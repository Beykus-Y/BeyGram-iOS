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

/// Waits for the first value of a signal that completes after one value, such as a search page.
private func firstValue<T>(_ signal: Signal<T, NoError>) async -> T {
    final class Box {
        var disposable: Disposable?
    }
    let box = Box()
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

func chatExportMessage(_ message: EngineMessage) -> ChatExportMessage {
    var isEdited = false
    var replyTo: Int64?
    for attribute in message.attributes {
        if attribute is EditedMessageAttribute {
            isEdited = true
        } else if let reply = attribute as? ReplyMessageAttribute {
            replyTo = Int64(reply.messageId.id)
        }
    }
    var mediaKind: String?
    var isService = false
    for media in message.engineMedia {
        switch media {
        case .image:
            mediaKind = "photo"
        case .file:
            mediaKind = "file"
        case .action:
            isService = true
        default:
            break
        }
    }
    return ChatExportMessage(
        id: Int64(message.id.id),
        date: Date(timeIntervalSince1970: TimeInterval(message.timestamp)),
        senderName: senderName(message.author),
        text: message.text,
        isService: isService,
        isEdited: isEdited,
        replyToMessageId: replyTo,
        mediaKind: mediaKind,
        canBeSaved: !message.flags.contains(.CopyProtected)
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
    try ChatExportWriter.checkTarget(isSecretChat: peerId.isSecretChat, hasProtectedContent: hasProtectedContent)

    let writer = ChatExportWriter(
        format: format,
        header: ChatExportHeader(accountLabel: accountLabel, chatTitle: chatTitle, exportedAt: Date()),
        range: range,
        sink: sink
    )
    let job = ChatExportJob(writer: writer, cleanup: cleanup, onProgress: onProgress)

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
        return result.messages.map { chatExportMessage(EngineMessage($0)) }
    }
}
