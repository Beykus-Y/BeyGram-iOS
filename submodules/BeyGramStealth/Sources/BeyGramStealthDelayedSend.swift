import Foundation

/// Where a message held by the local delayed send is. Only `queued` waits for its time. A message is stored as `dispatching`
/// before its request, so a restart cannot send it again by itself. The raw values are stored, so they must not change.
public enum BeyGramStealthDelayedStatus: String, Codable, Equatable, Sendable {
    /// Waiting for its time, and for the app to run with a chat of the account open.
    case queued
    /// The send request is in flight.
    case dispatching
    /// The request failed, with a reason. It is not retried by itself.
    case failed
    /// The app stopped during the request, so the message may already be on the server. Only the user sends it again.
    case uncertain
}

/// Why a locally delayed message failed. The raw values are stored, so they must not change.
public enum BeyGramStealthDelayedFailure: String, Codable, Equatable, Sendable, CaseIterable {
    /// The message stayed in the queue longer than `BeyGramStealthDelayedSendQueue.retentionMillis`, so it was not sent.
    case expired
    /// The request could not reach the server.
    case network
    /// The server did not accept the message.
    case server

    /// The key of the dialog text for this failure. The UI adds the strings in both languages (docs/stealth-ui-contract.md, section 10).
    public var localizationKey: String {
        switch self {
        case .expired:
            return "BeyGram.Stealth.Delay.Failure.Expired"
        case .network:
            return "BeyGram.Stealth.Delay.Failure.Network"
        case .server:
            return "BeyGram.Stealth.Delay.Failure.Server"
        }
    }
}

/// Why a change to the local delayed send was refused. A call that throws changes nothing.
public enum BeyGramStealthDelayedQueueError: Error, Equatable, Sendable {
    /// The account already holds the most messages allowed. The caller keeps the draft.
    case full
    /// The text is empty or too long, or the delay is outside 1...3600 seconds.
    case invalidInput
    /// The queue could not be written to disk.
    case storage
}

/// One message held by the local delayed send. Times are wall-clock milliseconds from the device clock: the queue never asks
/// the server for the time, so a changed device clock moves the due time. `reconcile` limits what a jump back can do.
public struct BeyGramStealthDelayedEntry: Codable, Equatable, Sendable {
    public let id: String
    public let accountPeerId: Int64
    public let chatPeerId: Int64
    /// The forum topic the message is sent to, or 0 for none. Android keeps it too.
    public let topicId: Int64
    /// The message it replies to in the chat, or 0 for none.
    public let replyToMessageId: Int64
    /// Whether the message is sent without a notification.
    public let disableNotification: Bool
    public var text: String
    public var createdAtMillis: Int64
    public var notBeforeMillis: Int64
    public var status: BeyGramStealthDelayedStatus
    public var failure: BeyGramStealthDelayedFailure?
    /// True once the user chose "Send now" for this message. That choice is the user's agreement to send, so the dispatch may
    /// send it past a stealth refusal of an automatic send (the meaning of `sendNowConsent` in `resendMessages`).
    public var sendNowConsented: Bool
}

/// The local delayed send of one account: a message the user holds back for a few seconds before it goes out. The queue keeps
/// the messages on disk, one file per account, and sends nothing itself. A dispatcher (TelegramCore, not wired yet) reads
/// `dueEntries`, marks each message `markDispatching` before its request, and then reports `markSent`, `markFailed` or
/// `markUncertain`. iOS can suspend or end the app at any time, so a message goes out only while the app runs with a chat of
/// the account open, and nothing here promises the exact time.
public final class BeyGramStealthDelayedSendQueue {
    /// The most messages one account holds at once, failed ones included until the user deals with them.
    public static let maximumEntries = 50
    /// A queued message older than this expires: it is marked failed (`expired`) and is not sent. Its text is kept.
    public static let retentionMillis: Int64 = 24 * 60 * 60 * 1000
    /// The longest delay the user may choose, in seconds.
    public static let maximumDelaySeconds = 3600
    /// The Telegram text limit, counted in UTF-16 code units.
    public static let maximumTextLength = 4096

    private let lock = NSLock()
    private let accountPeerId: Int64
    private let directory: URL
    private let fileURL: URL
    private var stored: [BeyGramStealthDelayedEntry]
    /// Queued messages whose time had passed when the queue was loaded with "hide online" on. They wait for the user.
    private var held: Set<String>

