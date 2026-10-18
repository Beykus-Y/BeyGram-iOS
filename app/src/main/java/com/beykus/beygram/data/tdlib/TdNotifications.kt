package com.beykus.beygram.data.tdlib

import com.beykus.beygram.R
import com.beykus.beygram.diagnostics.recordAppEvent
import com.beykus.beygram.diagnostics.report.EventKind
import com.beykus.beygram.domain.UiText
import com.beykus.beygram.domain.model.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.drinkless.tdlib.Client
import org.drinkless.tdlib.TdApi

/** Consume TDLib's authoritative notification groups, never infer alerts from history. */
internal class TdNotifications(
    client: () -> Client,
    private val senderName: (TdApi.MessageSender?) -> String,
    private val debugLog: (String) -> Unit = { android.util.Log.i("BeyGramNotify", it) },
    private val isArchived: (Long) -> Boolean
) {
    private val request = TdRequests(client)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()
    private val groups = mutableMapOf<Int, TelegramNoticeGroup>()
    private val chats = mutableMapOf<Long, TdApi.Chat>()
    private val resolving = mutableSetOf<Long>()
    private val _state = MutableStateFlow(TelegramNotifications())
    val state = _state.asStateFlow()

    fun initialize() { scope.launch {
        conversationResult {
            request(TdApi.SetOption("notification_group_size_max", TdApi.OptionValueInteger(10)))
            request(TdApi.SetOption("notification_group_count_max", TdApi.OptionValueInteger(25)))
            // Configuring group limits does not confirm TDLib delivered an initial snapshot.
            // Keep the existing Android tray until the real UpdateActiveNotifications arrives.
        }
    } }
    suspend fun dismiss(groupId: Int, maxId: Int): Result<Unit> = conversationResult {
        request(TdApi.RemoveNotificationGroup(groupId, maxId)); Unit
    }
    fun chat(chat: TdApi.Chat) = synchronized(lock) {
        chats[chat.id] = chat
        groups.replaceAll { _, group -> if (group.chatId == chat.id) metadata(group) else group }
        publish()
    }

    /** Re-reads the archived flag of the chat's groups after its list position changed. */
    fun chatPositionChanged(chatId: Long) = synchronized(lock) {
        if (groups.values.none { it.chatId == chatId }) return@synchronized
        groups.replaceAll { _, group -> if (group.chatId == chatId) metadata(group) else group }
        publish()
    }
    fun handle(update: TdApi.Object) = synchronized(lock) {
        when (update) {
            is TdApi.UpdateActiveNotifications -> {
                val previous = groups.toMap()
                groups.clear()
                update.groups.orEmpty().filterNot { it.type is TdApi.NotificationGroupTypeCalls }.forEach { group ->
                    val notices = group.notifications.orEmpty().mapNotNull(::notice)
                    // A pending alert survives the snapshot while its notice is still active; the renderer's watermark stops repeats.
                    val alert = previous[group.id]?.takeIf { it.chatId == group.chatId }?.alertId?.takeIf { id -> notices.any { it.id == id } } ?: 0
                    groups[group.id] = metadata(TelegramNoticeGroup(group.id, group.chatId, totalCount = group.totalCount,
                        notices = notices, alertId = alert, isSecret = group.type is TdApi.NotificationGroupTypeSecretChat))
                }
                _state.value = _state.value.copy(initialized = true, snapshot = true)
                recordAppEvent(EventKind.NOTIFICATION, "snapshot", "Снимок уведомлений: групп ${groups.size}", attrs = mapOf("groups" to groups.size.toString()))
            }
            is TdApi.UpdateNotificationGroup -> {
                // Incremental groups can render immediately but cannot prove other groups are absent.
                _state.value = _state.value.copy(initialized = true)
                if (update.type is TdApi.NotificationGroupTypeCalls) { groups.remove(update.notificationGroupId); publish(); return@synchronized }
                val old = groups[update.notificationGroupId]?.takeIf { it.chatId == update.chatId }
                val removed = (update.removedNotificationIds ?: intArrayOf()).toSet()
                val added = update.addedNotifications.orEmpty()
                val merged = (old?.notices.orEmpty().filterNot { it.id in removed } + added.mapNotNull(::notice)).associateBy { it.id }.values.sortedBy { it.id }.takeLast(10)
                val newAlert = if (update.notificationSoundId != 0L) added.filter { !it.isSilent && it.id > (old?.notices?.maxOfOrNull { n -> n.id } ?: 0) }.maxOfOrNull { it.id } ?: 0 else 0
                // An alert the renderer has not posted yet stays until its notice is gone, even when other updates arrive first.
                val pendingAlert = old?.alertId?.takeIf { id -> merged.any { it.id == id } } ?: 0
                val alert = maxOf(pendingAlert, newAlert)
                if (update.totalCount == 0 || merged.isEmpty()) groups.remove(update.notificationGroupId)
                else groups[update.notificationGroupId] = metadata(TelegramNoticeGroup(update.notificationGroupId, update.chatId, totalCount = update.totalCount,
                    notices = merged, alertId = alert, isSecret = update.type is TdApi.NotificationGroupTypeSecretChat))
            }
            is TdApi.UpdateNotification -> groups[update.notificationGroupId]?.let { group ->
                val changed = notice(update.notification)
                groups[group.id] = group.copy(notices = group.notices.mapNotNull { if (it.id == update.notification.id) changed else it })
            }
            is TdApi.UpdateHavePendingNotifications -> _state.value = _state.value.copy(hasPending = update.haveDelayedNotifications || update.haveUnreceivedNotifications)
            is TdApi.UpdateChatTitle -> chats[update.chatId]?.let { it.title = update.title; groups.replaceAll { _, group -> if (group.chatId == it.id) metadata(group) else group } }
            is TdApi.UpdateChatPermissions -> chats[update.chatId]?.let { it.permissions = update.permissions; groups.replaceAll { _, group -> if (group.chatId == it.id) metadata(group) else group } }
            else -> return@synchronized
        }
        publish()
        if (com.beykus.beygram.BuildConfig.DEBUG && (update is TdApi.UpdateActiveNotifications || update is TdApi.UpdateNotificationGroup)) {
            debugLog("${update.javaClass.simpleName}: active groups=${groups.size}")
        }
        groups.values.map { it.chatId }.distinct().filter { it !in chats && resolving.add(it) }.forEach { id -> scope.launch {
            try { chat(request(TdApi.GetChat(id))) } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { }
            finally { synchronized(lock) { resolving.remove(id) } }
        } }
    }
    private fun metadata(group: TelegramNoticeGroup): TelegramNoticeGroup {
        val archived = isArchived(group.chatId)
        return chats[group.chatId]?.let { chat ->
            group.copy(title = chat.title, metadataReady = true, isGroup = chat.type is TdApi.ChatTypeBasicGroup || chat.type is TdApi.ChatTypeSupergroup,
                isSecret = group.isSecret || chat.type is TdApi.ChatTypeSecret, archived = archived, replyable = replyable(chat))
        } ?: group.copy(archived = archived)
    }
    private fun publish() { _state.value = _state.value.copy(groups = groups.values.sortedBy { it.id }) }
    /** A reply needs a chat the user can write to; channels and secret chats never get one. */
    private fun replyable(chat: TdApi.Chat): Boolean =
        chat.type !is TdApi.ChatTypeSecret && (chat.type as? TdApi.ChatTypeSupergroup)?.isChannel != true && chat.permissions.canSendBasicMessages
    private fun notice(notification: TdApi.Notification): TelegramNotice? = when (val type = notification.type) {
        is TdApi.NotificationTypeNewMessage -> TelegramNotice(notification.id, notification.date.toLong(), senderName(type.message.senderId),
            if (type.showPreview) preview(type.message.content) else UiText.Res(R.string.notif_new_message), type.showPreview, type.message.id,
            (type.message.topicId as? TdApi.MessageTopicForum)?.forumTopicId?.toLong() ?: 0L)
        is TdApi.NotificationTypeNewSecretChat -> TelegramNotice(notification.id, notification.date.toLong(), "", UiText.Res(R.string.notif_new_secret_chat), false)
        else -> null // No FCM registration; push payloads and unimplemented calls are not rendered.
    }
    private fun preview(content: TdApi.MessageContent): UiText = when (content) {
        is TdApi.MessageText -> UiText.Raw(content.text.text.take(1000))
        is TdApi.MessagePhoto -> captioned(content.caption?.text, R.string.notif_preview_photo_caption, R.string.media_kind_photo)
        is TdApi.MessageVideo -> captioned(content.caption?.text, R.string.notif_preview_video_caption, R.string.media_kind_video)
        is TdApi.MessageAnimation -> UiText.Res(R.string.media_kind_animation)
        is TdApi.MessageVoiceNote -> UiText.Res(R.string.notif_preview_voice)
        is TdApi.MessageVideoNote -> UiText.Res(R.string.media_kind_video_note)
        is TdApi.MessageAudio -> UiText.Res(R.string.media_kind_audio)
        is TdApi.MessageDocument -> UiText.Res(R.string.notif_preview_document, listOf(content.document.fileName.take(1000)))
        is TdApi.MessageSticker -> UiText.Res(R.string.chat_preview_sticker, listOf(content.sticker.emoji))
        else -> UiText.Res(R.string.notif_new_message)
    }
    private fun captioned(caption: String?, withCaption: Int, plain: Int): UiText =
        caption?.takeIf { it.isNotBlank() }?.let { UiText.Res(withCaption, listOf(it.take(1000))) } ?: UiText.Res(plain)
}
