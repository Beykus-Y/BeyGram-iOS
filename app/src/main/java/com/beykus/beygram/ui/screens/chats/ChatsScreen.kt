package com.beykus.beygram.ui.screens.chats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material.icons.rounded.Done
import androidx.compose.material.icons.rounded.DoneAll
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.NotificationsOff
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beykus.beygram.R
import com.beykus.beygram.data.appearance.ListDensity
import com.beykus.beygram.domain.UiText
import com.beykus.beygram.domain.model.ChatPreview
import com.beykus.beygram.ui.components.Avatar
import com.beykus.beygram.ui.components.SearchField
import com.beykus.beygram.ui.components.TelegramAvatar
import com.beykus.beygram.domain.model.ProfileInfo
import com.beykus.beygram.domain.model.MediaFileState
import com.beykus.beygram.domain.model.MessageSendState
import com.beykus.beygram.ui.text.resolve
import com.beykus.beygram.ui.text.russianPlural
import kotlin.math.min
import kotlinx.coroutines.flow.StateFlow
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.beykus.beygram.ui.components.beyGramPalette

private enum class ChatFilter(val title: Int) {
    All(R.string.chats_filter_all), People(R.string.chats_filter_people), Groups(R.string.chats_filter_groups), Unread(R.string.chats_filter_unread)
}

/** Сколько протянуть список вниз, чтобы вернуть скрытый архив; подсказка занимает столько же. */
private val archivePullThreshold = 104.dp

