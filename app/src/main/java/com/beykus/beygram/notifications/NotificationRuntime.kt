package com.beykus.beygram.notifications

import android.content.Context
import com.beykus.beygram.R
import com.beykus.beygram.data.tdlib.TdLibBootstrap
import com.beykus.beygram.data.tdlib.TdLibTelegramRepository
import com.beykus.beygram.data.vpn.VpnBackend
import com.beykus.beygram.diagnostics.recordAppEvent
import com.beykus.beygram.diagnostics.report.EventKind
import com.beykus.beygram.diagnostics.report.Severity
import com.beykus.beygram.domain.UiText
import com.beykus.beygram.domain.UserMessageException
import com.beykus.beygram.domain.model.AuthState
import com.beykus.beygram.domain.repository.TelegramRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** Process-level presenter; the service and UI share the same TDLib instance and subscriptions. */
class NotificationRuntime private constructor(private val context: Context) {
    val preferences = NotificationPreferencesStore(context)
    private val renderer = AndroidNotificationRenderer(context, preferences)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    @Volatile private var repository: TelegramRepository? = null
    private val flushing = ConcurrentHashMap.newKeySet<Int>()
    private val dismissRetryRounds = ConcurrentHashMap<Int, Int>()
    private val dismissNotBefore = ConcurrentHashMap<Int, Long>()
    private val dismissRetryScheduled = ConcurrentHashMap.newKeySet<Int>()
    private val replyOutbox by lazy { ReplyOutbox(File(context.noBackupFilesDir, REPLY_OUTBOX_DIRECTORY)) }
    private val replyInFlight = ConcurrentHashMap.newKeySet<String>()
    private val replyRetryScheduled = AtomicBoolean(false)
    private val invalidations = MutableStateFlow(0L)
    private val _service = MutableStateFlow(false)
    val serviceRunning = _service.asStateFlow()
    private val _serviceError = MutableStateFlow<UiText?>(null)
    val serviceError = _serviceError.asStateFlow()
    private val _authorized = MutableStateFlow(false)
    val authorized = _authorized.asStateFlow()
    fun serviceState(running: Boolean, error: UiText? = null) { _service.value = running; if (running || error != null) _serviceError.value = error }

