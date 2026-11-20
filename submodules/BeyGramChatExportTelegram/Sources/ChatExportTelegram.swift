import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import BeyGramChatExport

/// Writes into a file handle that the app opened from a user-chosen, security-scoped URL.
/// The app must not give this sink a path in shared Downloads, the app cache or a private temporary file.
public final class ChatExportFileHandleSink: ChatExportSink {
    private let handle: FileHandle

    public init(handle: FileHandle) {
        self.handle = handle
    }

    public func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }
}

/// Holds the disposable of a `firstValue` subscription until the value arrives.
private final class FirstValueDisposableBox {
    var disposable: Disposable?
}

/// Waits for the first value of a signal that completes after one value, such as a search page.
private func firstValue<T>(_ signal: Signal<T, NoError>) async -> T {
    let box = FirstValueDisposableBox()
    return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
        box.disposable = signal.start(next: { value in
            // Keeps the box, and so the disposable, alive until the value arrives.
            withExtendedLifetime(box) {
                continuation.resume(returning: value)
            }
        }, completed: {})
    }
}

private func senderName(_ peer: EnginePeer?) -> String {
    switch peer {
    case let .user(user)?:
        return [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
    case let .channel(channel)?:
        return channel.title
    case let .legacyGroup(group)?:
        return group.title
    default:
        return ""
    }
}

/// TDLib's id for a peer, as the Android export writes it: a user keeps its id, a basic group is negative, and a channel
/// or supergroup is -1000000000000 minus its id. Without the peer, the stored id is written as it is.
private func tdlibId(_ id: EnginePeer.Id, peer: EnginePeer?) -> Int64 {
    let raw = id.id._internalGetInt64Value()
    switch peer {
    case .legacyGroup?:
        return -raw
    case .channel?:
        return -1_000_000_000_000 - raw
    default:
        return raw
    }
}

/// The kind of a chat, named as the Android export names it (`exportKind`).
private func chatKind(_ peer: EnginePeer?) -> String {
    switch peer {
    case .user?:
        return "private"
    case .legacyGroup?:
        return "group"
    case let .channel(channel)?:
        if case .broadcast = channel.info {
            return "channel"
        }
        return "group"
    default:
        return "unknown"
    }
}

/// The Android media kind of a file, checked in the order the Android export uses.
private func fileKind(_ file: TelegramMediaFile) -> ChatExportMediaKind {
    if file.isSticker {
        return .sticker
    }
    if file.isInstantVideo {
        return .videoNote
    }
    if file.isVoice {
        return .voice
    }
    if file.isMusic {
        return .audio
    }
    if file.isAnimated {
        return .animation
    }
    if file.isVideo {
        return .video
    }
    return .document
}

/// The file of a message, for the JSON `media` object. Photos and files are described; other media is not.
/// The sizes are the ones Telegram reports. A photo is described by its largest representation.
private func chatExportAttachment(_ media: EngineMedia) -> ChatExportAttachment? {
    switch media {
    case let .image(image):
        // Telegram photos are always JPEG.
        let largest = image.representations.max { lhs, rhs in
            Int64(lhs.dimensions.width) * Int64(lhs.dimensions.height) < Int64(rhs.dimensions.width) * Int64(rhs.dimensions.height)
        }
        return ChatExportAttachment(
            id: image.imageId.id,
            kind: .photo,
            mimeType: "image/jpeg",
            size: (largest?.resource as? CloudPhotoSizeMediaResource)?.size ?? 0,
            width: Int(largest?.dimensions.width ?? 0),
            height: Int(largest?.dimensions.height ?? 0)
        )
    case let .file(file):
        let dimensions = file.dimensions
        return ChatExportAttachment(
            id: file.fileId.id,
            kind: fileKind(file),
            fileName: file.fileName ?? "",
            mimeType: file.mimeType,
            size: file.size ?? 0,
            durationSeconds: Int(file.duration ?? 0),
            width: Int(dimensions?.width ?? 0),
            height: Int(dimensions?.height ?? 0)
        )
    default:
        return nil
    }
}

func chatExportMessage(_ message: EngineMessage, accountPeerId: EnginePeer.Id) -> ChatExportMessage {
    var isEdited = false
    var replyTo: Int64?
    for attribute in message.attributes {
        if attribute is EditedMessageAttribute {
            isEdited = true
        } else if let reply = attribute as? ReplyMessageAttribute {
            replyTo = Int64(reply.messageId.id)
        }
    }
    var attachment: ChatExportAttachment?
    var isService = false
    for media in message.engineMedia {
        if case .action = media {
            isService = true
        } else if attachment == nil, let found = chatExportAttachment(media) {
            attachment = found
        }
    }
    return ChatExportMessage(
        id: Int64(message.id.id),
        date: Date(timeIntervalSince1970: TimeInterval(message.timestamp)),
        isOutgoing: !message.effectivelyIncoming(accountPeerId),
        senderId: message.author.map { tdlibId($0.id, peer: $0) } ?? 0,
        senderName: senderName(message.author),
        text: message.text,
        isEdited: isEdited,
        serviceText: isService ? message.text : nil,
        replyToMessageId: replyTo,
        canBeSaved: !message.flags.contains(.CopyProtected),
        attachment: attachment
    )
}

/// Exports one chat of one account. The history is paged newest first, 100 per request, through
/// message search with an empty query, which returns every message in the peer.
/// Cancelling the calling task stops the export and runs `cleanup`.
public func runChatExport(
    context: AccountContext,
    peerId: EnginePeer.Id,
    chatTitle: String,
    accountLabel: String,
    hasProtectedContent: Bool,
    format: ChatExportFormat,
    range: ChatExportRange,
    sink: ChatExportSink,
    cleanup: @escaping () -> Void,
    onProgress: @escaping (ChatExportProgress) -> Void
) async throws -> ChatExportSummary {
    try ChatExportWriter.checkTarget(isSecretChat: peerId.isSecretChatNamespace, hasProtectedContent: hasProtectedContent)

    let peer = await firstValue(context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)))
    // An untitled chat is named "Chat", as on Android.
    let title = chatTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Chat" : chatTitle
    let header = ChatExportHeader(
        accountLabel: accountLabel,
        chat: ChatExportChat(id: tdlibId(peerId, peer: peer), title: title, kind: chatKind(peer)),
        exportedAt: Date(),
        mediaRequested: false
    )
    let writer = ChatExportWriter(
        format: format,
        header: header,
        range: range,
        sink: sink
    )
    let job = ChatExportJob(writer: writer, cleanup: cleanup, onProgress: onProgress)
    let accountPeerId = context.account.peerId

    var state: SearchMessagesState?
    var isFinished = false
    return try await job.run {
        if isFinished {
            return []
        }
        let (result, nextState) = await firstValue(context.engine.messages.searchMessages(
            location: .peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil),
            query: "",
            state: state
        ))
        state = nextState
        if result.completed || result.messages.isEmpty {
            isFinished = true
        }
        return result.messages.map { chatExportMessage(EngineMessage($0), accountPeerId: accountPeerId) }
    }
}
