import Foundation

/// Media categories mirror Android BeyGram's TdMediaMapper / MediaKind.
enum TelegramMediaKind: String, Equatable {
    case photo, video, animation, document, audio, voice, videoNote, sticker

    var label: String {
        switch self {
        case .photo: return "Фото"
        case .video: return "Видео"
        case .animation: return "GIF"
        case .document: return "Документ"
        case .audio: return "Аудио"
        case .voice: return "Голосовое"
        case .videoNote: return "Видеосообщение"
        case .sticker: return "Стикер"
        }
    }

    var symbol: String {
        switch self {
        case .photo: return "photo.fill"
        case .video, .videoNote: return "play.rectangle.fill"
        case .animation: return "sparkles.tv"
        case .document: return "doc.fill"
        case .audio, .voice: return "waveform"
        case .sticker: return "face.smiling"
        }
    }

    var isVisual: Bool {
        switch self {
        case .photo, .video, .animation, .videoNote, .sticker: return true
        default: return false
        }
    }
}

/// Only a *completed* TDLib local file may be passed to iOS viewers.
/// The remote TDLib file id is not a URL and is never fetched by URLSession.
struct TelegramMediaFile: Equatable {
    let id: Int
    let size: Int64
    let downloadedBytes: Int64
    let isDownloading: Bool
    let canDownload: Bool
    let completedPath: String?

    static func from(_ raw: [String: Any]) -> Self? {
        let id = TelegramJSON.integer(raw["id"])
        guard id > 0 else { return nil }
        let local = TelegramJSON.object(raw["local"])
        let complete = TelegramJSON.flag(local["is_downloading_completed"])
        let path = TelegramJSON.string(local["path"])
        return Self(
            id: id,
            size: max(0, TelegramJSON.int64(raw["size"]), TelegramJSON.int64(raw["expected_size"])),
            downloadedBytes: max(0, TelegramJSON.int64(local["downloaded_size"])),
            isDownloading: TelegramJSON.flag(local["is_downloading_active"]),
            canDownload: TelegramJSON.flag(local["can_be_downloaded"]),
            completedPath: complete && !path.isEmpty ? path : nil
        )
    }

    var fraction: Double {
        guard size > 0 else { return 0 }
        return min(1, max(0, Double(downloadedBytes) / Double(size)))
    }

    var humanSize: String {
        guard size > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var isOnDisk: Bool {
        guard let completedPath else { return false }
        return FileManager.default.fileExists(atPath: completedPath)
    }
}

struct TelegramMessageMedia: Equatable {
    let kind: TelegramMediaKind
    let file: TelegramMediaFile
    let preview: TelegramMediaFile?
    let fileName: String
    let mimeType: String
    let caption: String
    let width: Int
    let height: Int
    let durationSeconds: Int
    let hasSpoiler: Bool
    let isSecret: Bool

    var shapeRatio: CGFloat {
        guard width > 0 && height > 0 else { return 4.0 / 3.0 }
        return min(1.8, max(0.7, CGFloat(width) / CGFloat(height)))
    }