    @Synchronized fun attach(source: TelegramRepository) {
        if (repository != null) return
        repository = source
        scope.launch {
            combine(source.notifications, source.notificationPresentation, source.authState, preferences.state, invalidations) { notices, presentation, auth, config, _ ->
                // Turning off background notifications does not close the TDLib session used by an open UI,
                // but it must stop posting from a still-alive process once every screen is closed.
                if (config.background || presentation.foreground) {
                    runCatching { renderer.render(notices, config, presentation, auth == AuthState.Ready) }
                        .onFailure { android.util.Log.w("BeyGramNotify", "Notification rendering failed: ${it.javaClass.simpleName}") }
                }
            }.collect()
        }
        scope.launch { source.authState.collect { auth ->
            when (auth) {
                AuthState.Ready -> { preferences.authorized = true; flushDismissals(); flushReplies() }
                AuthState.WaitingForPhone -> {
                    // The sign-out replaces the session token before the outbox is cleared. A reply that the clear misses
                    // belongs to the old token, so it is never sent.
                    preferences.authorized = false
                    dismissRetryRounds.clear()
                    dismissNotBefore.clear()
                    val kept = outbox { clear() }
                    if (kept > 0) recordAppEvent(EventKind.NOTIFICATION, "reply_clear_failed", "Ответы из уведомлений не удалось убрать при выходе", Severity.WARNING, mapOf("count" to kept.toString()))
                }
                else -> Unit
            }
            _authorized.value = auth == AuthState.Ready
        } }
        scope.launch { source.connectionState.collect { flushDismissals() } }
    }
    fun refresh() {
        repository?.authState?.value?.let { auth ->
            if (auth == AuthState.Ready) preferences.authorized = true
            else if (auth == AuthState.WaitingForPhone) preferences.authorized = false
            _authorized.value = auth == AuthState.Ready
        }
        invalidations.update { it + 1 }
    }
    fun dismiss(groupId: Int, maxId: Int) {
        if (groupId <= 0 || maxId <= 0) return
        preferences.dismiss(groupId, maxId)
        // A new explicit dismissal may retry even when an earlier group reached its budget.
        dismissRetryRounds.remove(groupId)
        dismissNotBefore.remove(groupId)
        renderer.cancelGroup(groupId)
        refresh(); flushDismissals()
    }
    /**
     * Sends a reply typed in a notification. The reply is written to the outbox, so a process that stops before the send finishes
     * sends it at the next start. The write and the send share the broadcast's time budget: [finished] ends the broadcast in time,
     * and a write or send that is slower keeps running after it. An accepted send dismisses the group; a rejected one keeps the
     * notification and marks it. [session] is the session token that validated the action.
     */
    fun reply(chatId: Long, groupId: Int, maxId: Int, replyToMessageId: Long, topicId: Long, text: String, session: String, finished: () -> Unit) {
        scope.launch {
            try {
                // A blank reply sends nothing; re-posting the notification still clears the inline field.
                // The reply is written before the broadcast ends, so a process that stops after that still sends it later.
                val pending = if (text.isBlank()) null else storeReply(chatId, groupId, maxId, replyToMessageId, topicId, text, session)
                val work = launch {
                    // The submitted action is spent, so the notification is re-posted; re-posting needs an attached repository.
                    if (repository == null) runCatching { attachRealClient() }
                    if (pending == null) refresh() else if (!deliverReply(pending)) scheduleReplyRetry()
                }
                withTimeoutOrNull(REPLY_BROADCAST_MILLIS) { work.join() }
            } finally {
                finished()
            }
        }
    }
    /**
     * Keeps the reply on disk under the session token that validated it. A reply made while signed out, or one the disk refuses,
     * is sent once and not kept.
     */
    private suspend fun storeReply(chatId: Long, groupId: Int, maxId: Int, replyToMessageId: Long, topicId: Long, text: String, session: String): PendingReply {
        val now = System.currentTimeMillis()
        val saved: ReplyOutbox.Entry? = if (repository?.authState?.value == AuthState.WaitingForPhone) null else try {
            outbox { add(chatId, groupId, maxId, replyToMessageId, text, now, session, topicId) }
        } catch (error: IOException) {
            recordAppEvent(EventKind.NOTIFICATION, "reply_not_stored", "Ответ из уведомления не удалось сохранить", Severity.WARNING, mapOf("cause" to error.javaClass.simpleName))
            null
        }
        val entry = saved ?: ReplyOutbox.Entry(
            id = UUID.randomUUID().toString(), session = session, chatId = chatId, groupId = groupId, maxId = maxId,
            replyToMessageId = replyToMessageId, topicId = topicId, text = text, createdAtMillis = now, attempts = 0
        )
        return PendingReply(entry, stored = saved != null)
    }
    /** Sends one reply. Returns false when the send failed and the reply stays stored for another attempt. */
    private suspend fun deliverReply(pending: PendingReply): Boolean {
        val entry = pending.entry
        // One attempt at a time: a flush does not send a reply that the broadcast is still sending.
        if (!replyInFlight.add(entry.id)) return true
        try {
            // A stored reply that is no longer in the outbox was sent already, or cleared by a sign-out.
            if (pending.stored && !outbox { isStored(entry.id) }) return true
            val failure = sendReply(pending).exceptionOrNull()
            if (failure is AccountChangedException) {
                // The reply was made in a session that has signed out since. It is dropped without a failed mark.
                if (pending.stored) outbox { remove(entry.id) }
                recordAppEvent(EventKind.NOTIFICATION, "reply_account_changed", "Ответ из уведомления отменён: аккаунт сменился", Severity.WARNING)
                return true
            }
            if (failure == null) {
                // A reply that stays in the outbox after it was sent would be sent again at the next start.
                // Delivery is at least once: TDLib accepted the send, but a stop before this removal sends it again.
                if (pending.stored && !outbox { remove(entry.id) }) recordAppEvent(EventKind.NOTIFICATION, "reply_remove_failed", "Отправленный ответ не удалось убрать из очереди", Severity.WARNING)
                recordAppEvent(EventKind.NOTIFICATION, "reply_sent", "Ответ из уведомления отправлен")
                dismiss(entry.groupId, entry.maxId)
                return true
            }
            // The note belongs to the newest notice at this moment, so a notice that arrives later clears it.
            val newest = repository?.notifications?.value?.groups?.firstOrNull { it.id == entry.groupId }?.notices?.maxOfOrNull { it.id } ?: entry.maxId
            renderer.markReplyFailed(entry.groupId, newest)
            recordAppEvent(EventKind.NOTIFICATION, "reply_failed", "Ответ из уведомления не отправлен", Severity.WARNING, mapOf("cause" to failure.javaClass.simpleName))
            refresh()
            if (!pending.stored) return true
            // A reply that is too long for Telegram fails the same way every time, so it is dropped at once.
            val attemptLimit = if (failure.isPermanentReplyFailure()) entry.attempts + 1 else MAX_REPLY_ATTEMPTS
            // If the outbox cannot record the failure, the reply keeps its count and is tried again.
            val dropped = try { outbox { recordFailure(entry, attemptLimit) } } catch (error: IOException) { false }
            if (dropped) recordAppEvent(EventKind.NOTIFICATION, "reply_dropped", "Ответ из уведомления отброшен после повторных попыток", Severity.WARNING)
            return dropped
        } finally {
            replyInFlight.remove(entry.id)
        }
    }
    /**
     * Sends the stored replies of the signed-in session. A reply that fails stays stored for a later attempt. Flushes do not wait
     * for each other: a reply that another attempt is sending is skipped, and that attempt schedules its own retry.
     */
    private fun flushReplies() {
        if (repository?.authState?.value != AuthState.Ready) return
        scope.launch {
            var retry = false
            val expired = outbox { discardExpired(System.currentTimeMillis(), REPLY_TTL_MILLIS) }
            if (expired > 0) recordAppEvent(EventKind.NOTIFICATION, "reply_expired", "Устаревшие ответы из уведомлений удалены", Severity.WARNING, mapOf("count" to expired.toString()))
            val snapshot = outbox { entries() }
            // The session is read after the snapshot, so a sign-out that came since then is seen before anything is sent.
            val session = preferences.replyToken()
            for (entry in snapshot) {
                // A reply from an earlier session is not sent, and it is removed from the outbox.
                if (entry.session != session) {
                    outbox { remove(entry.id) }
                    continue
                }
                if (!deliverReply(PendingReply(entry, stored = true))) retry = true
            }
            if (retry) scheduleReplyRetry()
        }
    }
    /** One retry at a time, so failures in a row do not multiply the scheduled attempts. */
    private fun scheduleReplyRetry() {
        if (!replyRetryScheduled.compareAndSet(false, true)) return
        scope.launch {
            delay(REPLY_RETRY_MILLIS)
            replyRetryScheduled.set(false)
            flushReplies()
        }
    }
    /** Outbox files are read and written off the main thread. */
    private suspend fun <T> outbox(block: ReplyOutbox.() -> T): T = withContext(Dispatchers.IO) { replyOutbox.block() }
    /** A reply on its way to Telegram. Only a [stored] reply is kept on disk until it is sent. */
    private class PendingReply(val entry: ReplyOutbox.Entry, val stored: Boolean)
    /** The session that made the reply signed out before the reply was sent. */
    private class AccountChangedException : IllegalStateException("Telegram account changed before the reply was sent")
    /**
     * A reply belongs to the session that made it. A sign-out replaces the session token, so a reply from an earlier session no
     * longer matches. A stored reply also needs its outbox entry, so a copy that was sent or cleared is not sent again.
     */
    private suspend fun stillOwned(pending: PendingReply): Boolean =
        pending.entry.session == preferences.replyToken() && (!pending.stored || outbox { isStored(pending.entry.id) })
    private suspend fun sendReply(pending: PendingReply): Result<Unit> = try {
        val entry = pending.entry
        val source = repository ?: attachRealClient() ?: throw IllegalStateException("Telegram client is unavailable")
        // The reply is sent only while it still belongs to the session that made it.
        if (!stillOwned(pending)) throw AccountChangedException()
        // A signed-out account cannot send, and a reply does not wait for another account to sign in.
        if (source.authState.value == AuthState.WaitingForPhone) throw IllegalStateException("Telegram client is not authorized")
        // A reply that starts the process can arrive before TDLib has authorized, and TDLib rejects requests until then.
        // Without authorization in time the reply is not sent, and the notification is marked as failed.
        withTimeoutOrNull(REPLY_READY_MILLIS) { source.authState.first { it == AuthState.Ready } }
            ?: throw IllegalStateException("Telegram client is not authorized")
        // A sign-out while the reply waited ends it.
        if (!stillOwned(pending)) throw AccountChangedException()
        // Replying to the notified message puts the answer in its forum topic, too.
        val replyId = entry.replyToMessageId.takeIf { it > 0L }
        val sent = source.sendMessage(entry.chatId, entry.text, replyId, forumTopicId = entry.topicId)
        // The notified message can be deleted or no longer take replies since the notice. Then the text goes out as a plain message.
        if (replyId == null || !sent.exceptionOrNull().isReplyRejected()) sent else {
            // The session can change while the first send waits, so the fallback needs the same ownership check.
            if (!stillOwned(pending)) throw AccountChangedException()
            when {
                // The topic was stored with the reply, so the fallback lands in it.
                entry.topicId > 0L -> source.sendMessage(entry.chatId, entry.text, null, forumTopicId = entry.topicId)
                // In a forum the topic lives on the replied-to message, which is gone. A plain send would land in General, so it is not sent.
                source.isForumChat(entry.chatId).getOrDefault(true) -> sent
                else -> source.sendMessage(entry.chatId, entry.text, null)
            }
        }
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        Result.failure(error)
    }

