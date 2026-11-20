import Foundation

/// Chat export for BeyGram, in the layout of the Android export (`ChatExportStreamer.writeJson` and `writeHtml`): the
/// same keys in the same order, the same escaping, and the same HTML document, stylesheet and wording.
///
/// The writer is synchronous and streams: each message is written to the sink as it arrives, so the full history is
/// never held in memory. The caller pages the history newest first (100 per request), feeds each page here, checks for
/// cancellation, and calls `finish`. On failure or cancellation the caller deletes the destination document.
///
/// This module writes no files itself. The destination is supplied by the app, for example a document chosen through
/// `UIDocumentPickerViewController` in export mode.
public enum ChatExportFormat: Equatable {
    case json
    case html
}

extension ChatExportFormat {
    /// The document's file extension, which is also the name of its entry in an archive.
    var fileExtension: String {
        switch self {
        case .json:
            return "json"
        case .html:
            return "html"
        }
    }
}

public enum ChatExportRefusal: Error, Equatable {
    /// Secret chats are never exported.
    case secretChat
    /// Chats with protected content (saving forbidden) are never exported.
    case protectedContent
    /// The date range is empty or reversed. Android refuses it too.
    case invalidDateRange
}

/// A chat as the export header names it. `kind` is the Android `exportKind`: "private", "group", "channel" or
/// "unknown". `id` is TDLib's chat id: a user keeps its id, a basic group is negative, and a channel or supergroup is
/// -1000000000000 minus its id.
public struct ChatExportChat: Equatable {
    public var id: Int64
    public var title: String
    public var kind: String

    public init(id: Int64, title: String, kind: String) {
        self.id = id
        self.title = title
        self.kind = kind
    }
}

public struct ChatExportHeader: Equatable {
    /// The account the export came from, so a user with several accounts knows which one it was.
    public var accountLabel: String
    public var chat: ChatExportChat
    public var exportedAt: Date
    /// True for an archive that holds media. Written as `mediaRequested`.
    public var mediaRequested: Bool

    public init(accountLabel: String, chat: ChatExportChat, exportedAt: Date, mediaRequested: Bool = false) {
        self.accountLabel = accountLabel
        self.chat = chat
        self.exportedAt = exportedAt
        self.mediaRequested = mediaRequested
    }
}

public struct ChatExportMessage: Equatable {
    public var id: Int64
    public var date: Date
    public var isOutgoing: Bool
    /// The sender's id as TDLib writes it, or 0 when there is no sender.
    public var senderId: Int64
    public var senderName: String
    public var text: String
    public var isEdited: Bool
    /// The text of a service event. Nil for any other message, which is how the Android export tells them apart.
    public var serviceText: String?
    public var replyToMessageId: Int64?
    /// False when Telegram forbids saving this message. Such messages are skipped and counted.
    public var canBeSaved: Bool
    /// The file attached to the message, if any.
    public var attachment: ChatExportAttachment?

    public init(
        id: Int64,
        date: Date,
        isOutgoing: Bool = false,
        senderId: Int64 = 0,
        senderName: String,
        text: String,
        isEdited: Bool = false,
        serviceText: String? = nil,
        replyToMessageId: Int64? = nil,
        canBeSaved: Bool = true,
        attachment: ChatExportAttachment? = nil
    ) {
        self.id = id
        self.date = date
        self.isOutgoing = isOutgoing
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.isEdited = isEdited
        self.serviceText = serviceText
        self.replyToMessageId = replyToMessageId
        self.canBeSaved = canBeSaved
        self.attachment = attachment
    }
}

/// Half-open date range in whole days, with the same semantics as chat search: the start day is included and the end
/// day is excluded. Days are taken in `calendar`'s time zone. The JSON `range` holds the bounds in Unix seconds, as the
/// Android export does.
public struct ChatExportRange: Equatable {
    public var startDay: Date?
    public var endDay: Date?
    public var calendar: Calendar

    public init(startDay: Date? = nil, endDay: Date? = nil, calendar: Calendar = .current) {
        self.startDay = startDay
        self.endDay = endDay
        self.calendar = calendar
    }

