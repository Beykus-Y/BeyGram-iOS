import Foundation

/// Chat export for BeyGram (port of the Android `ChatExportWriter` contract, docs/chat-export.md).
///
/// The writer is synchronous and streams: each message is serialized and written to the sink
/// immediately, so the full history is never held in memory. The caller pages the history
/// (newest to oldest, 100 per request), feeds each page here, checks for cancellation, and
/// closes the sink. On failure or cancellation the caller deletes the destination document.
///
/// This module writes no files itself. The destination is supplied by the app, for example a
/// document chosen through `UIDocumentPickerViewController` in export mode.
public enum ChatExportFormat: Equatable {
    case json
    case html
}

public enum ChatExportRefusal: Error, Equatable {
    /// Secret chats are never exported.
    case secretChat
    /// Chats with protected content (saving forbidden) are never exported.
    case protectedContent
}

public struct ChatExportHeader: Equatable {
    /// Account label, so a user with several accounts knows which one was exported.
    public var accountLabel: String
    public var chatTitle: String
    public var exportedAt: Date

    public init(accountLabel: String, chatTitle: String, exportedAt: Date) {
        self.accountLabel = accountLabel
        self.chatTitle = chatTitle
        self.exportedAt = exportedAt
    }
}

public struct ChatExportMessage: Equatable {
    public var id: Int64
    public var date: Date
    public var senderName: String
    public var text: String
    public var isService: Bool
    public var isEdited: Bool
    public var replyToMessageId: Int64?
    /// Short media description, such as "photo" or "document". Media bytes are not part of this module.
    public var mediaKind: String?
    /// False when Telegram forbids saving this message. Such messages are skipped and counted.
    public var canBeSaved: Bool

    public init(
        id: Int64,
        date: Date,
        senderName: String,
        text: String,
        isService: Bool = false,
        isEdited: Bool = false,
        replyToMessageId: Int64? = nil,
        mediaKind: String? = nil,
        canBeSaved: Bool = true
    ) {
        self.id = id
        self.date = date
        self.senderName = senderName
        self.text = text
        self.isService = isService
        self.isEdited = isEdited
        self.replyToMessageId = replyToMessageId
        self.mediaKind = mediaKind
        self.canBeSaved = canBeSaved
    }
}

/// Half-open date range with the same semantics as chat search: the start day is included,
/// the end day is excluded. Days are taken in `calendar`'s time zone.
public struct ChatExportRange: Equatable {
    public var startDay: Date?
    public var endDay: Date?
    public var calendar: Calendar

    public init(startDay: Date? = nil, endDay: Date? = nil, calendar: Calendar = .current) {
        self.startDay = startDay
        self.endDay = endDay
        self.calendar = calendar
    }

    public func contains(_ date: Date) -> Bool {
        if let startDay = startDay, date < calendar.startOfDay(for: startDay) {
            return false
        }
        if let endDay = endDay, date >= calendar.startOfDay(for: endDay) {
            return false
        }
        return true
    }
}

public protocol ChatExportSink: AnyObject {
    /// Appends bytes to the destination. Throwing aborts the export.
    func write(_ data: Data) throws
}

public struct ChatExportSummary: Equatable {
    public var exportedMessages: Int
    /// Messages Telegram forbids saving (`canBeSaved == false`).
    public var skippedNotSaveable: Int
    /// Messages outside the requested date range.
    public var skippedOutOfRange: Int
}

public final class ChatExportWriter {
    private let format: ChatExportFormat
    private let header: ChatExportHeader
    private let range: ChatExportRange
    private let sink: ChatExportSink
    private var hasWrittenMessage = false
    private var summary = ChatExportSummary(exportedMessages: 0, skippedNotSaveable: 0, skippedOutOfRange: 0)
    private var isFinished = false