    /** Telegram refused the message this reply points at, not the reply itself. */
    private fun Throwable?.isReplyRejected(): Boolean {
        val id = (((this as? UserMessageException)?.text) as? UiText.Res)?.id ?: return false
        return id == R.string.err_message_cannot_reply || id == R.string.err_tdlib_message_unavailable
    }

    /** Telegram refuses this reply every time it is sent, so retrying cannot help. */
    private fun Throwable.isPermanentReplyFailure(): Boolean =
        ((this as? UserMessageException)?.text as? UiText.Res)?.id == R.string.err_message_too_long || isReplyRejected()

    private fun flushDismissals() {
        val source = repository ?: return
        if (source.authState.value != AuthState.Ready) return
        preferences.pendingDismissals().forEach { (group, max) ->
            if (System.currentTimeMillis() < (dismissNotBefore[group] ?: 0L)) return@forEach
            if (!flushing.add(group)) return@forEach
            scope.launch {
            var accepted = false
            var tries = 0
            try {
                // Bounded retry with backoff: a transient TDLib failure must not wait for an unrelated event.
                repeat(DISMISS_ATTEMPTS) { attempt ->
                    if (accepted) return@repeat
                    if (attempt > 0) delay(DISMISS_RETRY_MILLIS shl (attempt - 1))
                    tries++
                    accepted = source.dismissNotifications(group, max).isSuccess
                }
                if (accepted) {
                    preferences.acknowledge(group, max)
                    dismissRetryRounds.remove(group)
                    dismissNotBefore.remove(group)
                } else {
                    scheduleDismissRetry(group)
                }
            } finally {
                flushing.remove(group)
                // Newer dismissals will retry after the failure cooldown, never in a busy loop.
                if ((preferences.pendingDismissals()[group] ?: 0) > max) flushDismissals()
            }
            recordDismiss(accepted, tries)
        } }
    }
    /** Schedule a finite second-level retry window, deduplicated by group. */
    private fun scheduleDismissRetry(group: Int) {
        if (preferences.pendingDismissals()[group] == null) return
        val round = dismissRetryRounds.merge(group, 1, Int::plus) ?: 1
        if (round > MAX_DISMISS_RETRY_ROUNDS) {
            dismissNotBefore[group] = Long.MAX_VALUE
            return
        }
        val backoff = DISMISS_ROUND_BACKOFF_MILLIS * (1L shl (round - 1))
        dismissNotBefore[group] = System.currentTimeMillis() + backoff
        if (!dismissRetryScheduled.add(group)) return
        scope.launch {
            try {
                while (true) {
                    val due = dismissNotBefore[group] ?: break
                    if (due == Long.MAX_VALUE) break
                    delay((due - System.currentTimeMillis()).coerceAtLeast(0L))
                    // A newer dismissal can extend the cooldown while this job sleeps.
                    if (!dismissNotBefore.remove(group, due)) continue
                    dismissRetryScheduled.remove(group)
                    flushDismissals()
                    return@launch
                }
            } finally {
                dismissRetryScheduled.remove(group)
            }
        }
    }

