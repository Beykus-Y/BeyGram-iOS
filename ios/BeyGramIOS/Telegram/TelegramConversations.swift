import Foundation
import TDLibKit

/// Mirrors Android's repository pattern: TDLib updates are the source of truth.
/// The UI never constructs native TDLib requests.
@MainActor
final class TelegramConversations: ObservableObject {
    @Published private(set) var mainChats: [TelegramChatPreview] = []
    @Published private(set) var contacts: [TelegramContact] = []
    @Published private(set) var contactsLoading = false
    @Published private(set) var archivedChats: [TelegramChatPreview] = []
    @Published private(set) var histories: [Int64: [TelegramChatMessage]] = [:]
    @Published private(set) var loadingHistory: Set<Int64> = []
    @Published private(set) var exhaustedHistory: Set<Int64> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var fileStates: [Int: TelegramMediaFile] = [:]
    @Published private(set) var pendingDownloads: Set<Int> = []
    @Published private(set) var mediaErrors: [Int: String] = [:]

    private weak var client: TDLibClient?
    private var rawChats: [Int64: [String: Any]] = [:]
    private var activeChats: Set<Int64> = []
    private var visibleMessages: [Int64: Set<Int64>] = [:]
    private var readFlushTasks: [Int64: Task<Void, Never>] = [:]
    private var loaded = false

    func bind(client: TDLibClient) {
        self.client = client
    }

    func start() {
        guard !loaded else { return }
        loaded = true
        request(TelegramRequestFactory.make(LoadChats(chatList: .chatListMain, limit: 100))) { [weak self] result in
            // 404 means that TDLib has no further chats; it isn't an auth failure.
            self?.refreshChatList()
        }
        request(TelegramRequestFactory.make(LoadChats(chatList: .chatListArchive, limit: 60))) { [weak self] _ in
            self?.refreshChatList()
        }
        refreshChatList()
        loadContacts()
    }

    func loadContacts() {
        guard !contactsLoading else { return }
        contactsLoading = true
        request(TelegramRequestFactory.make(GetContacts())) { [weak self] result in
            guard let self else { return }
            self.contactsLoading = false
            guard TelegramJSON.string(result["@type"]) == "users" else {
                self.errorMessage = TelegramJSON.string(result["message"])
                return
            }
            let ids = result["user_ids"] as? [Any] ?? []
            if ids.isEmpty { self.contacts = [] }
            for item in ids {
                let id = TelegramJSON.int64(item)
                if id != 0 { self.fetchContact(id) }
            }
        }
    }

    private func fetchContact(_ id: Int64) {
        request(TelegramRequestFactory.make(GetUser(userId: id))) { [weak self] result in
            guard TelegramJSON.string(result["@type"]) == "user",
                  let contact = TelegramContact.from(result) else { return }
            self?.upsertContact(contact)
        }
    }

    private func upsertContact(_ contact: TelegramContact) {
        var copy = contacts.filter { $0.id != contact.id }
        copy.append(contact)
        contacts = copy.sorted {
            $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }
    }

    func openPrivateChat(_ userID: Int64, completion: @escaping (Int64?) -> Void) {
        request(TelegramRequestFactory.make(CreatePrivateChat(force: false, userId: userID))) { [weak self] result in
            guard TelegramJSON.string(result["@type"]) == "chat" else {
                self?.errorMessage = TelegramJSON.string(result["message"])
                completion(nil)
                return
            }
            self?.mergeChat(result)
            let id = TelegramJSON.int64(result["id"])
            completion(id == 0 ? nil : id)
        }
    }

    func chat(for id: Int64) -> TelegramChatPreview? {
        guard let raw = rawChats[id] else { return nil }
        return TelegramChatPreview.from(raw)
    }

    func loadMoreChats() {
        request(TelegramRequestFactory.make(LoadChats(chatList: .chatListMain, limit: 80))) { [weak self] _ in
            self?.refreshChatList()
        }
    }

