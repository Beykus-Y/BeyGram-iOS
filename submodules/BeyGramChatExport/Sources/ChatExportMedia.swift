import Foundation

/// Media kinds, named as the Android `MediaKind` enum, so the JSON `kind` matches the Android export.
public enum ChatExportMediaKind: String, Equatable {
    case photo = "Photo"
    case video = "Video"
    case animation = "Animation"
    case sticker = "Sticker"
    case audio = "Audio"
    case document = "Document"
    case voice = "Voice"
    case videoNote = "VideoNote"

    /// The file name stem used when the original name is missing or unusable.
    var fallbackFileName: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case .animation: return "animation"
        case .sticker: return "sticker"
        case .audio: return "audio"
        case .document: return "document"
        case .voice: return "voice"
        case .videoNote: return "video_note"
        }
    }

    /// The extension used when neither the name nor the MIME type gives one.
    var defaultFileExtension: String {
        switch self {
        case .photo: return "jpg"
        case .video, .animation, .videoNote: return "mp4"
        case .sticker: return "webp"
        case .audio: return "mp3"
        case .voice: return "ogg"
        case .document: return "bin"
        }
    }
}

extension ChatExportFormat {
    /// The extension of the document entry inside the archive.
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .html: return "html"
        }
    }
}

/// A file attached to a message. The app supplies the bytes through `ChatExportFileProvider`. This value only describes them.
public struct ChatExportAttachment: Equatable {
    /// Identifies the file to the provider, for example the Telegram media id.
    public var id: Int64
    public var kind: ChatExportMediaKind
    /// The original file name, or empty when there is none.
    public var fileName: String
    public var mimeType: String
    /// The size Telegram reports, in bytes. Zero means unknown, and unknown sizes are not exported, as on Android.
    public var size: Int64
    /// Playback length in seconds, zero when unknown. Written to the JSON media object, as on Android.
    public var durationSeconds: Int
    /// Pixel size, zero when unknown. Written to the JSON media object, as on Android.
    public var width: Int
    public var height: Int

    public init(
        id: Int64,
        kind: ChatExportMediaKind,
        fileName: String = "",
        mimeType: String = "",
        size: Int64,
        durationSeconds: Int = 0,
        width: Int = 0,
        height: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
    }
}

/// Limits on media, the same as on Android: 10,000 files, 25 MiB for one file, and 100 MiB in total.
public struct ChatExportMediaLimits: Equatable {
    public static let standard = ChatExportMediaLimits(
        maxFiles: 10_000,
        maxSingleFileBytes: 25 * 1024 * 1024,
        maxTotalBytes: 100 * 1024 * 1024
    )

    public var maxFiles: Int
    public var maxSingleFileBytes: Int64
    public var maxTotalBytes: Int64

    public init(maxFiles: Int, maxSingleFileBytes: Int64, maxTotalBytes: Int64) {
        self.maxFiles = maxFiles
        self.maxSingleFileBytes = maxSingleFileBytes
        self.maxTotalBytes = maxTotalBytes
    }
}

/// Decides which files are copied, in the Android order. A file is refused when the copy count has reached its limit,
/// when its size is unknown or above the single-file limit, or when its size would take the total past the limit.
/// The size is reserved before the file is opened, so a file that then fails keeps its share, as on Android.
struct ChatExportMediaBudget {
    let limits: ChatExportMediaLimits
    private(set) var copiedFiles = 0
    private(set) var reservedBytes: Int64 = 0

    init(limits: ChatExportMediaLimits) {
        self.limits = limits
    }

    /// Reserves the size of `attachment`. Returns false when the file must be skipped.
    mutating func reserve(_ attachment: ChatExportAttachment) -> Bool {
        guard copiedFiles < limits.maxFiles else {
            return false
        }
        let size = attachment.size
        guard size > 0, size <= limits.maxSingleFileBytes, reservedBytes + size <= limits.maxTotalBytes else {
            return false
        }
        reservedBytes += size
        return true
    }

    mutating func recordCopied() {
        copiedFiles += 1
    }
}

/// Names inside the archive. Ports of the Android `safeExportFileName`, `mediaExtension` and `mediaEntryName`.
public enum ChatExportFileName {
    private static let unsafeCharacters = try? NSRegularExpression(pattern: "[\\\\/:*?\"<>|\\x00-\\x1F\\x7F]+")
    /// ASCII whitespace only, as Java's \s on Android. ICU's \s would also match Unicode spaces such as U+00A0.
    private static let whitespaceRun = try? NSRegularExpression(pattern: "[ \\t\\n\\x0B\\f\\r]+")
    private static let dotRun = try? NSRegularExpression(pattern: "\\.{2,}")

