package com.beykus.beygram.ui.screens.profile

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beykus.beygram.R
import com.beykus.beygram.data.presence.LastSeenStyle
import com.beykus.beygram.domain.model.*
import com.beykus.beygram.ui.components.TelegramAvatar
import com.beykus.beygram.ui.components.beyGramPalette
import com.beykus.beygram.ui.screens.chat.SharedMediaWindow
import com.beykus.beygram.ui.text.resolve
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Вкладки профиля группы. «Участники» показываются списком из профиля, остальные берут окна вложений. */
internal enum class GroupTab(val kind: SharedMediaKind?) {
    Members(null), Media(SharedMediaKind.Media), Files(SharedMediaKind.Files), Links(SharedMediaKind.Links), Voice(SharedMediaKind.Voice)
}

/** Во сколько раз уменьшается аватар, когда шапка свёрнута. */
private const val AVATAR_SHRINK = 0.5f
private val SHARED_STATUS_HEIGHT = 240.dp

/** Доля сжатия шапки: 0 — раскрыта, 1 — свёрнута. Свёрнута, как только первым на экране стал элемент после шапки. */
internal fun collapseFraction(firstVisibleIndex: Int, scrollOffsetPx: Int, collapseRangePx: Int): Float {
    if (firstVisibleIndex > 0) return 1f
    if (collapseRangePx <= 0) return 0f
    return (scrollOffsetPx.toFloat() / collapseRangePx).coerceIn(0f, 1f)
}

