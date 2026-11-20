import Foundation
import UserNotifications
import SwiftSignalKit
import TelegramCore
import AccountContext
import BeyGramKit
import BeyGramTriggerWords

private let triggerAlertThread = "bg-trigger-words"
private let maxTriggerAlertsInTray = 10

private func firstValue<T>(_ signal: Signal<T, NoError>) async -> T {
    final class Box {
        var disposable: Disposable?
    }
    let box = Box()
    return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
        box.disposable = signal.start(next: { value in
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

/// Whether previews are shown for this message: the chat's own setting wins; the default follows the global
/// setting for the chat's category. Returns the category's `enabled` too, since a disabled category posts no alerts.
private func previewSettings(context: AccountContext, message: EngineMessage, global: EngineGlobalNotificationSettings) async -> (previews: Bool, enabled: Bool, muted: Bool) {
    let category: EngineGlobalNotificationSettings.CategorySettings
    switch message.enginePeers[message.id.peerId] {
    case let .channel(channel)?:
        if case .broadcast = channel.info {
            category = global.channels
        } else {
            category = global.groupChats
        }
    case .legacyGroup?:
        category = global.groupChats
    default:
        category = global.privateChats
    }
    let peerSettings = await firstValue(context.engine.data.get(TelegramEngine.EngineData.Item.Peer.NotificationSettings(id: message.id.peerId)))
    let muted: Bool
    switch peerSettings.muteState {
    case let .muted(until):
        muted = until >= Int32(Date().timeIntervalSince1970)
    case .default, .unmuted:
        muted = false
    }
    switch peerSettings.displayPreviews {
    case .show:
        return (true, category.enabled, muted)
    case .hide:
        return (false, category.enabled, muted)
    case .default:
        return (category.displayPreviews, category.enabled, muted)
    }
}

/// Posts one local alert per match. The identifier includes account, chat and message, so a repeat replaces the
/// earlier alert. Only the newest 10 trigger alerts stay in the tray.
private func postTriggerAlert(identifier: String, title: String, body: String, date: Date) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.threadIdentifier = triggerAlertThread
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    let center = UNUserNotificationCenter.current()
    center.add(request, withCompletionHandler: nil)
    center.getDeliveredNotifications { delivered in
        let triggerAlerts = delivered
            .filter { $0.request.content.threadIdentifier == triggerAlertThread }
            .sorted { $0.date > $1.date }
        guard triggerAlerts.count > maxTriggerAlertsInTray else {
            return
        }
        let stale = triggerAlerts.dropFirst(maxTriggerAlertsInTray).map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: Array(stale))
    }
}

/// Feeds new incoming messages of one account to the trigger-word ingestor and posts alerts when the policy asks for one.
///
/// Returns at once. Nothing happens while the flag is off or there are no rules. Outgoing and secret-chat messages are skipped.
/// Preview and category settings come from the engine, so a hidden preview keeps no text in the feed and in the alert.
public func ingestTriggerWordsFromAccount(
    context: AccountContext,
    batches: [[EngineMessage]],
    isChatOpen: @escaping (EnginePeer.Id) -> Bool
) {
    guard BeyGramSettings.shared.isEnabled(.triggerWords), !TriggerWordsStore.shared.state.rules.isEmpty else {
        return
    }
    Task { @MainActor in
        let global = await firstValue(context.engine.data.get(TelegramEngine.EngineData.Item.NotificationSettings.Global()))
        let store = TriggerWordsStore.shared
        let accountId = context.account.id.int64
        for messages in batches {
            for message in messages {
                guard message.flags.contains(.Incoming), !message.id.peerId.isSecretChatNamespace else {
                    continue
                }
                let settings = await previewSettings(context: context, message: message, global: global)
                let incoming = TriggerWordIncomingMessage(
                    accountId: accountId,
                    chatId: message.id.peerId.toInt64(),
                    messageId: Int64(message.id.id),
                    messageDate: Date(timeIntervalSince1970: TimeInterval(message.timestamp)),
                    text: message.text,
                    senderName: senderName(message.author),
                    isChatMuted: settings.muted,
                    isChatOpenOnScreen: isChatOpen(message.id.peerId),
                    isProtectedContent: message.flags.contains(.CopyProtected)
                )
                let account = TriggerWordAccountSettings(
                    notificationsEnabled: settings.enabled,
                    backgroundEnabled: true,
                    previewsEnabled: settings.previews,
                    chatPreviewsEnabled: true
                )
                guard let decision = TriggerWordsIngestor.ingest(incoming, store: store, account: account, now: Date()), decision.postAlert else {
                    continue
                }
                let identifier = "bg-trigger-\(accountId)-\(incoming.chatId)-\(incoming.messageId)"
                let word = decision.matchedPatterns.first ?? ""
                if decision.alertShowsText {
                    postTriggerAlert(identifier: identifier, title: "\(incoming.senderName): \(word)", body: incoming.text, date: incoming.messageDate)
                } else {
                    postTriggerAlert(identifier: identifier, title: "Trigger word", body: word, date: incoming.messageDate)
                }
            }
        }
    }
}