    /// Loads the account's queue. A queued message whose time passed while the app was not running is due now, unless `hideOnline`
    /// is on: then it waits for the user, because sending would show the account as online. A file that cannot be read is moved
    /// beside the queue as `delayed-send-<account>.unreadable.json`, and the queue starts empty.
    public init(directory: URL, accountPeerId: Int64, hideOnline: Bool, nowMillis: Int64) {
        let fileURL = directory.appendingPathComponent("delayed-send-\(accountPeerId).json", isDirectory: false)
        var loaded: [BeyGramStealthDelayedEntry] = []
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode([BeyGramStealthDelayedEntry].self, from: data) {
                loaded = decoded
            } else {
                let aside = directory.appendingPathComponent("delayed-send-\(accountPeerId).unreadable.json", isDirectory: false)
                _ = try? FileManager.default.removeItem(at: aside)
                _ = try? FileManager.default.moveItem(at: fileURL, to: aside)
            }
        }
        let reconciled = BeyGramStealthDelayedSendQueue.reconcile(loaded, nowMillis: nowMillis, hideOnline: hideOnline)
        self.accountPeerId = accountPeerId
        self.directory = directory
        self.fileURL = fileURL
        self.stored = reconciled.entries
        self.held = reconciled.held
        if reconciled.entries != loaded {
            _ = try? BeyGramStealthDelayedSendQueue.write(reconciled.entries, to: fileURL, directory: directory)
        }
    }

    /// All messages of the account, oldest first.
    public func entries() -> [BeyGramStealthDelayedEntry] {
        lock.lock()
        defer { lock.unlock() }
        return stored.sorted { $0.createdAtMillis < $1.createdAtMillis }
    }

    /// The queued messages that may go out now, oldest first (see `isDue`). Expired messages count as failed here, as `expireOverdue`
    /// would record them, so an expired message is never returned.
    public func dueEntries(nowMillis: Int64) -> [BeyGramStealthDelayedEntry] {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = BeyGramStealthDelayedSendQueue.markingExpired(stored, nowMillis: nowMillis)
        let heldIds = held
        return snapshot
            .filter { BeyGramStealthDelayedSendQueue.isDue($0, among: snapshot, held: heldIds, nowMillis: nowMillis) }
            .sorted { $0.createdAtMillis < $1.createdAtMillis }
    }

    /// The queued messages held at load under "hide online". Each waits until `sendNow` releases it.
    public func heldAtLoad() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return held
    }

    /// Adds a message that is sent after `delaySeconds`. The message is on disk when this returns, so the caller may clear the draft then.
    /// The topic, the reply and the silent flag are kept, as Android keeps them. Formatting is not kept yet (docs/stealth-ui-contract.md, section 10).
    public func enqueue(chatPeerId: Int64, text: String, delaySeconds: Int, nowMillis: Int64, topicId: Int64 = 0, replyToMessageId: Int64 = 0, disableNotification: Bool = false) throws -> BeyGramStealthDelayedEntry {
        lock.lock()
        defer { lock.unlock() }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf16.count <= BeyGramStealthDelayedSendQueue.maximumTextLength,
              (1 ... BeyGramStealthDelayedSendQueue.maximumDelaySeconds).contains(delaySeconds) else {
            throw BeyGramStealthDelayedQueueError.invalidInput
        }
        var next = BeyGramStealthDelayedSendQueue.markingExpired(stored, nowMillis: nowMillis)
        guard next.count < BeyGramStealthDelayedSendQueue.maximumEntries else {
            throw BeyGramStealthDelayedQueueError.full
        }
        let entry = BeyGramStealthDelayedEntry(
            id: UUID().uuidString,
            accountPeerId: accountPeerId,
            chatPeerId: chatPeerId,
            topicId: topicId,
            replyToMessageId: replyToMessageId,
            disableNotification: disableNotification,
            text: text,
            createdAtMillis: nowMillis,
            notBeforeMillis: nowMillis + Int64(delaySeconds) * 1000,
            status: .queued,
            failure: nil,
            sendNowConsented: false
        )
        next.append(entry)
        try commit(next, held: held)
        return entry
    }

    /// Removes a message that is not in flight and returns it, so its text can go back to the draft. Returns nil when the message
    /// is unknown or in flight.
    public func cancel(id: String) throws -> BeyGramStealthDelayedEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let current = stored.first(where: { $0.id == id }), current.status != .dispatching else {
            return nil
        }
        try commit(stored.filter { $0.id != id }, held: held)
        return current
    }

    /// Changes the text of a message that is not in flight. Its due time and status stay. Returns false when the message is unknown
    /// or in flight.
    public func edit(id: String, text: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = stored.firstIndex(where: { $0.id == id }), stored[index].status != .dispatching else {
            return false
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf16.count <= BeyGramStealthDelayedSendQueue.maximumTextLength else {
            throw BeyGramStealthDelayedQueueError.invalidInput
        }
        var next = stored
        next[index].text = text
        try commit(next, held: held)
        return true
    }

    /// The user chose to send the message now. A queued message goes out before its time. A failed or uncertain one is sent again,
    /// and its retention starts again. A message in flight is left alone, and the call returns false for it.
    public func sendNow(id: String, nowMillis: Int64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = stored.firstIndex(where: { $0.id == id }), stored[index].status != .dispatching else {
            return false
        }
        var next = stored
        if next[index].status != .queued || BeyGramStealthDelayedSendQueue.isExpired(next[index], nowMillis: nowMillis) {
            next[index].createdAtMillis = nowMillis
        }
        next[index].status = .queued
        next[index].failure = nil
        next[index].notBeforeMillis = nowMillis
        next[index].sendNowConsented = true
        var nextHeld = held
        nextHeld.remove(id)
        try commit(next, held: nextHeld)
        return true
    }

    /// Marks a due message as in flight before its request. It is written to disk first, so a restart finds it `uncertain`, not queued.
    /// Returns false when the message is unknown, not due, held, expired, or held back by the order of its chat.
    public func markDispatching(id: String, nowMillis: Int64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = BeyGramStealthDelayedSendQueue.markingExpired(stored, nowMillis: nowMillis)
        guard let index = snapshot.firstIndex(where: { $0.id == id }),
              BeyGramStealthDelayedSendQueue.isDue(snapshot[index], among: snapshot, held: held, nowMillis: nowMillis) else {
            return false
        }
        var next = snapshot
        next[index].status = .dispatching
        try commit(next, held: held)
        return true
    }

    /// Removes a message that the server accepted. Returns false when the message is not in flight.
    public func markSent(id: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let current = stored.first(where: { $0.id == id }), current.status == .dispatching else {
            return false
        }
        try commit(stored.filter { $0.id != id }, held: held)
        return true
    }

    /// Marks a message in flight as failed, with its reason. It keeps its text until the user sends it again or deletes it.
    public func markFailed(id: String, failure: BeyGramStealthDelayedFailure) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = stored.firstIndex(where: { $0.id == id }), stored[index].status == .dispatching else {
            return false
        }
        var next = stored
        next[index].status = .failed
        next[index].failure = failure
        try commit(next, held: held)
        return true
    }

    /// Marks a message in flight as uncertain: the request was interrupted, so the message may already be on the server.
    public func markUncertain(id: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = stored.firstIndex(where: { $0.id == id }), stored[index].status == .dispatching else {
            return false
        }
        var next = stored
        next[index].status = .uncertain
        try commit(next, held: held)
        return true
    }

    /// Marks the queued messages older than the retention as failed (`expired`). Returns how many changed.
    public func expireOverdue(nowMillis: Int64) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let next = BeyGramStealthDelayedSendQueue.markingExpired(stored, nowMillis: nowMillis)
        let changed = stored.indices.filter { stored[$0].status != next[$0].status }.count
        guard changed > 0 else {
            return 0
        }
        try commit(next, held: held)
        return changed
    }

    /// Deletes every delayed message of the account, for logout or the removal of the account.
    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            throw BeyGramStealthDelayedQueueError.storage
        }
        stored = []
        held = []
    }

    /// Writes `next` and only then makes it the state, so a failed write changes nothing. Called with the lock held.
    private func commit(_ next: [BeyGramStealthDelayedEntry], held nextHeld: Set<String>) throws {
        do {
            try BeyGramStealthDelayedSendQueue.write(next, to: fileURL, directory: directory)
        } catch {
            throw BeyGramStealthDelayedQueueError.storage
        }
        let queuedIds = Set(next.filter { $0.status == .queued }.map { $0.id })
        stored = next
        held = nextHeld.intersection(queuedIds)
    }

    private static func write(_ entries: [BeyGramStealthDelayedEntry], to fileURL: URL, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    /// The restart rules. A message that was in flight may already be on the server, so it becomes `uncertain`. A queued message
    /// older than the retention expires. A queued message whose due time lies further away than its delay allows is brought
    /// forward (a wall clock that jumped back). With `hideOnline`, the messages due at load are held for the user.
    private static func reconcile(_ entries: [BeyGramStealthDelayedEntry], nowMillis: Int64, hideOnline: Bool) -> (entries: [BeyGramStealthDelayedEntry], held: Set<String>) {
        let inFlightFixed = entries.map { (entry: BeyGramStealthDelayedEntry) -> BeyGramStealthDelayedEntry in
            guard entry.status == .dispatching else {
                return entry
            }
            var next = entry
            next.status = .uncertain
            return next
        }
        let expiredFixed = BeyGramStealthDelayedSendQueue.markingExpired(inFlightFixed, nowMillis: nowMillis)
        let clamped = expiredFixed.map { (entry: BeyGramStealthDelayedEntry) -> BeyGramStealthDelayedEntry in
            guard entry.status == .queued else {
                return entry
            }
            return BeyGramStealthDelayedSendQueue.clampedNotBefore(entry, nowMillis: nowMillis)
        }
        var held = Set<String>()
        if hideOnline {
            for entry in clamped where entry.status == .queued && entry.notBeforeMillis <= nowMillis {
                held.insert(entry.id)
            }
        }
        return (clamped, held)
    }

    /// When the wall clock has jumped back, a message due much later than its delay allows is brought forward to one delay from now.
    private static func clampedNotBefore(_ entry: BeyGramStealthDelayedEntry, nowMillis: Int64) -> BeyGramStealthDelayedEntry {
        let delayMillis = max(entry.notBeforeMillis - entry.createdAtMillis, 0)
        guard entry.notBeforeMillis > nowMillis + 2 * delayMillis else {
            return entry
        }
        var next = entry
        next.notBeforeMillis = nowMillis + delayMillis
        return next
    }

    /// Whether a queued message may go out now: its time has come, it is not held, and no older message of its chat holds it back.
    /// A message the user chose to send now is not held back by the order, as on Android. `entries` must already have its expired
    /// messages marked failed (`markingExpired`).
    private static func isDue(_ entry: BeyGramStealthDelayedEntry, among entries: [BeyGramStealthDelayedEntry], held: Set<String>, nowMillis: Int64) -> Bool {
        guard entry.status == .queued, entry.notBeforeMillis <= nowMillis, !held.contains(entry.id) else {
            return false
        }
        if entry.sendNowConsented {
            return true
        }
        return !entries.contains { other in
            other.chatPeerId == entry.chatPeerId
                && other.createdAtMillis <= entry.createdAtMillis
                && holdsBack(other, held: held)
        }
    }

    /// Whether a message holds back the newer waiting messages of its chat: it is held at load, in flight, uncertain or failed.
    /// An expired message does not. Android removes such a message, and here it is kept only for its text.
    private static func holdsBack(_ other: BeyGramStealthDelayedEntry, held: Set<String>) -> Bool {
        if held.contains(other.id) {
            return true
        }
        switch other.status {
        case .queued:
            return false
        case .dispatching, .uncertain:
            return true
        case .failed:
            return other.failure != BeyGramStealthDelayedFailure.expired
        }
    }

    private static func isExpired(_ entry: BeyGramStealthDelayedEntry, nowMillis: Int64) -> Bool {
        return entry.status == .queued && nowMillis - entry.createdAtMillis > retentionMillis
    }

    private static func markingExpired(_ entries: [BeyGramStealthDelayedEntry], nowMillis: Int64) -> [BeyGramStealthDelayedEntry] {
        return entries.map { (entry: BeyGramStealthDelayedEntry) -> BeyGramStealthDelayedEntry in
            guard BeyGramStealthDelayedSendQueue.isExpired(entry, nowMillis: nowMillis) else {
                return entry
            }
            var next = entry
            next.status = .failed
            next.failure = .expired
            return next
        }
    }
}