/**
 * Профиль группы одним списком: шапка сжимается при прокрутке, название переезжает в панель, полоска вкладок закрепляется сверху.
 * Вкладки вложений догружают страницы по мере прокрутки, как в профиле чата.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun GroupProfileScreen(
    info: ProfileInfo, state: ProfileState, lastSeenStyle: LastSeenStyle,
    observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit,
    onBack: () -> Unit, onRefresh: () -> Unit, onAvatarClick: () -> Unit,
    onMembers: () -> Unit, onOpenUser: (Long) -> Unit,
    sharedMessages: (suspend (SharedMediaKind, Long, Boolean) -> Result<MessageSearchPage>)?, confirmExport: suspend (Long) -> Boolean,
    onContentOpened: (Long) -> Unit, onOpenMessage: (Long) -> Unit
) {
    val palette = beyGramPalette()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    var headerHeightPx by remember { mutableIntStateOf(0) }
    // Прокрутку читаем только при рисовании: иначе каждый кадр прокрутки перекомпоновывал бы весь экран.
    val collapse = remember { derivedStateOf { collapseFraction(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset, headerHeightPx) } }
    val windows = rememberSharedMediaWindows(info.id) { kind, from, newer -> sharedMessages?.invoke(kind, from, newer) ?: Result.failure(IllegalStateException()) }
    val tabs = if (sharedMessages == null) listOf(GroupTab.Members) else GroupTab.entries
    var selectedTab by rememberSaveable(info.id) { mutableStateOf(GroupTab.Members) }
    // Сохранённая вкладка может пропасть из полоски, если источника вложений больше нет: тогда показываем участников.
    val activeTab = selectedTab.takeIf { it in tabs } ?: GroupTab.Members
    var viewing by remember(info.id) { mutableStateOf<Long?>(null) }
    val window = activeTab.kind?.let { windows.getValue(it) }
    val title = info.title.ifBlank { stringResource(R.string.user_name_unknown) }
    // Индекс полоски вкладок в списке: перед ней идут шапка, строки и, если есть, администраторы.
    val tabsIndex = if (info.administrators.isEmpty()) 2 else 3
    val nearEnd by remember { derivedStateOf { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.let { it.index >= listState.layoutInfo.totalItemsCount - PREFETCH_ROWS } ?: true } }
    // Пока список дошёл до конца вкладки, грузим её страницы; первая страница вкладки грузится тем же путём.
    if (window != null) LaunchedEffect(window, nearEnd, window.messages.size, window.hasOlder) {
        if (nearEnd && window.hasOlder) window.loadOlder()
    }
    Column(Modifier.fillMaxSize().background(palette.screen).windowInsetsPadding(WindowInsets.safeDrawing)) {
        GroupProfileToolbar(title, collapse, refreshEnabled = !state.isLoading, onBack = onBack, onRefresh = onRefresh)
        if (state.isLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
        // Ошибку показываем над списком: в конце длинной вкладки она оказалась бы за сотнями строк.
        state.error?.let { error -> Text(error.resolve(), color = palette.danger, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) }
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = listState, contentPadding = PaddingValues(bottom = 28.dp)) {
            item(key = "header") {
                Column(
                    Modifier.fillMaxWidth().onSizeChanged { headerHeightPx = it.height }.padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    TelegramAvatar(info.initials, palette.accent, 112.dp, info.photo, observeFile, downloadFile,
                        Modifier.graphicsLayer { val scale = 1f - AVATAR_SHRINK * collapse.value; scaleX = scale; scaleY = scale }
                            .clickable(enabled = info.photo != null, onClick = onAvatarClick))
                    Spacer(Modifier.height(16.dp))
                    Column(Modifier.fillMaxWidth().graphicsLayer { alpha = 1f - collapse.value }, horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(title, color = palette.textPrimary, fontSize = 26.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(4.dp))
                        ProfileSubtitle(info, lastSeenStyle)
                        ProfileBadges(info)
                    }
                }
            }
            item(key = "rows") { ProfileRowsCard(profileRows(context, info, withSharedCounts = sharedMessages == null)) }
            if (info.administrators.isNotEmpty()) item(key = "administrators") { AdministratorsSection(info.administrators, onOpenUser) }
            stickyHeader(key = "tabs") {
                GroupTabRow(
                    tabs = tabs, selected = activeTab,
                    countText = { tab -> if (tab == GroupTab.Members) info.memberCount?.toString() else tab.kind?.let { info.sharedCounts?.countOf(it)?.toString() } },
                    onSelect = { tab ->
                        selectedTab = tab
                        // Если список ушёл вниз по прежней вкладке, возвращаем его к полоске: иначе новая вкладка окажется за своим концом.
                        scope.launch { if (listState.firstVisibleItemIndex >= tabsIndex) listState.scrollToItem(tabsIndex) }
                    }
                )
            }
            val kind = activeTab.kind
            if (kind == null || window == null) item(key = "members") { GroupMembers(info, state.isLoading, observeFile, downloadFile, onMembers, onOpenUser) }
            else sharedItems(kind, info.id, window, observeFile, downloadFile, confirmExport, onContentOpened, onOpenMedia = { viewing = it }, onOpenMessage = onOpenMessage, onRetry = { scope.launch { window.loadOlder() } })
        }
    }
    SharedMediaViewer(media = windows.getValue(SharedMediaKind.Media), viewing = viewing, onViewing = { viewing = it },
        observeFile = observeFile, downloadFile = downloadFile, onOpenMessage = onOpenMessage)
}

/** Панель профиля группы. Название появляется здесь, когда шапка уходит за экран; читается из [collapse] при рисовании. */
@Composable
private fun GroupProfileToolbar(title: String, collapse: State<Float>, refreshEnabled: Boolean, onBack: () -> Unit, onRefresh: () -> Unit) {
    val palette = beyGramPalette()
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.common_back), tint = palette.textPrimary) }
        Text(title, color = palette.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).graphicsLayer { alpha = collapse.value })
        IconButton(onClick = onRefresh, enabled = refreshEnabled) { Icon(Icons.Rounded.Refresh, stringResource(R.string.common_refresh), tint = palette.textSecondary) }
    }
}