    /// `media/<messageId>_<name>.<extension>`. The message id keeps the files of different messages apart.
    public static func mediaEntryName(messageId: Int64, attachment: ChatExportAttachment) -> String {
        let base = safe(stem(of: attachment.fileName), fallback: attachment.kind.fallbackFileName, maxLength: 80)
        return "media/\(messageId)_\(base).\(fileExtension(for: attachment))"
    }

    /// The extension from the name when it is short and alphanumeric, else from the MIME type, else from the kind.
    public static func fileExtension(for attachment: ChatExportAttachment) -> String {
        if let dot = attachment.fileName.lastIndex(of: ".") {
            let fromName = attachment.fileName[attachment.fileName.index(after: dot)...].lowercased()
            if isSafeExtension(fromName) {
                return fromName
            }
        }
        let mimeBase = (attachment.mimeType.components(separatedBy: ";").first ?? "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        switch mimeBase {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "video/mp4": return "mp4"
        case "video/webm": return "webm"
        case "video/quicktime": return "mov"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/ogg", "audio/opus", "audio/x-opus+ogg": return "ogg"
        case "audio/mp4", "audio/m4a", "audio/x-m4a": return "m4a"
        case "audio/wav", "audio/x-wav": return "wav"
        case "application/pdf": return "pdf"
        case "application/zip": return "zip"
        case "application/x-tgsticker": return "tgs"
        default: return attachment.kind.defaultFileExtension
        }
    }

    /// Port of Android `safeExportFileName`. Unsafe characters become `_`, runs of spaces collapse, dots and spaces
    /// are trimmed from both ends, and the result is cut to `maxLength` UTF-16 units without splitting a surrogate pair.
    public static func safe(_ raw: String, fallback: String, maxLength: Int) -> String {
        var cleaned = replace(raw.trimmingCharacters(in: .whitespacesAndNewlines), with: unsafeCharacters, template: "_")
        cleaned = replace(cleaned, with: whitespaceRun, template: " ")
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if cleaned.isEmpty {
            cleaned = fallback
        }
        cleaned = replace(cleaned, with: dotRun, template: "_")
        if cleaned.isEmpty {
            cleaned = fallback
        }
        if cleaned.utf16.count > maxLength {
            cleaned = leadingUTF16(cleaned, count: maxLength).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        }
        return cleaned.isEmpty ? fallback : cleaned
    }

    private static func stem(of fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: ".") else {
            return fileName
        }
        return String(fileName[..<dot])
    }

    private static func isSafeExtension(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        return (1 ... 8).contains(scalars.count) && scalars.allSatisfy { scalar in
            (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
        }
    }

    private static func replace(_ text: String, with expression: NSRegularExpression?, template: String) -> String {
        guard let expression else {
            return text
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    /// The first `count` UTF-16 units, without ending in a lead surrogate.
    private static func leadingUTF16(_ text: String, count: Int) -> String {
        let units = Array(text.utf16)
        var end = min(count, units.count)
        if end > 0, UTF16.isLeadSurrogate(units[end - 1]) {
            end -= 1
        }
        return String(decoding: units[0 ..< end], as: UTF16.self)
    }
}

/// Opens the files of attachments. The app implements this on top of its media store and download path.
public protocol ChatExportFileProvider: AnyObject {
    /// Opens the file. Returns nil when it cannot be exported: not downloaded and not downloadable, or a request that timed
    /// out. Called before the ZIP entry is created, so a nil result or any other thrown error skips the file cleanly.
    /// Throw `CancellationError` only for cancellation, which stops the export.
    func openFile(for attachment: ChatExportAttachment) async throws -> ChatExportFileStream?
}

/// One opened file, read in order.
public protocol ChatExportFileStream: AnyObject {
    /// The next chunk of bytes, or nil at the end of the file. An error here aborts the export, as on Android, because
    /// the ZIP entry is already open by then.
    func readChunk() async throws -> Data?
    /// Releases the file. Called once, after the last read or after a failure.
    func close()
}

/// Keeps written bytes in memory while they fit in `limit`. Past the limit the bytes are dropped and `overflowed` is
/// set, so the caller renders the document again instead of holding all of it. Port of the Android `DocumentBuffer`.
public final class ChatExportBufferSink: ChatExportSink {
    private let limit: Int
    private var buffered: Data? = Data()

    /// True once the written bytes passed the limit. Nothing is kept after that.
    public private(set) var overflowed = false

    public init(limit: Int) {
        self.limit = limit
    }

    public func write(_ data: Data) throws {
        guard buffered != nil else {
            return
        }
        if (buffered?.count ?? 0) + data.count > limit {
            overflowed = true
            buffered = nil
            return
        }
        buffered?.append(data)
    }

    /// Writes the bytes kept so far. Writes nothing after an overflow.
    public func writeKept(to sink: ChatExportSink) throws {
        if let buffered {
            try sink.write(buffered)
        }
    }
}