    /// The lower bound in Unix seconds, inclusive. Nil when the range is open at the start.
    public var fromSeconds: Int64? {
        guard let startDay = startDay else {
            return nil
        }
        return Self.unixSeconds(calendar.startOfDay(for: startDay))
    }

    /// The upper bound in Unix seconds, exclusive. Nil when the range is open at the end.
    public var toSeconds: Int64? {
        guard let endDay = endDay else {
            return nil
        }
        return Self.unixSeconds(calendar.startOfDay(for: endDay))
    }

    /// Android's `hasValidDateRange`: equal or reversed bounds describe no messages, so they are refused.
    public var isValid: Bool {
        guard let from = fromSeconds, let to = toSeconds else {
            return true
        }
        return from < to
    }

    /// Android's `includesDate`. With no bound set, every message is inside. With a bound set, a message without a
    /// date (zero or less) is outside.
    public func contains(_ date: Date) -> Bool {
        guard fromSeconds != nil || toSeconds != nil else {
            return true
        }
        let seconds = Self.unixSeconds(date)
        if seconds <= 0 {
            return false
        }
        if let from = fromSeconds, seconds < from {
            return false
        }
        if let to = toSeconds, seconds >= to {
            return false
        }
        return true
    }

    /// Whole Unix seconds of a date, rounded down.
    static func unixSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
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
    /// Media files copied into the archive. Zero for a document written without media.
    public var mediaFiles: Int = 0
    /// Media files skipped by the limits, or because they could not be opened.
    public var skippedMedia: Int = 0
}

public final class ChatExportWriter {
    private let format: ChatExportFormat
    private let header: ChatExportHeader
    private let range: ChatExportRange
    private let sink: ChatExportSink
    private var hasWrittenMessage = false
    private var summary = ChatExportSummary(exportedMessages: 0, skippedNotSaveable: 0, skippedOutOfRange: 0)
    private var isFinished = false

    /// Android's `formatExportTimestamp`: local time as `yyyy-MM-dd HH:mm`.
    private static let localTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// The date and time part of `Instant.toString()`. `javaInstantString` adds the fraction and the `Z`.
    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
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

    /// Writes the opening of the document. A date range that Android refuses is refused here, before anything is written.
    public func begin() throws {
        guard range.isValid else {
            throw ChatExportRefusal.invalidDateRange
        }
        switch format {
        case .json:
            try writeString(Self.jsonOpening(header: header, range: range))
        case .html:
            try writeString(htmlOpening())
        }
    }

    /// True when `append` would write the message: it is inside the date range and Telegram allows saving it.
    public func accepts(_ message: ChatExportMessage) -> Bool {
        range.contains(message.date) && message.canBeSaved
    }

