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

/// A file attached to a message. The JSON `media` object describes it, as the Android export does. The bytes come from
/// the app through `ChatExportFileProvider` when they are copied into an archive.
public struct ChatExportAttachment: Equatable {
    /// Identifies the file to the provider, for example the Telegram media id.
    public var id: Int64
    public var kind: ChatExportMediaKind
    /// The original file name, or empty when there is none.
    public var fileName: String
    public var mimeType: String
    /// The size Telegram reports, in bytes. Zero means unknown.
    public var size: Int64
    /// Playback length in seconds, zero when unknown.
    public var durationSeconds: Int
    /// Pixel size, zero when unknown.
    public var width: Int
    public var height: Int

    public init(
        id: Int64,
        kind: ChatExportMediaKind,
        fileName: String = "",
        mimeType: String = "",
        size: Int64 = 0,
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