    func refreshChatList() {
        for list in [ChatList.chatListMain, ChatList.chatListArchive] {
            request(TelegramRequestFactory.make(GetChats(chatList: list, limit: 100))) { [weak self] result in
                let ids = result["chat_ids"] as? [Any] ?? []
                for value in ids {
                    let id = TelegramJSON.int64(value)
                    guard id != 0 else { continue }
                    self?.fetchChat(id)
                }
            }
        }
    }

    private func fetchChat(_ id: Int64) {
        request(TelegramRequestFactory.make(GetChat(chatId: id))) { [weak self] result in
            guard TelegramJSON.string(result["@type"]) == "chat" else { return }
            self?.mergeChat(result)
        }
    }

    private func mergeChat(_ chat: [String: Any]) {
        let id = TelegramJSON.int64(chat["id"])
        guard id != 0 else { return }
        rawChats[id] = chat
        publishChats()
    }

    private func modifyChat(_ id: Int64, mutate: (inout [String: Any]) -> Void) {
        guard var chat = rawChats[id] else {
            fetchChat(id)
            return
        }
        mutate(&chat)
        rawChats[id] = chat
        publishChats()
    }

    private func publishChats() {
        let values = rawChats.values.compactMap(TelegramChatPreview.from)
        mainChats = values.filter { $0.mainOrder > 0 }
            .sorted { ($0.mainOrder, $0.id) > ($1.mainOrder, $1.id) }
        archivedChats = values.filter { $0.archiveOrder > 0 }
            .sorted { ($0.archiveOrder, $0.id) > ($1.archiveOrder, $1.id) }
    }

