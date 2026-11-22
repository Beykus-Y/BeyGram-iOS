import Foundation

/// In-memory ring buffer of structured diagnostic events for the bug report (port of Android `StructuredEventLog`).
///
/// Producers record fixed codes and non-secret attributes: states, counters, error codes. Free text from logs or
/// user data does not belong here. The report redacts what it reads anyway (see `BugReportBuilder`).
public final class BugReportEventLog {
    public struct Entry: Equatable {
        public let seq: Int64
        /// Seconds since 1970 with a fraction.
        public let at: Double
        public let kind: BugReportEventKind
        public let severity: BugReportSeverity
        public let code: String
        public let message: String
        public let attrs: [String: String]
    }

    public static let defaultCapacity = 200

    /// The process-wide log that the bug report reads.
    public static let shared = BugReportEventLog()

    private let capacity: Int
    private let clock: () -> Double
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var nextSeq: Int64 = 0
    private var overflowed = false

    /// - Parameters:
    ///   - capacity: how many events are kept. The oldest are dropped first.
    ///   - clock: seconds since 1970. Injected for tests.
    public init(
        capacity: Int = BugReportEventLog.defaultCapacity,
        clock: @escaping () -> Double = { Date().timeIntervalSince1970 }
    ) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        self.clock = clock
    }

    /// Records one event. Safe to call from any thread.
    public func record(
        kind: BugReportEventKind,
        severity: BugReportSeverity = .info,
        code: String,
        message: String = "",
        attrs: [String: String] = [:]
    ) {
        lock.lock()
        defer { lock.unlock() }
        if entries.count == capacity {
            entries.removeFirst()
            overflowed = true
        }
        entries.append(
            Entry(
                seq: nextSeq,
                at: clock(),
                kind: kind,
                severity: severity,
                code: code,
                message: message,
                attrs: attrs
            )
        )
        nextSeq += 1
    }

    /// The events still in the buffer, oldest first.
    public func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// True when the buffer has dropped events since the process started.
    public var hasOverflowed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return overflowed
    }

    /// How many events were recorded since the process started, including the ones already dropped.
    public var totalRecorded: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return nextSeq
    }
}