@Composable
fun ChatsScreen(
    chats: List<ChatPreview>,
    archivedChats: List<ChatPreview>,
    myProfile: ProfileInfo?,
    observeFile: (Int) -> StateFlow<MediaFileState>,
    downloadFile: (Int) -> Unit,
    onMyProfile: () -> Unit,
    onNotifications: () -> Unit,
    onArchiveClick: () -> Unit,
    onMarkRead: suspend (ChatPreview) -> Boolean,
    onArchive: suspend (ChatPreview) -> Boolean,
    archiveHidden: Boolean,
    onArchiveHiddenChange: (Boolean) -> Unit,
    onChatClick: (ChatPreview) -> Unit
) {
    var query by rememberSaveable { mutableStateOf("") }
    var selectedFilterName by rememberSaveable { mutableStateOf(ChatFilter.All.name) }
    val selectedFilter = ChatFilter.valueOf(selectedFilterName)
    val palette = beyGramPalette()
    val context = LocalContext.current
    var openSwipeChatId by remember { mutableStateOf<Long?>(null) }
    val readAction = ChatSwipeAction(
        label = stringResource(R.string.chats_action_read), icon = Icons.Rounded.DoneAll, container = palette.surface2, content = palette.accentInk,
        enabled = true, perform = onMarkRead
    )
    val archiveAction = ChatSwipeAction(
        label = stringResource(R.string.chats_action_archive), icon = Icons.Rounded.Archive, container = palette.accent, content = palette.onAccent,
        enabled = true, perform = onArchive
    )
    val filteredChats = remember(query, chats, selectedFilter) {
        chats.filter { chat ->
            val matchesQuery = query.isBlank() || chat.title.contains(query, true) || (chat.lastMessage as? UiText.Raw)?.text?.contains(query, true) == true
            val matchesFilter = when (selectedFilter) {
                ChatFilter.All -> true
                ChatFilter.Unread -> chat.unreadCount > 0
                ChatFilter.People -> !chat.isGroup
                ChatFilter.Groups -> chat.isGroup
            }
            matchesQuery && matchesFilter
        }
    }
    val pinnedChats = remember(filteredChats, selectedFilter, query) {
        if (selectedFilter == ChatFilter.All && query.isBlank()) filteredChats.filter { it.isPinned } else emptyList()
    }
    val regularChats = remember(filteredChats, pinnedChats) { filteredChats.filterNot { it in pinnedChats } }
    val unreadTotal = remember(chats) { chats.sumOf { it.unreadCount } }
    val showAllHeader = pinnedChats.isNotEmpty() || (selectedFilter == ChatFilter.All && query.isBlank())
    val archiveAvailable = archivedChats.isNotEmpty() && selectedFilter == ChatFilter.All && query.isBlank()
    val density = LocalDensity.current
    val listState = rememberLazyListState()
    val archivePullThresholdPx = with(density) { archivePullThreshold.toPx() }
    // Сколько протянуто вниз, пока архив скрыт. Подсказка растёт до порога, а за порогом архив возвращается при отпускании.
    var pullPx by remember { mutableFloatStateOf(0f) }
    val pullCanReveal by rememberUpdatedState(archiveAvailable && archiveHidden)
    val latestOnArchiveHiddenChange by rememberUpdatedState(onArchiveHiddenChange)
    val pullConnection = remember(listState, archivePullThresholdPx) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // Архив мог исчезнуть или вернуться посреди протяжки: без скрытого архива протяжки быть не должно.
                if (!pullCanReveal) pullPx = 0f
                if (source != NestedScrollSource.UserInput) return Offset.Zero
                val atTop = listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0
                return when {
                    available.y > 0f && pullCanReveal && atTop -> {
                        pullPx = minOf(pullPx + available.y, archivePullThresholdPx)
                        Offset(0f, available.y)
                    }
                    available.y < 0f && pullPx > 0f -> {
                        val back = minOf(-available.y, pullPx)
                        pullPx -= back
                        Offset(0f, -back)
                    }
                    else -> Offset.Zero
                }
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (pullPx <= 0f) return Velocity.Zero
                val reveal = pullPx >= archivePullThresholdPx
                pullPx = 0f
                if (reveal) latestOnArchiveHiddenChange(false)
                return available
            }
        }
    }
    // Если жест прервали системой, onPreFling не придёт: сбрасываем протяжку, когда список перестал скроллиться.
    LaunchedEffect(listState.isScrollInProgress) {
        if (!listState.isScrollInProgress) pullPx = 0f
    }

    Column(
        modifier = Modifier.fillMaxSize().background(palette.screen).windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.app_name).uppercase(), color = palette.accent, style = MaterialTheme.typography.labelMedium, letterSpacing = 0.8.sp)
                    Text(stringResource(R.string.chats_title), color = palette.textPrimary, fontSize = 30.sp, lineHeight = 33.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp)
                }
                androidx.compose.material3.IconButton(onClick = onNotifications, modifier = Modifier.semantics { contentDescription = context.getString(R.string.chats_notifications_description) }) {
                    Icon(Icons.Rounded.Notifications, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(24.dp))
                }
                Spacer(Modifier.width(4.dp))
                TelegramAvatar(myProfile?.initials ?: stringResource(R.string.chats_avatar_fallback), palette.accent, 40.dp, myProfile?.photo, observeFile, downloadFile,
                    Modifier.semantics { contentDescription = context.getString(R.string.chats_my_profile_description) }.clickable(onClick = onMyProfile))
            }

            Spacer(Modifier.height(14.dp))
            SearchField(query = query, onChange = { query = it }, placeholder = stringResource(R.string.chats_search_placeholder))
            Spacer(Modifier.height(12.dp))
            Row(modifier = Modifier.fillMaxWidth().horizontalScroll(androidx.compose.foundation.rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChatFilter.entries.forEach { filter ->
                    FilterChip(
                        title = stringResource(filter.title),
                        selected = selectedFilter == filter,
                        count = if (filter == ChatFilter.Unread) unreadTotal else null,
                        onClick = { selectedFilterName = filter.name }
                    )
                }
            }
        }

        ArchivePullSlot(shownPx = { if (archiveAvailable && archiveHidden) min(pullPx, archivePullThresholdPx) else 0f })
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).nestedScroll(pullConnection),
            contentPadding = PaddingValues(bottom = 20.dp)
        ) {
            if (archiveAvailable && !archiveHidden) {
                item(key = "archive_row") { ArchiveRow(archivedChats, onClick = onArchiveClick, onHide = { onArchiveHiddenChange(true) }) }
            }
            if (pinnedChats.isNotEmpty()) {
                item(key = "pinned_header") {
                    Text(stringResource(R.string.chats_section_pinned), modifier = Modifier.padding(start = 20.dp, top = 18.dp, bottom = 6.dp), color = palette.textSecondary, style = MaterialTheme.typography.labelSmall)
                }
                items(pinnedChats, key = { "pinned_${it.id}" }) { chat ->
                    SwipeChatRow(
                        chat = chat,
                        observeFile = observeFile,
                        downloadFile = downloadFile,
                        openChatId = openSwipeChatId,
                        onOpenChange = { openSwipeChatId = it },
                        onClick = { onChatClick(chat) },
                        read = readAction.copy(enabled = chat.unreadCount > 0),
                        primary = archiveAction
                    )
                }
            }
            if (regularChats.isEmpty() && pinnedChats.isEmpty()) {
                item(key = "empty_state") { EmptyState(selectedFilter, query) }
            } else {
                if (showAllHeader && regularChats.isNotEmpty()) {
                    item(key = "all_header") {
                        Text(stringResource(R.string.chats_section_all), modifier = Modifier.padding(start = 20.dp, top = 18.dp, bottom = 6.dp), color = palette.textSecondary, style = MaterialTheme.typography.labelSmall)
                    }
                }
                items(regularChats, key = { it.id }) { chat ->
                    SwipeChatRow(
                        chat = chat,
                        observeFile = observeFile,
                        downloadFile = downloadFile,
                        openChatId = openSwipeChatId,
                        onOpenChange = { openSwipeChatId = it },
                        onClick = { onChatClick(chat) },
                        read = readAction.copy(enabled = chat.unreadCount > 0),
                        primary = archiveAction
                    )
                }
            }
        }
    }
}