    func handleUpdate(_ data: Data) {
        let update = TelegramJSON.decode(data)
        let type = TelegramJSON.string(update["@type"])
        let chatID = TelegramJSON.int64(update["chat_id"])

        switch type {
        case "updateFile":
            // A TDLib update is newer than the message's original file snapshot.
            if let file = TelegramMediaFile.from(TelegramJSON.object(update["file"])) {
                fileStates[file.id] = file
                if file.isOnDisk || !file.isDownloading {
                    pendingDownloads.remove(file.id)
                }
                if file.isOnDisk {
                    mediaErrors.removeValue(forKey: file.id)
                }
            }
        case "updateNewChat":
            let chat = TelegramJSON.object(update["chat"])
            if !chat.isEmpty { mergeChat(chat) }
        case "updateUser":
            if let contact = TelegramContact.from(TelegramJSON.object(update["user"])) {
                // Only keep actual contacts returned by getContacts. TDLib emits
                // updateUser for noncontacts as well; do not leak those into the list.
                if contacts.contains(where: { $0.id == contact.id }) { upsertContact(contact) }
            }
        case "updateUserStatus":
            let id = TelegramJSON.int64(update["user_id"])
            if let current = contacts.first(where: { $0.id == id }) {
                let online = TelegramJSON.string(
                    TelegramJSON.object(update["status"])["@type"]
                ) == "userStatusOnline"
                upsertContact(current.withOnline(online))
            }
        case "updateChatTitle":
            modifyChat(chatID) { $0["title"] = update["title"] }
        case "updateChatLastMessage":
            modifyChat(chatID) {
                $0["last_message"] = update["last_message"] ?? NSNull()
                if let positions = update["positions"] { $0["positions"] = positions }
            }
        case "updateChatPosition":
            modifyChat(chatID) { chat in
                let position = TelegramJSON.object(update["position"])
                guard !position.isEmpty else { return }
                let newList = TelegramJSON.string(TelegramJSON.object(position["list"])["@type"])
                var all = chat["positions"] as? [[String: Any]] ?? []
                all.removeAll { TelegramJSON.string(TelegramJSON.object($0["list"])["@type"]) == newList }
                if TelegramJSON.int64(position["order"]) > 0 { all.append(position) }
                chat["positions"] = all
            }
        case "updateChatReadInbox":
            modifyChat(chatID) { $0["unread_count"] = update["unread_count"] }
        case "updateChatNotificationSettings":
            modifyChat(chatID) { $0["notification_settings"] = update["notification_settings"] }
        case "updateNewMessage":
            let message = TelegramJSON.object(update["message"])
            if activeChats.contains(TelegramJSON.int64(message["chat_id"])) {
                upsertMessage(message)
            }
        case "updateMessageContent":
            let messageID = TelegramJSON.int64(update["message_id"])
            if var messages = histories[chatID], let index = messages.firstIndex(where: { $0.id == messageID }) {
                // TDLib updateMessageContent only contains the changed content.
                var raw: [String: Any] = [
                    "id": messageID, "chat_id": chatID,
                    "date": messages[index].timestamp,
                    "is_outgoing": messages[index].outgoing,
                    "content": update["new_content"] ?? [:]
                ]
                if !messages[index].status.isEmpty {
                    raw["sending_state"] = ["@type": messages[index].status]
                }
                if messages[index].media?.isSecret == true {
                    // updateMessageContent omits the surrounding message's self-destruct
                    // metadata. Never accidentally turn an ephemeral attachment public.
                    raw["self_destruct_type"] = ["@type": "messageSelfDestructTypeTimer"]
                }
                if let replacement = TelegramChatMessage.from(raw) {
                    registerMedia(replacement.media)
                    // TDLib's updateMessageContent omits interaction_info.
                    // Do not erase reactions when media/text is edited.
                    messages[index] = replacement.withReactions(messages[index].reactions)
                    histories[chatID] = messages
                }
            }
        case "updateMessageInteractionInfo":
            let messageID = TelegramJSON.int64(update["message_id"])
            if var messages = histories[chatID],
               let index = messages.firstIndex(where: { $0.id == messageID }) {
                let interaction = TelegramJSON.object(update["interaction_info"])
                messages[index] = messages[index].withReactions(
                    TelegramMessageReaction.fromInteraction(interaction)
                )
                histories[chatID] = messages
            }
        case "updateMessageSendSucceeded":
            let oldID = TelegramJSON.int64(update["old_message_id"])
            let message = TelegramJSON.object(update["message"])
            let id = TelegramJSON.int64(message["chat_id"])
            histories[id]?.removeAll(where: { $0.id == oldID })
            upsertMessage(message)
        case "updateMessageSendFailed":
            let oldID = TelegramJSON.int64(update["old_message_id"])
            let message = TelegramJSON.object(update["message"])
            let id = TelegramJSON.int64(message["chat_id"])
            histories[id]?.removeAll(where: { $0.id == oldID })
            upsertMessage(message)
        case "updateDeleteMessages":
            // Only delete those messages TDLib confirms were removed.
            let ids = Set((update["message_ids"] as? [Any] ?? []).map(TelegramJSON.int64))
            histories[chatID]?.removeAll(where: { ids.contains($0.id) })
        default: break
        }
    }

    func openChat(_ id: Int64) {
        activeChats.insert(id)
        request(TelegramRequestFactory.make(OpenChat(chatId: id))) { _ in }
        loadLatest(id)
    }

    func closeChat(_ id: Int64) {
        activeChats.remove(id)
        readFlushTasks.removeValue(forKey: id)?.cancel()
        visibleMessages.removeValue(forKey: id)
        request(TelegramRequestFactory.make(CloseChat(chatId: id))) { _ in }
    }

    /// Only messages actually visible in the LazyVStack are reported as viewed.
    /// Coalesce quick scroll events to avoid one TDLib call for every cell.
    func messageBecameVisible(chatID: Int64, messageID: Int64) {
        guard activeChats.contains(chatID), messageID > 0 else { return }
        visibleMessages[chatID, default: []].insert(messageID)
        scheduleViewReport(for: chatID)
    }

    func messageBecameHidden(chatID: Int64, messageID: Int64) {
        visibleMessages[chatID]?.remove(messageID)
    }