    private fun recordDismiss(accepted: Boolean, tries: Int) = when {
        !accepted -> recordAppEvent(EventKind.NOTIFICATION, "dismiss_failed", "Смахивание не отправлено, попыток: $tries", Severity.WARNING, mapOf("tries" to tries.toString()))
        tries > 1 -> recordAppEvent(EventKind.NOTIFICATION, "dismiss_retried", "Смахивание отправлено с попытки $tries", attrs = mapOf("tries" to tries.toString()))
        else -> Unit
    }
    /**
     * [startProxy] is false when a dismissal from the background attaches: starting the proxy there can be refused by Android 12+,
     * and the dismissal is flushed when the app or a reply attaches with the proxy.
     */
    fun attachRealClient(startProxy: Boolean = true): TelegramRepository? {
        if (!TdLibBootstrap(context).readiness().canCreateClient) return null
        val repository = TdLibTelegramRepository.getInstance(context)
        // TDLib keeps the saved proxy, and only the backend restarts its local listener. A cold reply skips the application's
        // start-up path when background notifications are off, so the backend is created here before the client is used.
        if (startProxy) VpnBackend.getInstance(context, repository.connectionState, scope, repository::setMihomoProxyEnabled, repository::isMihomoProxyEnabled)
        return repository.also(::attach)
    }
    companion object {
        private const val DISMISS_ATTEMPTS = 4
        private const val DISMISS_RETRY_MILLIS = 2_000L
        private const val DISMISS_ROUND_BACKOFF_MILLIS = 30_000L
        private const val MAX_DISMISS_RETRY_ROUNDS = 3
        // Bounds the write and the send of a reply broadcast inside the receiver's time limit; a slower one still completes.
        private const val REPLY_BROADCAST_MILLIS = 8_000L
        // Longest wait for TDLib's authorization after the broadcast has ended; the send itself is not bound to the broadcast.
        private const val REPLY_READY_MILLIS = 30_000L
        // A failed reply is tried again after REPLY_RETRY_MILLIS. A stored reply is dropped after MAX_REPLY_ATTEMPTS failures,
        // or once it is older than REPLY_TTL_MILLIS.
        private const val REPLY_RETRY_MILLIS = 60_000L
        private const val MAX_REPLY_ATTEMPTS = 5
        private const val REPLY_TTL_MILLIS = 24 * 60 * 60 * 1000L
        private const val REPLY_OUTBOX_DIRECTORY = "reply-outbox"
        @Volatile private var instance: NotificationRuntime? = null
        fun get(context: Context): NotificationRuntime = instance ?: synchronized(this) {
            instance ?: NotificationRuntime(context.applicationContext).also { instance = it }
        }
    }
}