/** Полоска вкладок. Закрепляется сверху, когда список прокручен до неё; на узком экране прокручивается по горизонтали. */
@Composable
private fun GroupTabRow(tabs: List<GroupTab>, selected: GroupTab, countText: (GroupTab) -> String?, onSelect: (GroupTab) -> Unit) {
    val palette = beyGramPalette()
    Row(
        Modifier.fillMaxWidth().background(palette.screen).horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        tabs.forEach { tab ->
            val isSelected = tab == selected
            Row(
                Modifier.clip(RoundedCornerShape(percent = 50))
                    .background(if (isSelected) palette.accentSoft else palette.surface2)
                    .clickable { onSelect(tab) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(stringResource(tab.titleRes()), color = if (isSelected) palette.accentInk else palette.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                countText(tab)?.let { Text(it, color = if (isSelected) palette.accentInk else palette.textSecondary, fontSize = 13.sp, maxLines = 1) }
            }
        }
    }
}

/** Участники группы из профиля. Полный список открывается отдельным экраном. */
@Composable
private fun GroupMembers(info: ProfileInfo, isLoading: Boolean, observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, onMembers: () -> Unit, onOpenUser: (Long) -> Unit) {
    val palette = beyGramPalette()
    if (!info.canListMembers) {
        Text(stringResource(R.string.profile_members_hidden), color = palette.textSecondary, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp))
        return
    }
    // Пока превью не пришло, показываем загрузку, а не одну кнопку «Все участники». Пустое превью без загрузки ничего не рисует.
    if (info.memberPreview.isEmpty()) {
        if (isLoading) Box(Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.size(28.dp), color = palette.accent, strokeWidth = 2.dp)
        }
        return
    }
    Column(Modifier.padding(horizontal = 16.dp).clip(RoundedCornerShape(20.dp)).background(palette.surface).padding(vertical = 4.dp)) {
        info.memberPreview.forEachIndexed { index, member ->
            if (index > 0) HorizontalDivider(color = palette.divider, modifier = Modifier.padding(start = 82.dp))
            MemberRow(member, observeFile, downloadFile) { onOpenUser(member.userId) }
        }
        TextButton(onClick = onMembers, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.profile_members_all, info.memberCount ?: info.memberPreview.size), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Вкладка вложений: сетка для «Медиа», строки для остальных. Пустая вкладка показывает загрузку, пустоту или ошибку. */
private fun LazyListScope.sharedItems(
    kind: SharedMediaKind, chatId: Long, window: SharedMediaWindow,
    observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, confirmExport: suspend (Long) -> Boolean,
    onContentOpened: (Long) -> Unit, onOpenMedia: (Long) -> Unit, onOpenMessage: (Long) -> Unit, onRetry: () -> Unit
) {
    // «Ссылки» бывают и в тексте, поэтому им вложение не нужно; остальные вкладки показывают только сообщения с вложением.
    val shown = window.messages.asReversed().filter { kind == SharedMediaKind.Links || it.media != null }
    if (shown.isEmpty()) {
        item(key = "status") {
            Box(Modifier.fillMaxWidth().height(SHARED_STATUS_HEIGHT), contentAlignment = Alignment.Center) { SharedMediaStatus(kind, window, onRetry) }
        }
        return
    }
    if (kind == SharedMediaKind.Media) {
        items(shown.chunked(GRID_COLUMNS), key = { row -> row.first().id }) { row ->
            SharedMediaGridRow(row, observeFile, downloadFile, onOpenMedia, onOpenMessage)
        }
    } else {
        items(shown, key = { it.id }) { message ->
            SharedMediaRowItem(kind, chatId, message, observeFile, downloadFile, confirmExport, onContentOpened, onOpenMessage)
        }
    }
    item(key = "footer") { SharedMediaFooter(window, onRetry) }
}

/** Ряд сетки «Медиа»: до трёх ячеек. Недостающие места заполняются пустыми весами, чтобы ячейки не растягивались. */
@Composable
private fun SharedMediaGridRow(
    row: List<ChatMessage>, observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit,
    onOpenMedia: (Long) -> Unit, onOpenMessage: (Long) -> Unit
) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp, vertical = 1.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        row.forEach { message ->
            message.media?.let { media ->
                SharedMediaCell(media, observeFile, downloadFile, onClick = { if (media.isSecret) onOpenMessage(message.id) else onOpenMedia(message.id) }, modifier = Modifier.weight(1f))
            }
        }
        repeat(GRID_COLUMNS - row.size) { Spacer(Modifier.weight(1f)) }
    }
}

private fun GroupTab.titleRes(): Int = when (this) {
    GroupTab.Members -> R.string.profile_members_tab
    GroupTab.Media -> R.string.profile_shared_media
    GroupTab.Files -> R.string.profile_shared_files
    GroupTab.Links -> R.string.profile_shared_links
    GroupTab.Voice -> R.string.profile_shared_voice
}