@Composable
private fun ArchiveRow(archivedChats: List<ChatPreview>, onClick: () -> Unit, onHide: () -> Unit) {
    val palette = beyGramPalette()
    val context = LocalContext.current
    var actionsOpen by remember { mutableStateOf(false) }
    val unread = archivedChats.sumOf { it.unreadCount }
    val summary = buildString {
        append("${archivedChats.size} ${russianPlural(archivedChats.size, context.getString(R.string.chats_archive_count_one), context.getString(R.string.chats_archive_count_few), context.getString(R.string.chats_archive_count_many))}")
        if (unread > 0) append(" · $unread ${russianPlural(unread, context.getString(R.string.chats_archive_unread_one), context.getString(R.string.chats_archive_unread_few), context.getString(R.string.chats_archive_unread_few))}")
    }
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(20.dp)).background(palette.surface)
                .combinedClickable(onClick = onClick, onLongClick = { actionsOpen = true })
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(modifier = Modifier.size(44.dp).clip(CircleShape).background(palette.surface2), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Archive, contentDescription = null, tint = palette.accentInk, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.chats_archive_title), color = palette.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Text(summary, color = palette.textSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(22.dp))
        }
        if (actionsOpen) {
            // Действия открываются прямо под строкой, без всплывающего окна.
            Column(
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp)
                    .clip(RoundedCornerShape(20.dp)).background(palette.surface).padding(vertical = 4.dp)
            ) {
                ArchiveAction(Icons.Rounded.VisibilityOff, stringResource(R.string.chats_archive_hide), palette.accent, palette.accentInk, FontWeight.SemiBold, onHide)
                Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(palette.divider))
                ArchiveAction(Icons.Rounded.Close, stringResource(R.string.common_cancel), palette.textSecondary, palette.textSecondary, FontWeight.Normal) { actionsOpen = false }
            }
        }
    }
}

@Composable
private fun ArchiveAction(icon: ImageVector, label: String, iconTint: Color, labelColor: Color, labelWeight: FontWeight, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(label, color = labelColor, fontSize = 16.sp, fontWeight = labelWeight)
    }
}

/** Читает протяжку внутри себя: частые шаги жеста перерисовывают только подсказку, а не весь экран чатов. */
@Composable
private fun ArchivePullSlot(shownPx: () -> Float) {
    val density = LocalDensity.current
    val px = shownPx()
    if (px > 0f) ArchivePullHint(heightDp = with(density) { px.toDp() })
}