    /// Appends one message. `mediaPath` is the archive path of its file when the file was copied, and is written as
    /// `exportedPath`. Returns false when the message was skipped.
    @discardableResult
    public func append(_ message: ChatExportMessage, mediaPath: String? = nil) throws -> Bool {
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
            // Android writes a comma before every message but the first, and starts each message on its own line.
            if hasWrittenMessage {
                try writeString(",")
            }
            try writeString("\n" + Self.jsonMessage(message, mediaPath: mediaPath))
        case .html:
            try writeString(Self.htmlMessage(message, mediaPath: mediaPath))
        }
        hasWrittenMessage = true
        summary.exportedMessages += 1
        return true
    }

    /// Closes the document and returns the counts. `mediaFiles` and `skippedMedia` come from the archive job, and a
    /// document written without media passes zero. Call only after a successful run.
    public func finish(mediaFiles: Int = 0, skippedMedia: Int = 0) throws -> ChatExportSummary {
        summary.mediaFiles = mediaFiles
        summary.skippedMedia = skippedMedia
        switch format {
        case .json:
            try writeString(jsonClosing())
        case .html:
            try writeString(htmlClosing())
        }
        isFinished = true
        return summary
    }

    // MARK: - JSON, as the Android export writes it

    private static func jsonOpening(header: ChatExportHeader, range: ChatExportRange) -> String {
        var out = "{\n\"format\":\"beygram-chat-export\",\n\"version\":1,\n\"exportedAt\":"
        out += jsonString(javaInstantString(header.exportedAt))
        out += ",\n\"sourceAccount\":" + jsonString(header.accountLabel)
        out += ",\n\"chat\":{\"id\":\(header.chat.id),\"title\":" + jsonString(header.chat.title)
        out += ",\"kind\":" + jsonString(header.chat.kind)
        out += "},\n\"range\":{\"from\":" + optionalSeconds(range.fromSeconds)
        out += ",\"to\":" + optionalSeconds(range.toSeconds)
        out += "},\n\"mediaRequested\":" + boolText(header.mediaRequested)
        out += ",\n\"messages\":["
        return out
    }

    private static func jsonMessage(_ message: ChatExportMessage, mediaPath: String?) -> String {
        let seconds = ChatExportRange.unixSeconds(message.date)
        var out = "{\"id\":\(message.id),\"date\":\(seconds),\"dateIso\":"
        out += jsonString(exportIsoTimestamp(seconds))
        out += ",\"outgoing\":" + boolText(message.isOutgoing)
        out += ",\"sender\":{\"id\":\(message.senderId),\"name\":" + jsonString(message.senderName)
        out += "},\"text\":" + jsonString(message.text)
        out += ",\"edited\":" + boolText(message.isEdited)
        out += ",\"service\":" + boolText(message.serviceText != nil)
        out += ",\"replyToMessageId\":" + optionalReplyId(message.replyToMessageId)
        out += ",\"media\":" + jsonMedia(message.attachment, mediaPath: mediaPath)
        out += "}"
        return out
    }

    /// The `media` object with the Android field names, or null for a message without a file. `exportedPath` is null
    /// when the file is not in the archive.
    private static func jsonMedia(_ attachment: ChatExportAttachment?, mediaPath: String?) -> String {
        guard let attachment = attachment else {
            return "null"
        }
        var out = "{\"kind\":" + jsonString(attachment.kind.rawValue)
        out += ",\"fileName\":" + jsonString(attachment.fileName)
        out += ",\"mimeType\":" + jsonString(attachment.mimeType)
        out += ",\"bytes\":\(attachment.size)"
        out += ",\"durationSeconds\":\(attachment.durationSeconds)"
        out += ",\"width\":\(attachment.width)"
        out += ",\"height\":\(attachment.height)"
        out += ",\"exportedPath\":"
        if let mediaPath = mediaPath {
            out += jsonString(mediaPath)
        } else {
            out += "null"
        }
        out += "}"
        return out
    }

    private func jsonClosing() -> String {
        var out = "\n],\n\"summary\":{\"messages\":\(summary.exportedMessages)"
        out += ",\"mediaFiles\":\(summary.mediaFiles)"
        out += ",\"skippedSaveRestricted\":\(summary.skippedNotSaveable)"
        out += ",\"skippedMedia\":\(summary.skippedMedia)}\n}\n"
        return out
    }

    /// Port of Android `appendJsonString`. Quotes and backslashes are escaped, control characters and U+2028 and U+2029
    /// become \uXXXX, and everything else is written as it is.
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                out += "\\\""
            case 0x5C:
                out += "\\\\"
            case 0x08:
                out += "\\b"
            case 0x0C:
                out += "\\f"
            case 0x0A:
                out += "\\n"
            case 0x0D:
                out += "\\r"
            case 0x09:
                out += "\\t"
            case 0x00 ..< 0x20, 0x2028, 0x2029:
                out += "\\u" + hexDigits4(scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }

    private static func hexDigits4(_ value: UInt32) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    private static func boolText(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func optionalSeconds(_ value: Int64?) -> String {
        guard let value = value else {
            return "null"
        }
        return String(value)
    }

    private static func optionalReplyId(_ id: Int64?) -> String {
        guard let id = id, id > 0 else {
            return "null"
        }
        return String(id)
    }

    // MARK: - HTML, as the Android export writes it

    private func htmlOpening() -> String {
        var out = "<!doctype html>\n<html lang=\"und\">\n<head>\n<meta charset=\"utf-8\">\n"
        out += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        out += "<meta name=\"generator\" content=\"BeyGram\">\n<title>"
        out += Self.escapeHTML(header.chat.title)
        out += "</title>\n<style>" + Self.htmlStyle + "</style>\n</head>\n<body>\n<main>\n"
        out += "<header class=\"chat-header\">\n<h1>" + Self.escapeHTML(header.chat.title)
        out += "</h1>\n<p class=\"meta\">Source account: " + Self.escapeHTML(header.accountLabel)
        out += "</p>\n<p class=\"meta\">Exported " + Self.escapeHTML(Self.javaInstantString(header.exportedAt))
        out += "</p>\n<p class=\"meta\">Date range: " + Self.escapeHTML(htmlDateRange())
        out += "</p>\n<p class=\"warning\">This file contains private chat data and is not protected by BeyGram. "
        out += "Store it securely.</p>\n</header>\n<section class=\"messages\">\n"
        return out
    }

    private func htmlDateRange() -> String {
        guard let from = range.fromSeconds else {
            guard let to = range.toSeconds else {
                return "all messages"
            }
            return "until " + Self.formatExportTimestamp(to)
        }
        guard let to = range.toSeconds else {
            return "from " + Self.formatExportTimestamp(from)
        }
        return Self.formatExportTimestamp(from) + " \u{2013} " + Self.formatExportTimestamp(to)
    }

    private func htmlClosing() -> String {
        let counts = "Exported \(summary.exportedMessages) messages and \(summary.mediaFiles) media files. "
            + "Skipped \(summary.skippedNotSaveable) save-restricted messages and \(summary.skippedMedia) unavailable media files."
        var out = "</section>\n<footer class=\"chat-footer\">\n<p>" + Self.escapeHTML(counts) + "</p>\n</footer>\n"
        out += "</main>\n</body>\n</html>\n"
        return out
    }

    private static func htmlMessage(_ message: ChatExportMessage, mediaPath: String?) -> String {
        let seconds = ChatExportRange.unixSeconds(message.date)
        var out = "<article class=\"message " + (message.isOutgoing ? "outgoing" : "incoming")
        if message.serviceText != nil {
            out += " service"
        }
        let senderName = isBlank(message.senderName) ? "Unknown sender" : message.senderName
        out += "\">\n<header><span class=\"sender\">" + escapeHTML(senderName)
        out += "</span> <time datetime=\"" + escapeHTML(exportIsoTimestamp(seconds))
        out += "\">" + escapeHTML(formatExportTimestamp(seconds)) + "</time>"
        if message.isEdited {
            out += " <span class=\"edited\">edited</span>"
        }
        out += "</header>\n"
        let text = message.serviceText ?? message.text
        if !isBlank(text) {
            out += "<div class=\"text\">" + escapeHTML(text) + "</div>\n"
        }
        if let attachment = message.attachment {
            out += attachmentFigure(attachment, mediaPath: mediaPath)
        }
        out += "</article>\n"
        return out
    }

    /// An image for an `image/*` type, a link for any other type, and a note when the file is not in the archive.
    private static func attachmentFigure(_ attachment: ChatExportAttachment, mediaPath: String?) -> String {
        var out = "<figure class=\"attachment\">"
        if let mediaPath = mediaPath {
            let label = isBlank(attachment.fileName) ? attachment.kind.rawValue : attachment.fileName
            let href = escapeHTML(mediaHref(mediaPath))
            if attachment.mimeType.hasPrefix("image/") {
                out += "<img loading=\"lazy\" src=\"" + href + "\" alt=\"" + escapeHTML(label) + "\">"
            } else {
                out += "<a href=\"" + href + "\">" + escapeHTML(label) + "</a>"
            }
        }
        let name = isBlank(attachment.fileName) ? "attachment" : attachment.fileName
        let size = attachment.size > 0 ? "\(attachment.size) bytes" : ""
        let caption = [attachment.kind.rawValue, name, size].filter { !isBlank($0) }.joined(separator: " \u{00B7} ")
        out += "<figcaption>" + escapeHTML(caption)
        if mediaPath == nil {
            out += " <span class=\"missing\">not included</span>"
        }
        out += "</figcaption></figure>\n"
        return out
    }

    /// Android `exportMediaHref`: each path segment is percent-encoded the way `URLEncoder` encodes it, and the spaces
    /// become %20. The slashes between the segments stay.
    static func mediaHref(_ entry: String) -> String {
        let segments = entry.split(separator: "/", omittingEmptySubsequences: false)
        return segments.map { segment -> String in
            var encoded = ""
            for byte in segment.utf8 {
                if isURLSafe(byte) {
                    encoded.append(Character(Unicode.Scalar(byte)))
                } else {
                    let hex = String(byte, radix: 16, uppercase: true)
                    encoded += "%" + (hex.count == 1 ? "0" + hex : hex)
                }
            }
            return encoded
        }.joined(separator: "/")
    }

    /// The bytes `URLEncoder` leaves alone: ASCII letters, digits, and `.`, `-`, `*` and `_`.
    private static func isURLSafe(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A, 0x2E, 0x2D, 0x2A, 0x5F:
            return true
        default:
            return false
        }
    }

    /// Android `formatExportTimestamp`: local time as `yyyy-MM-dd HH:mm`, or empty when the time is not known.
    static func formatExportTimestamp(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }
        return localTimestampFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    /// Android `exportIsoTimestamp`: the instant in UTC, or empty when the time is not known.
    static func exportIsoTimestamp(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }
        return javaInstantString(Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    /// Java's `Instant.toString()`: UTC with a `Z`, and a fraction only when the instant has one.
    static func javaInstantString(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        let wholeSeconds = interval.rounded(.down)
        let milliseconds = Int(((interval - wholeSeconds) * 1000).rounded(.down))
        var text = utcFormatter.string(from: Date(timeIntervalSince1970: wholeSeconds))
        if milliseconds > 0 {
            let digits = String(milliseconds)
            text += "." + String(repeating: "0", count: max(0, 3 - digits.count)) + digits
        }
        return text + "Z"
    }

    /// Kotlin's `isBlank`: empty, or only whitespace.
    static func isBlank(_ value: String) -> Bool {
        value.allSatisfy { $0.isWhitespace }
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

    /// The stylesheet of the Android export, unchanged.
    private static let htmlStyle = """
    :root { color-scheme: light dark; }
    body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; background: #f4f5f7; color: #17181a; }
    main { max-width: 860px; margin: 0 auto; padding: 24px 16px 48px; }
    .chat-header, .chat-footer { background: #fff; border-radius: 16px; padding: 18px 20px; margin-bottom: 16px; }
    h1 { font-size: 22px; margin: 0 0 8px; }
    .meta { color: #5f6368; font-size: 13px; margin: 3px 0; }
    .warning { color: #7a4b00; background: #fff4d6; border-radius: 10px; padding: 10px 12px; font-size: 13px; margin: 12px 0 0; }
    .messages { display: flex; flex-direction: column; gap: 10px; }
    .message { background: #fff; border-radius: 14px; padding: 12px 14px; max-width: 78%; }
    .message.outgoing { align-self: flex-end; background: #dcf2e6; }
    .message.service { align-self: center; max-width: 90%; background: #e7e9ed; color: #4b4f55; text-align: center; }
    .message header { display: flex; gap: 8px; align-items: baseline; margin-bottom: 5px; font-size: 12px; color: #5f6368; }
    .sender { font-weight: 600; color: #1f6f4d; }
    .text { white-space: pre-wrap; overflow-wrap: anywhere; font-size: 15px; line-height: 1.42; }
    .attachment { margin: 10px 0 0; }
    .attachment img { display: block; max-width: 100%; max-height: 420px; border-radius: 10px; }
    .attachment figcaption { font-size: 12px; color: #5f6368; margin-top: 4px; }
    .missing { color: #8a6d3b; }
    .chat-footer { color: #5f6368; font-size: 12px; }
    @media (prefers-color-scheme: dark) {
        body { background: #101214; color: #e8eaed; }
        .chat-header, .chat-footer, .message { background: #1c1f23; }
        .message.outgoing { background: #153c2c; }
        .message.service { background: #262a2f; color: #c2c7ce; }
        .sender { color: #7fd4ab; }
        .warning { background: #3a2c10; color: #ffe08a; }
        .meta, .message header, .attachment figcaption, .chat-footer { color: #aeb4bc; }
    }\
    """
}
