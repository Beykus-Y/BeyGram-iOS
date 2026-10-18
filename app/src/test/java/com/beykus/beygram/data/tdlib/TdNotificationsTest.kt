package com.beykus.beygram.data.tdlib

import org.drinkless.tdlib.TdApi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TdNotificationsTest {
    private fun newFeed(archived: () -> Boolean = { false }) = TdNotifications({ error("TDLib is not used in unit tests") }, { "" }, debugLog = {}) { archived() }
        .apply { chat(TdApi.Chat().apply { id = CHAT_ID; title = "Chat"; permissions = chatPermissions(canSend = true) }) }

    private fun chatPermissions(canSend: Boolean) = TdApi.ChatPermissions().apply { canSendBasicMessages = canSend }

    private fun notice(id: Int, silent: Boolean = false) = TdApi.Notification().apply {
        this.id = id
        date = 1_000 + id
        isSilent = silent
        type = TdApi.NotificationTypeNewMessage().apply {
            message = TdApi.Message().apply { senderId = TdApi.MessageSenderUser().apply { userId = 1L } }
        }
    }

    private fun groupUpdate(added: List<TdApi.Notification>, sound: Long = SOUND_ID) = TdApi.UpdateNotificationGroup().apply {
        notificationGroupId = GROUP_ID
        chatId = CHAT_ID
        notificationSoundId = sound
        totalCount = added.size
        addedNotifications = added.toTypedArray()
        removedNotificationIds = intArrayOf()
    }

    private fun contentUpdate(updated: TdApi.Notification) = TdApi.UpdateNotification().apply {
        notificationGroupId = GROUP_ID
        notification = updated
    }

    private fun activeGroup(notices: List<TdApi.Notification>) = TdApi.NotificationGroup().apply {
        id = GROUP_ID
        chatId = CHAT_ID
        totalCount = notices.size
        notifications = notices.toTypedArray()
    }

    @Test fun pendingAlertSurvivesContentUpdateBeforeRender() {
        val feed = newFeed()
        feed.handle(groupUpdate(listOf(notice(7))))
        feed.handle(contentUpdate(notice(7)))
        assertEquals(7, feed.state.value.groups.single().alertId)
    }

    @Test fun silentGroupUpdateKeepsPendingAlert() {
        val feed = newFeed()
        feed.handle(groupUpdate(listOf(notice(7))))
        feed.handle(groupUpdate(listOf(notice(8, silent = true)), sound = 0L))
        assertEquals(7, feed.state.value.groups.single().alertId)
    }

    @Test fun newerSoundedMessageReplacesPendingAlert() {
        val feed = newFeed()
        feed.handle(groupUpdate(listOf(notice(7))))
        feed.handle(groupUpdate(listOf(notice(9))))
        assertEquals(9, feed.state.value.groups.single().alertId)
    }

    @Test fun snapshotKeepsPendingAlertWhileItsNoticeIsActive() {
        val feed = newFeed()
        feed.handle(groupUpdate(listOf(notice(7))))
        feed.handle(TdApi.UpdateActiveNotifications().apply { groups = arrayOf(activeGroup(listOf(notice(7), notice(8, silent = true)))) })
        val state = feed.state.value
        assertTrue(state.snapshot)
        assertEquals(7, state.groups.single().alertId)
    }

    @Test fun snapshotDropsPendingAlertWhoseNoticeIsGone() {
        val feed = newFeed()
        feed.handle(groupUpdate(listOf(notice(7))))
        feed.handle(TdApi.UpdateActiveNotifications().apply { groups = arrayOf(activeGroup(listOf(notice(8, silent = true)))) })
        assertEquals(0, feed.state.value.groups.single().alertId)
    }

    @Test fun firstGroupUpdateDoesNotClaimFullStartupSnapshot() {
        val feed = newFeed()
        feed.handle(groupUpdate(listOf(notice(7))))
        assertTrue(feed.state.value.initialized)
        assertFalse(feed.state.value.snapshot)
        // Old Android tray groups remain until TDLib confirms the full set.
        feed.handle(TdApi.UpdateActiveNotifications().apply { groups = arrayOf(activeGroup(listOf(notice(7)))) })
        assertTrue(feed.state.value.snapshot)
    }

    @Test fun archivedFlagIsRereadWhenChatPositionChanges() {
        var archived = false
        val feed = newFeed { archived }
        feed.handle(groupUpdate(listOf(notice(7))))
        assertFalse(feed.state.value.groups.single().archived)
        archived = true
        feed.chatPositionChanged(CHAT_ID)
        assertTrue(feed.state.value.groups.single().archived)
    }

    @Test fun replyabilityFollowsChatPermissionUpdates() {
        val feed = newFeed()
        feed.handle(groupUpdate(listOf(notice(7))))
        assertTrue(feed.state.value.groups.single().replyable)
        feed.handle(TdApi.UpdateChatPermissions().apply { chatId = CHAT_ID; permissions = chatPermissions(canSend = false) })
        assertFalse(feed.state.value.groups.single().replyable)
        feed.handle(TdApi.UpdateChatPermissions().apply { chatId = CHAT_ID; permissions = chatPermissions(canSend = true) })
        assertTrue(feed.state.value.groups.single().replyable)
    }

    private companion object {
        const val GROUP_ID = 1
        const val CHAT_ID = 10L
        const val SOUND_ID = 5L
    }
}