    private func scheduleViewReport(for chatID: Int64) {
        guard readFlushTasks[chatID] == nil else { return }
        readFlushTasks[chatID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self else { return }
            self.readFlushTasks.removeValue(forKey: chatID)
            guard !Task.isCancelled, self.activeChats.contains(chatID),
                  let visible = self.visibleMessages[chatID], !visible.isEmpty else { return }
            // TDLib handles duplicate view reports and server-side read receipts.
            self.request(TelegramRequestFactory.make(ViewMessages(
                chatId: chatID, forceRead: false, messageIds: Array(visible),
                source: .messageSourceChatHistory
            ))) { [weak self] result in
                if TelegramJSON.string(result["@type"]) == "error" {
                    self?.errorMessage = TelegramJSON.string(result["message"])
                }
            }
        }
    }

    func loadLatest(_ id: Int64) {
        guard !loadingHistory.contains(id) else { return }
        loadingHistory.insert(id)
        exhaustedHistory.remove(id)
        request(TelegramRequestFactory.make(GetChatHistory(
            chatId: id, fromMessageId: 0, limit: 60, offset: 0, onlyLocal: false
        ))) { [weak self] response in
            guard let self else { return }
            self.loadingHistory.remove(id)
            guard TelegramJSON.string(response["@type"]) == "messages" else {
                self.errorMessage = TelegramJSON.string(response["message"])
                return
            }
            let raw = response["messages"] as? [Any] ?? []
            let mapped = raw.compactMap { TelegramChatMessage.from(TelegramJSON.object($0)) }
            mapped.forEach { self.registerMedia($0.media) }
            self.mergeMessages(mapped, for: id)
            if raw.isEmpty { self.exhaustedHistory.insert(id) }
        }
    }

    func loadOlder(_ id: Int64) {
        guard !loadingHistory.contains(id), !exhaustedHistory.contains(id),
              let first = histories[id]?.first else { return }
        loadingHistory.insert(id)
        request(TelegramRequestFactory.make(GetChatHistory(
            chatId: id, fromMessageId: first.id, limit: 60, offset: 0, onlyLocal: false
        ))) { [weak self] response in
            guard let self else { return }
            self.loadingHistory.remove(id)
            guard TelegramJSON.string(response["@type"]) == "messages" else {
                self.errorMessage = TelegramJSON.string(response["message"])
                return
            }
            let raw = response["messages"] as? [Any] ?? []
            let models = raw.compactMap { TelegramChatMessage.from(TelegramJSON.object($0)) }
            models.forEach { self.registerMedia($0.media) }
            let priorFirst = self.histories[id]?.first?.id
            self.mergeMessages(models, for: id)
            if models.isEmpty || self.histories[id]?.first?.id == priorFirst {
                self.exhaustedHistory.insert(id)
            }
        }
    }

    func availableEmojiReactions(
        for message: TelegramChatMessage,
        completion: @escaping ([String]) -> Void
    ) {
        request(TelegramRequestFactory.make(GetMessageAvailableReactions(
            chatId: message.chatId, messageId: message.id, rowSize: 6
        ))) { [weak self] response in
            guard TelegramJSON.string(response["@type"]) == "availableReactions" else {
                if TelegramJSON.string(response["@type"]) == "error" {
                    self?.errorMessage = TelegramJSON.string(response["message"])
                }
                completion([])
                return
            }
            if response["unavailability_reason"] != nil &&
               !(response["unavailability_reason"] is NSNull) {
                completion([])
                return
            }
            let keys = ["top_reactions", "recent_reactions", "popular_reactions"]
            var seen = Set<String>()
            var emoji: [String] = []
            for key in keys {
                for item in response[key] as? [[String: Any]] ?? [] {
                    // Don't offer Premium-only or custom/paid reactions until
                    // the app implements eligibility and custom emoji rendering.
                    if TelegramJSON.flag(item["needs_premium"]) { continue }
                    let type = TelegramJSON.object(item["type"])
                    guard TelegramJSON.string(type["@type"]) == "reactionTypeEmoji" else {
                        continue
                    }
                    let name = TelegramJSON.string(type["emoji"])
                    if !name.isEmpty && seen.insert(name).inserted {
                        emoji.append(name)
                    }
                }
            }
            completion(Array(emoji.prefix(24)))
        }
    }