    /// TDLib JSON properties use snake_case, matching Android TdMediaMapper.
    static func from(_ message: [String: Any]) -> Self? {
        let content = TelegramJSON.object(message["content"])
        let type = TelegramJSON.string(content["@type"])
        let kind: TelegramMediaKind
        let contentObject: [String: Any]
        let fileObject: [String: Any]
        var previewObject: [String: Any] = [:]
        var width = 0
        var height = 0

        switch type {
        case "messagePhoto":
            kind = .photo
            let photo = TelegramJSON.object(content["photo"])
            let sizes = (photo["sizes"] as? [[String: Any]] ?? []).sorted {
                TelegramJSON.integer($0["width"]) * TelegramJSON.integer($0["height"]) <
                TelegramJSON.integer($1["width"]) * TelegramJSON.integer($1["height"])
            }
            guard let largest = sizes.last else { return nil }
            fileObject = TelegramJSON.object(largest["photo"])
            if let preferred = sizes.first(where: {
                max(TelegramJSON.integer($0["width"]), TelegramJSON.integer($0["height"])) >= 240
            }) ?? sizes.first {
                previewObject = TelegramJSON.object(preferred["photo"])
            }
            width = TelegramJSON.integer(largest["width"])
            height = TelegramJSON.integer(largest["height"])
            contentObject = photo

        case "messageVideo":
            kind = .video
            contentObject = TelegramJSON.object(content["video"])
            fileObject = TelegramJSON.object(contentObject["video"])
            previewObject = TelegramJSON.object(TelegramJSON.object(contentObject["thumbnail"])["file"])
            width = TelegramJSON.integer(contentObject["width"])
            height = TelegramJSON.integer(contentObject["height"])

        case "messageAnimation":
            kind = .animation
            contentObject = TelegramJSON.object(content["animation"])
            fileObject = TelegramJSON.object(contentObject["animation"])
            previewObject = TelegramJSON.object(TelegramJSON.object(contentObject["thumbnail"])["file"])
            width = TelegramJSON.integer(contentObject["width"])
            height = TelegramJSON.integer(contentObject["height"])

        case "messageDocument":
            kind = .document
            contentObject = TelegramJSON.object(content["document"])
            fileObject = TelegramJSON.object(contentObject["document"])
            previewObject = TelegramJSON.object(TelegramJSON.object(contentObject["thumbnail"])["file"])

        case "messageAudio":
            kind = .audio
            contentObject = TelegramJSON.object(content["audio"])
            fileObject = TelegramJSON.object(contentObject["audio"])
            previewObject = TelegramJSON.object(TelegramJSON.object(contentObject["album_cover_thumbnail"])["file"])

        case "messageVoiceNote":
            kind = .voice
            contentObject = TelegramJSON.object(content["voice_note"])
            fileObject = TelegramJSON.object(contentObject["voice"])

        case "messageVideoNote":
            kind = .videoNote
            contentObject = TelegramJSON.object(content["video_note"])
            fileObject = TelegramJSON.object(contentObject["video"])
            previewObject = TelegramJSON.object(TelegramJSON.object(contentObject["thumbnail"])["file"])
            width = TelegramJSON.integer(contentObject["length"])
            height = width

        case "messageSticker":
            kind = .sticker
            contentObject = TelegramJSON.object(content["sticker"])
            fileObject = TelegramJSON.object(contentObject["sticker"])
            previewObject = TelegramJSON.object(TelegramJSON.object(contentObject["thumbnail"])["file"])
            width = TelegramJSON.integer(contentObject["width"])
            height = TelegramJSON.integer(contentObject["height"])
        default:
            return nil
        }

        guard let file = TelegramMediaFile.from(fileObject) else { return nil }
        let caption = TelegramJSON.string(TelegramJSON.object(content["caption"])["text"])
        let preview = TelegramMediaFile.from(previewObject)
        // can_be_saved=false indicates protected channel/group content.
        // Do not accidentally expose it through QuickLook, system sharing
        // or a regular screen-capturable media viewer.
        let protectedByChat = (message["can_be_saved"] as? Bool) == false
        let isSecret = protectedByChat ||
            TelegramJSON.flag(content["is_secret"]) ||
            (message["self_destruct_type"] != nil && !(message["self_destruct_type"] is NSNull))

        return Self(
            kind: kind,
            file: file,
            preview: preview?.id == file.id ? nil : preview,
            fileName: TelegramJSON.string(contentObject["file_name"]),
            mimeType: TelegramJSON.string(contentObject["mime_type"]),
            caption: caption,
            width: width,
            height: height,
            durationSeconds: TelegramJSON.integer(contentObject["duration"]),
            hasSpoiler: TelegramJSON.flag(content["has_spoiler"]),
            isSecret: isSecret
        )
    }
}