    private static let utcFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return formatter
    }()

    public init(format: ChatExportFormat, header: ChatExportHeader, range: ChatExportRange, sink: ChatExportSink) {
        self.format = format
        self.header = header
        self.range = range
        self.sink = sink
    }

    /// Call before anything else. Refuses secret chats and protected content before a target is opened.
    public static func checkTarget(isSecretChat: Bool, hasProtectedContent: Bool) throws {
        if isSecretChat {
            throw ChatExportRefusal.secretChat
        }
        if hasProtectedContent {
            throw ChatExportRefusal.protectedContent
        }
    }

    public func begin() throws {
        switch format {
        case .json:
            try writeString("{\"account\":")
            try writeJSONValue(header.accountLabel)
            try writeString(",\"chat\":")
            try writeJSONValue(header.chatTitle)
            try writeString(",\"exportedAt\":")
            try writeJSONValue(Self.utcFormatter.string(from: header.exportedAt))
            try writeString(",\"messages\":[")
        case .html:
            try writeString("<!doctype html><html><head><meta charset=\"utf-8\"><title>")
            try writeString(Self.escapeHTML(header.chatTitle))
            try writeString("</title></head><body><h1>")
            try writeString(Self.escapeHTML(header.chatTitle))
            try writeString("</h1><p>")
            try writeString(Self.escapeHTML(header.accountLabel))
            try writeString(" · ")
            try writeString(Self.escapeHTML(Self.utcFormatter.string(from: header.exportedAt)))
            try writeString("</p><table><thead><tr><th>id</th><th>UTC</th><th>Local</th><th>Sender</th><th>Text</th></tr></thead><tbody>")
        }
    }

    /// Appends one message. Returns false when the message was skipped.
    @discardableResult
    public func append(_ message: ChatExportMessage) throws -> Bool {
        precondition(!isFinished, "append after finish")
        guard range.contains(message.date) else {
            summary.skippedOutOfRange += 1
            return false
        }
        guard message.canBeSaved else {
            summary.skippedNotSaveable += 1
            return false
        }
        switch format {
        case .json:
            if hasWrittenMessage {
                try writeString(",")
            }
            try writeJSONMessage(message)
        case .html:
            try writeHTMLRow(message)
        }
        hasWrittenMessage = true
        summary.exportedMessages += 1
        return true
    }

    /// Closes the document and returns the counts. Call only after a successful run.
    public func finish() throws -> ChatExportSummary {
        switch format {
        case .json:
            try writeString("]}")
        case .html:
            try writeString("</tbody></table></body></html>")
        }
        isFinished = true
        return summary
    }

    // MARK: - Serialization

    private func writeJSONMessage(_ message: ChatExportMessage) throws {
        var object: [String: Any] = [
            "id": message.id,
            "utc": Self.utcFormatter.string(from: message.date),
            "local": Self.localFormatter.string(from: message.date),
            "sender": message.senderName,
            "text": message.text,
            "service": message.isService,
            "edited": message.isEdited,
        ]
        if let replyTo = message.replyToMessageId {
            object["replyTo"] = replyTo
        }
        if let mediaKind = message.mediaKind {
            object["media"] = mediaKind
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        try sink.write(data)
    }

    private func writeJSONValue(_ value: String) throws {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [])
        // Strip the surrounding brackets of the one-element array.
        try sink.write(data.subdata(in: 1 ..< (data.count - 1)))
    }

    private func writeHTMLRow(_ message: ChatExportMessage) throws {
        var text = Self.escapeHTML(message.text)
        if let mediaKind = message.mediaKind {
            text = "[\(Self.escapeHTML(mediaKind))] " + text
        }
        if message.isEdited {
            text += " (edited)"
        }
        try writeString("<tr><td>\(message.id)</td><td>\(Self.escapeHTML(Self.utcFormatter.string(from: message.date)))</td><td>\(Self.escapeHTML(Self.localFormatter.string(from: message.date)))</td><td>\(Self.escapeHTML(message.senderName))</td><td>\(text)</td></tr>")
    }

    private func writeString(_ string: String) throws {
        try sink.write(Data(string.utf8))
    }

    static func escapeHTML(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        for character in input {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}