/** Подсказка над списком, пока архив скрыт и список тянут вниз: высота растёт вместе с протяжкой. */
@Composable
private fun ArchivePullHint(heightDp: Dp) {
    val palette = beyGramPalette()
    Column(
        modifier = Modifier.fillMaxWidth().height(heightDp).clipToBounds()
            .background(Brush.verticalGradient(listOf(palette.accentSoft, Color.Transparent))),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(modifier = Modifier.size(36.dp).clip(CircleShape).background(palette.surface), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.ArrowDownward, contentDescription = null, tint = palette.accent, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.height(6.dp))
        Text(stringResource(R.string.chats_archive_pull_hint), color = palette.accentInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

@Composable
private fun FilterChip(title: String, selected: Boolean, count: Int?, onClick: () -> Unit) {
    val palette = beyGramPalette()
    Row(
        modifier = Modifier.height(34.dp).clip(RoundedCornerShape(50)).background(if (selected) palette.accent else palette.surface2)
            .clickable(onClick = onClick).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, color = if (selected) palette.onAccent else palette.textPrimary, fontSize = 14.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium)
        if (count != null && count > 0) {
            Spacer(Modifier.width(6.dp))
            Text(count.toString(), color = if (selected) palette.onAccent else palette.accent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun EmptyState(filter: ChatFilter, query: String) {
    val palette = beyGramPalette()
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 36.dp, vertical = 72.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(if (query.isNotBlank()) Icons.Rounded.Search else Icons.Rounded.Cloud, contentDescription = null, tint = palette.accent, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(12.dp))
        Text(
            text = when {
                query.isNotBlank() -> stringResource(R.string.chats_empty_no_results)
                filter == ChatFilter.Unread -> stringResource(R.string.chats_empty_all_read)
                filter == ChatFilter.Groups -> stringResource(R.string.chats_empty_no_groups)
                else -> stringResource(R.string.chats_empty_quiet)
            },
            color = palette.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold
        )
        Spacer(Modifier.height(5.dp))
        Text(stringResource(R.string.chats_empty_hint), color = palette.textSecondary, fontSize = 14.sp)
    }
}

/** Текст последнего сообщения с префиксом автора: «Вы» для своих и имя отправителя в группах. */
@Composable
private fun previewLine(chat: ChatPreview, emptyPreview: Boolean): String {
    if (emptyPreview) return stringResource(if (chat.isGroup) R.string.chats_group_preview else R.string.chats_start_conversation)
    val author = when {
        chat.lastMessageOutgoing -> stringResource(R.string.chat_you)
        chat.isGroup && chat.lastMessageSender.isNotBlank() -> chat.lastMessageSender
        else -> null
    }
    val body = chat.lastMessage.resolve()
    return if (author == null) body else stringResource(R.string.chats_preview_sender, author) + body
}

/** Статус своего последнего сообщения: отправляется, отправлено, прочитано или не отправлено. */
@Composable
private fun SendStatusIcon(chat: ChatPreview) {
    val palette = beyGramPalette()
    if (!chat.lastMessageOutgoing) return
    val modifier = Modifier.padding(start = 6.dp).size(16.dp)
    when (chat.lastMessageSendState) {
        MessageSendState.Sending -> Icon(Icons.Rounded.Schedule, stringResource(R.string.chat_sending_description), tint = palette.textSecondary, modifier = modifier)
        MessageSendState.Failed -> Icon(Icons.Rounded.ErrorOutline, stringResource(R.string.chat_status_not_sent), tint = palette.warningText, modifier = modifier)
        MessageSendState.Sent -> {
            val read = chat.lastMessageId > 0L && chat.lastMessageId <= chat.lastReadOutboxMessageId
            if (read) Icon(Icons.Rounded.DoneAll, stringResource(R.string.chat_read_description), tint = palette.accent, modifier = modifier)
            else Icon(Icons.Rounded.Done, stringResource(R.string.chat_sent_description), tint = palette.textSecondary, modifier = modifier)
        }
    }
}

/** Плотность списка чатов: сколько места отдано каждой строке. [Default] — вид, который BeyGram всегда имел. */
internal data class ChatListDensity(
    /** Отступ над и под содержимым строки чата. */
    val rowVerticalPadding: Dp = 10.dp
)

internal val LocalChatListDensity = compositionLocalOf { ChatListDensity() }

/** Строки списка чатов для выбранной плотности. [ListDensity.Comfortable] даёт прежний отступ строки. */
internal fun chatListDensityFor(density: ListDensity): ChatListDensity = when (density) {
    ListDensity.Compact -> ChatListDensity(rowVerticalPadding = 6.dp)
    ListDensity.Comfortable -> ChatListDensity()
    ListDensity.Spacious -> ChatListDensity(rowVerticalPadding = 14.dp)
}

@Composable
internal fun ChatListItem(chat: ChatPreview, observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, onClick: () -> Unit) {
    val palette = beyGramPalette()
    val listDensity = LocalChatListDensity.current
    val unread = chat.unreadCount > 0
    val emptyPreview = (chat.lastMessage as? UiText.Raw)?.text?.isBlank() == true
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = listDensity.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TelegramAvatar(chat.initials, Color(chat.avatarColorArgb), 54.dp, chat.photo, observeFile, downloadFile)
        Spacer(Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(chat.title, color = palette.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(6.dp))
                Text(chat.lastMessageTime, color = if (unread) palette.accent else palette.textSecondary, fontSize = 12.sp, fontWeight = if (unread) FontWeight.SemiBold else FontWeight.Normal)
            }
            Spacer(Modifier.height(3.dp))
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (chat.isMuted) Icon(Icons.Rounded.NotificationsOff, null, tint = palette.textSecondary, modifier = Modifier.padding(end = 6.dp).size(16.dp))
                Text(previewLine(chat, emptyPreview), color = palette.textSecondary, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                SendStatusIcon(chat)
                if (unread) {
                    Spacer(Modifier.width(8.dp))
                    // Чат без звука получает серый счётчик, как в Telegram.
                    val badgeColor = if (chat.isMuted) palette.textSecondary else palette.accent
                    Box(modifier = Modifier.defaultMinSize(minWidth = 22.dp).height(22.dp).clip(RoundedCornerShape(11.dp)).background(badgeColor).padding(horizontal = 7.dp), contentAlignment = Alignment.Center) {
                        Text(if (chat.unreadCount > 99) "99+" else chat.unreadCount.toString(), color = palette.onAccent, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}