    func setEmojiReaction(
        _ emoji: String,
        for message: TelegramChatMessage,
        removing: Bool
    ) {
        guard !emoji.isEmpty else { return }
        let type = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: emoji))
        if removing {
            request(TelegramRequestFactory.make(RemoveMessageReaction(
                chatId: message.chatId, messageId: message.id, reactionType: type
            ))) { [weak self] result in
                if TelegramJSON.string(result["@type"]) == "error" {
                    self?.errorMessage = TelegramJSON.string(result["message"])
                }
            }
        } else {
            request(TelegramRequestFactory.make(AddMessageReaction(
                chatId: message.chatId, isBig: false, messageId: message.id,
                reactionType: type, updateRecentReactions: true
            ))) { [weak self] result in
                if TelegramJSON.string(result["@type"]) == "error" {
                    self?.errorMessage = TelegramJSON.string(result["message"])
                }
            }
        }
    }

    func messagePermissions(
        _ message: TelegramChatMessage,
        completion: @escaping (TelegramMessagePermissions?) -> Void
    ) {
        request(TelegramRequestFactory.make(GetMessageProperties(
            chatId: message.chatId, messageId: message.id
        ))) { [weak self] result in
            if let properties = TelegramMessagePermissions.from(result) {
                completion(properties)
            } else {
                self?.errorMessage = TelegramJSON.string(result["message"])
                completion(nil)
            }
        }
    }

    func editText(_ text: String, in message: TelegramChatMessage) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isText, !trimmed.isEmpty, trimmed.utf16.count <= 4096 else {
            errorMessage = "Редактировать можно только текст до 4096 символов."
            return false
        }
        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: false, linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: trimmed)
            )
        )
        request(TelegramRequestFactory.make(EditMessageText(
            chatId: message.chatId, inputMessageContent: content,
            messageId: message.id, replyMarkup: nil
        ))) { [weak self] response in
            if TelegramJSON.string(response["@type"]) == "error" {
                self?.errorMessage = TelegramJSON.string(response["message"])
            }
        }
        return true
    }

    func deleteMessage(_ message: TelegramChatMessage, forEveryone: Bool) {
        // Permissions must be obtained for THIS message immediately before
        // exposing the action; the server remains the final authority.
        request(TelegramRequestFactory.make(DeleteMessages(
            chatId: message.chatId, messageIds: [message.id], revoke: forEveryone
        ))) { [weak self] result in
            if TelegramJSON.string(result["@type"]) == "error" {
                self?.errorMessage = TelegramJSON.string(result["message"])
            }
        }
    }

    func sendText(_ text: String, to chatID: Int64, replyTo messageID: Int64? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= 4096 else {
            errorMessage = "Длина сообщения должна быть от 1 до 4096 символов."
            return false
        }
        guard client != nil else {
            errorMessage = "TDLib недоступна."
            return false
        }
        let body = InputMessageContent.inputMessageText(
            InputMessageText(clearDraft: true, linkPreviewOptions: nil, text: FormattedText(entities: [], text: trimmed))
        )
        let reply: InputMessageReplyTo? = messageID.map {
            .inputMessageReplyToMessage(InputMessageReplyToMessage(
                checklistTaskId: 0, messageId: $0, pollOptionId: "", quote: nil
            ))
        }
        request(TelegramRequestFactory.make(SendMessage(
            chatId: chatID, inputMessageContent: body, options: nil,
            replyMarkup: nil, replyTo: reply, topicId: nil
        ))) { [weak self] response in
            if TelegramJSON.string(response["@type"]) == "error" {
                self?.errorMessage = TelegramJSON.string(response["message"])
            } else if TelegramJSON.string(response["@type"]) == "message" {
                self?.upsertMessage(response)
            }
        }
        return true
    }

    /// Uses typed InputFileLocal objects, matching Android's OutgoingMediaContent.
    /// Acceptance by sendMessage means TDLib queued the upload, not that the
    /// Telegram server has delivered it. Retain the staged file on disk.
    func sendAttachment(
        _ attachment: BeyGramOutgoingAttachment,
        to chatID: Int64,
        caption: String,
        replyTo messageID: Int64? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 1024 else {
            errorMessage = "Подпись должна содержать не более 1024 символов."
            completion(false)
            return
        }
        guard let client, FileManager.default.fileExists(atPath: attachment.localURL.path) else {
            errorMessage = "Подготовленный файл недоступен."
            completion(false)
            return
        }

        let content = makeOutgoingContent(attachment, caption: trimmed)
        let reply: InputMessageReplyTo? = messageID.map {
            .inputMessageReplyToMessage(InputMessageReplyToMessage(
                checklistTaskId: 0, messageId: $0,
                pollOptionId: "", quote: nil
            ))
        }
        do {
            try client.send(query: TelegramRequestFactory.make(SendMessage(
                chatId: chatID,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: reply,
                topicId: nil
            ))) { [weak self] data in
                let response = TelegramJSON.decode(data)
                Task { @MainActor in
                    switch TelegramJSON.string(response["@type"]) {
                    case "message":
                        self?.upsertMessage(response)
                        completion(true)
                    case "error":
                        self?.errorMessage = TelegramJSON.string(response["message"])
                        completion(false)
                    default:
                        self?.errorMessage = "Неожиданный ответ TDLib при отправке вложения."
                        completion(false)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            completion(false)
        }
    }

    /// Builds exactly the same TDLib input content for single sends and albums.
    private func makeOutgoingContent(
        _ attachment: BeyGramOutgoingAttachment, caption: String
    ) -> InputMessageContent {
        let input = InputFile.inputFileLocal(
            InputFileLocal(path: attachment.localURL.path)
        )
        let formatted: FormattedText? = caption.isEmpty
            ? nil : FormattedText(entities: [], text: caption)

        switch attachment.kind {
        case .photo:
            return .inputMessagePhoto(InputMessagePhoto(
                caption: formatted,
                hasSpoiler: false,
                photo: InputPhoto(
                    addedStickerFileIds: [],
                    height: attachment.height,
                    photo: input,
                    thumbnail: nil,
                    video: nil,
                    width: attachment.width
                ),
                selfDestructType: nil,
                showCaptionAboveMedia: false
            ))
        case .video:
            return .inputMessageVideo(InputMessageVideo(
                caption: formatted,
                hasSpoiler: false,
                selfDestructType: nil,
                showCaptionAboveMedia: false,
                video: InputVideo(
                    addedStickerFileIds: [],
                    cover: nil,
                    duration: attachment.durationSeconds,
                    height: attachment.height,
                    startTimestamp: 0,
                    supportsStreaming: true,
                    thumbnail: nil,
                    video: input,
                    width: attachment.width
                )
            ))
        case .document:
            return .inputMessageDocument(InputMessageDocument(
                caption: formatted,
                document: InputDocument(
                    disableContentTypeDetection: true,
                    document: input,
                    thumbnail: nil
                )
            ))
        }
    }

    /// TDLib supports 2–10 photos/videos as one album. Unlike sequential
    /// sendMessage calls, Telegram displays these as a grouped attachment.
    func sendMediaAlbum(
        _ attachments: [BeyGramOutgoingAttachment],
        to chatID: Int64,
        caption: String,
        replyTo replyID: Int64? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        guard (2...10).contains(attachments.count),
              attachments.allSatisfy({ $0.kind == .photo || $0.kind == .video }),
              caption.count <= 1024 else {
            errorMessage = "В одном альбоме допускается от 2 до 10 фото или видео."
            completion(false)
            return
        }

        guard attachments.allSatisfy({
            FileManager.default.fileExists(atPath: $0.localURL.path)
        }) else {
            errorMessage = "Одно из вложений больше недоступно."
            completion(false)
            return
        }

        let contents = attachments.enumerated().map { index, attachment in
            makeOutgoingContent(
                attachment, caption: index == 0 ? caption : ""
            )
        }
        let reply: InputMessageReplyTo? = replyID.map {
            .inputMessageReplyToMessage(InputMessageReplyToMessage(
                checklistTaskId: 0, messageId: $0, pollOptionId: "", quote: nil
            ))
        }
        request(TelegramRequestFactory.make(SendMessageAlbum(
            chatId: chatID,
            inputMessageContents: contents,
            options: nil,
            replyTo: reply,
            topicId: nil
        ))) { [weak self] response in
            guard TelegramJSON.string(response["@type"]) == "messages" else {
                self?.errorMessage = TelegramJSON.string(response["message"])
                completion(false)
                return
            }
            let messages = response["messages"] as? [[String: Any]] ?? []
            guard messages.count == attachments.count else {
                self?.errorMessage = "TDLib вернула неполный ответ на отправку альбома."
                completion(false)
                return
            }
            for message in messages {
                self?.upsertMessage(message)
            }
            completion(true)
        }
    }

    func clearError() { errorMessage = nil }

    func mediaFileState(_ file: TelegramMediaFile) -> TelegramMediaFile {
        fileStates[file.id] ?? file
    }

    func mediaError(for id: Int) -> String? { mediaErrors[id] }

    /// Thumbnail download is opt-in from a *visible* media bubble.
    /// Full-size downloads always require a user's button press.
    func downloadMedia(_ media: TelegramMessageMedia, preview: Bool = false) {
        guard !media.isSecret else { return }
        guard let selected = preview ? media.preview : media.file else { return }
        let state = mediaFileState(selected)
        guard !state.isOnDisk, state.canDownload,
              !pendingDownloads.contains(state.id) else { return }

        pendingDownloads.insert(state.id)
        mediaErrors.removeValue(forKey: state.id)
        request(TelegramRequestFactory.make(DownloadFile(
            fileId: state.id,
            limit: 0,
            offset: 0,
            priority: preview ? 4 : 16,
            synchronous: false
        ))) { [weak self] result in
            guard let self else { return }
            if TelegramJSON.string(result["@type"]) == "error" {
                self.pendingDownloads.remove(state.id)
                self.mediaErrors[state.id] = TelegramJSON.string(result["message"])
            } else if let file = TelegramMediaFile.from(result) {
                self.fileStates[file.id] = file
                if file.isOnDisk { self.pendingDownloads.remove(file.id) }
            }
        }
    }

    private func registerMedia(_ media: TelegramMessageMedia?) {
        guard let media, !media.isSecret else { return }
        for file in [media.file, media.preview].compactMap({ $0 }) {
            // Do not roll an updateFile state back with an older history snapshot.
            if let old = fileStates[file.id], !file.isOnDisk && old.isOnDisk {
                continue
            }
            if fileStates[file.id] == nil || file.isOnDisk {
                fileStates[file.id] = file
            }
        }
    }

    private func upsertMessage(_ raw: [String: Any]) {
        guard let model = TelegramChatMessage.from(raw) else { return }
        guard activeChats.contains(model.chatId) else { return }
        registerMedia(model.media)
        var messages = histories[model.chatId] ?? []
        messages.removeAll(where: { $0.id == model.id })
        messages.append(model)
        messages.sort { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
        histories[model.chatId] = messages
    }

    private func mergeMessages(_ added: [TelegramChatMessage], for id: Int64) {
        var byID: [Int64: TelegramChatMessage] = [:]
        for item in histories[id] ?? [] { byID[item.id] = item }
        for item in added { byID[item.id] = item }
        histories[id] = byID.values.sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
    }

    private func request(
        _ query: TdQuery,
        completion: @escaping ([String: Any]) -> Void
    ) {
        guard let client else {
            let reason = "TDLib ещё не инициализирована."
            errorMessage = reason
            completion(["@type": "error", "message": reason])
            return
        }
        do {
            try client.send(query: query) { data in
                let result = TelegramJSON.decode(data)
                Task { @MainActor in completion(result) }
            }
        } catch {
            errorMessage = error.localizedDescription
            completion(["@type": "error", "message": error.localizedDescription])
        }
    }
}
