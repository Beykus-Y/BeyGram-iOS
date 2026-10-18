package com.beykus.beygram.ui.screens.profile

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.beykus.beygram.R
import com.beykus.beygram.domain.model.ChatMessage
import com.beykus.beygram.domain.model.MediaFileState
import com.beykus.beygram.domain.model.MediaKind
import com.beykus.beygram.domain.model.MessageMedia
import com.beykus.beygram.domain.model.MessageSearchPage
import com.beykus.beygram.domain.model.SharedCounts
import com.beykus.beygram.domain.model.SharedMediaKind
import com.beykus.beygram.domain.model.TextStyleKind
import com.beykus.beygram.domain.model.validTextEntities
import com.beykus.beygram.playback.PlaybackEngine
import com.beykus.beygram.playback.PlaybackOrigin
import com.beykus.beygram.playback.playbackItem
import com.beykus.beygram.playback.playbackKey
import com.beykus.beygram.ui.components.beyGramPalette
import com.beykus.beygram.ui.screens.chat.LocalMediaImage
import com.beykus.beygram.ui.screens.chat.MediaViewer
import com.beykus.beygram.ui.screens.chat.MediaViewerItem
import com.beykus.beygram.ui.screens.chat.SharedMediaWindow
import com.beykus.beygram.ui.screens.chat.duration
import com.beykus.beygram.ui.screens.chat.formatMediaSize
import com.beykus.beygram.ui.screens.chat.formatSearchDate
import com.beykus.beygram.ui.screens.chat.openExternalMedia
import com.beykus.beygram.ui.screens.chat.safeMessageUrl
import com.beykus.beygram.ui.text.userMessage
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

internal const val GRID_COLUMNS = 3
private const val GRID_PREVIEW_PX = 256
/** Сколько ячеек или строк остаётся до конца вкладки, когда следующая страница уже нужна. */
private const val PREFETCH_CELLS = 12
internal const val PREFETCH_ROWS = 6
private const val PAGER_SCREEN_FRACTION = 0.7f
private val PAGER_MIN_HEIGHT = 360.dp

/**
 * Вкладки «Медиа», «Файлы», «Ссылки» и «Голосовые» под разделами профиля чата. Каждая листается свайпом и грузит страницы по мере прокрутки.
 * Состояние держится в разделе, а не на странице, поэтому загруженное не теряется при свайпе.
 */
@Composable
internal fun SharedMediaSection(
    chatId: Long, counts: SharedCounts?, load: suspend (SharedMediaKind, Long, Boolean) -> Result<MessageSearchPage>,
    observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, confirmExport: suspend (Long) -> Boolean,
    onContentOpened: (Long) -> Unit, onOpenMessage: (Long) -> Unit
) {
    val palette = beyGramPalette()
    val scope = rememberCoroutineScope()
    val tabs = rememberSharedMediaWindows(chatId, load)
    val pagerState = rememberPagerState { SharedMediaKind.entries.size }
    val pagerHeight = (LocalConfiguration.current.screenHeightDp * PAGER_SCREEN_FRACTION).dp.coerceAtLeast(PAGER_MIN_HEIGHT)
    var viewing by remember(chatId) { mutableStateOf<Long?>(null) }
    fun loadMore(kind: SharedMediaKind) {
        scope.launch { tabs.getValue(kind).loadOlder() }
    }

    Text(stringResource(R.string.profile_shared_header), color = palette.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 6.dp))
    SharedMediaTabBar(
        titles = SharedMediaKind.entries.map { stringResource(it.titleRes()) },
        counts = SharedMediaKind.entries.map { counts?.countOf(it)?.toString() },
        selected = pagerState.currentPage,
        onSelect = { index -> scope.launch { pagerState.animateScrollToPage(index) } }
    )
    Spacer(Modifier.height(12.dp))
    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxWidth().height(pagerHeight)) { page ->
        val kind = SharedMediaKind.entries[page]
        SharedMediaPageContent(kind, chatId, tabs.getValue(kind), onMore = { loadMore(kind) }, observeFile = observeFile, downloadFile = downloadFile,
            confirmExport = confirmExport, onContentOpened = onContentOpened,
            onOpenMedia = { messageId -> viewing = messageId }, onOpenMessage = onOpenMessage)
    }

    SharedMediaViewer(media = tabs.getValue(SharedMediaKind.Media), viewing = viewing, onViewing = { viewing = it },
        observeFile = observeFile, downloadFile = downloadFile, onOpenMessage = onOpenMessage)
}

/** Окна вкладок по видам вложений. Новые создаются только при смене чата и переживают пересборку экрана. */
@Composable
internal fun rememberSharedMediaWindows(
    chatId: Long, load: suspend (SharedMediaKind, Long, Boolean) -> Result<MessageSearchPage>
): Map<SharedMediaKind, SharedMediaWindow> {
    val context = LocalContext.current
    val currentLoad by rememberUpdatedState(load)
    return remember(chatId) {
        SharedMediaKind.entries.associateWith { kind ->
            SharedMediaWindow(
                load = { from, newer -> currentLoad(kind, from, newer) },
                failure = { error -> error.userMessage(context, R.string.profile_shared_load_failed) }
            )
        }
    }
}

/** Просмотрщик фото и видео из вкладки «Медиа». Листает загруженное; секретные открываются в чате, где есть все проверки. */
@Composable
internal fun SharedMediaViewer(
    media: SharedMediaWindow, viewing: Long?, onViewing: (Long?) -> Unit,
    observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, onOpenMessage: (Long) -> Unit
) {
    val scope = rememberCoroutineScope()
    val selected = viewing
    val pages = media.messages.mapNotNull { message ->
        message.media?.takeUnless { it.isSecret }?.let { MediaViewerItem(message.id, it) }
    }
    if (selected != null && pages.any { it.messageId == selected }) MediaViewer(
        pages = pages, selectedId = selected,
        onSelect = { id ->
            onViewing(id)
            scope.launch { media.loadNear(id) { it.media?.isSecret == false } }
        },
        observeFile = observeFile, downloadFile = downloadFile, onViewed = {}, onClose = { onViewing(null) },
        // Сохранение и отправка идут через чат: там проверяется, разрешено ли сообщение переслать или сохранить.
        canExport = false, onShowInChat = { messageId -> onViewing(null); onOpenMessage(messageId) }
    )
}

@Composable
private fun SharedMediaTabBar(titles: List<String>, counts: List<String?>, selected: Int, onSelect: (Int) -> Unit) {
    val palette = beyGramPalette()
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        titles.forEachIndexed { index, title ->
            val isSelected = index == selected
            val ink = if (isSelected) palette.accentInk else palette.textSecondary
            Column(
                Modifier.weight(1f).height(52.dp).clip(RoundedCornerShape(16.dp))
                    .background(if (isSelected) palette.accentSoft else palette.surface2)
                    .clickable { onSelect(index) },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(title, color = if (isSelected) palette.accentInk else palette.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                counts[index]?.let { Text(it, color = ink, fontSize = 12.sp, maxLines = 1) }
            }
        }
    }
}

@Composable
private fun SharedMediaPageContent(
    kind: SharedMediaKind, chatId: Long, tab: SharedMediaWindow, onMore: () -> Unit,
    observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, confirmExport: suspend (Long) -> Boolean,
    onContentOpened: (Long) -> Unit, onOpenMedia: (Long) -> Unit, onOpenMessage: (Long) -> Unit
) {
    // Первую страницу грузим, как только вкладку показали; неудачную попытку повторяем при следующем показе.
    LaunchedEffect(kind) { if (!tab.loaded) onMore() }
    when {
        tab.messages.isEmpty() -> SharedMediaStatus(kind, tab, onRetry = onMore)
        kind == SharedMediaKind.Media -> SharedMediaGrid(tab, onMore, observeFile, downloadFile, onOpenMedia, onOpenMessage)
        else -> SharedMediaList(kind, chatId, tab, onMore, observeFile, downloadFile, confirmExport, onContentOpened, onOpenMessage)
    }
}

@Composable
internal fun SharedMediaStatus(kind: SharedMediaKind, tab: SharedMediaWindow, onRetry: () -> Unit) {
    val palette = beyGramPalette()
    val error = tab.error
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        when {
            error != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(error, color = palette.danger, fontSize = 14.sp, textAlign = TextAlign.Center)
                TextButton(onClick = onRetry) { Text(stringResource(R.string.common_retry)) }
            }
            // Пусто только тогда, когда дальше грузить нечего: страница без нужных вложений ещё не значит пустую вкладку.
            tab.loaded && !tab.hasOlder -> Text(stringResource(kind.emptyRes()), color = palette.textSecondary, fontSize = 14.sp, textAlign = TextAlign.Center)
            else -> CircularProgressIndicator(Modifier.size(28.dp), color = palette.accent, strokeWidth = 2.dp)
        }
    }
}

@Composable
internal fun SharedMediaFooter(tab: SharedMediaWindow, onRetry: () -> Unit) {
    val palette = beyGramPalette()
    val error = tab.error
    if (!tab.loading && error == null) return
    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        if (error != null) {
            Text(error, color = palette.danger, fontSize = 14.sp, textAlign = TextAlign.Center)
            TextButton(onClick = onRetry) { Text(stringResource(R.string.common_retry)) }
        } else CircularProgressIndicator(Modifier.size(24.dp), color = palette.accent, strokeWidth = 2.dp)
    }
}

@Composable
private fun SharedMediaGrid(
    tab: SharedMediaWindow, onMore: () -> Unit, observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit,
    onOpenMedia: (Long) -> Unit, onOpenMessage: (Long) -> Unit
) {
    val gridState = rememberLazyGridState()
    val nearEnd by remember(tab) { derivedStateOf { gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.let { it.index >= tab.messages.size - PREFETCH_CELLS } ?: true } }
    LaunchedEffect(nearEnd, tab.messages.size, tab.hasOlder) { if (nearEnd && tab.hasOlder) onMore() }
    LazyVerticalGrid(
        columns = GridCells.Fixed(GRID_COLUMNS), state = gridState, modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(2.dp), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        items(tab.messages.asReversed(), key = { it.id }) { message ->
            message.media?.let { media ->
                SharedMediaCell(media, observeFile, downloadFile, onClick = { if (media.isSecret) onOpenMessage(message.id) else onOpenMedia(message.id) })
            }
        }
        item(span = { GridItemSpan(maxLineSpan) }) { SharedMediaFooter(tab, onRetry = onMore) }
    }
}

@Composable
private fun SharedMediaList(
    kind: SharedMediaKind, chatId: Long, tab: SharedMediaWindow, onMore: () -> Unit,
    observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, confirmExport: suspend (Long) -> Boolean,
    onContentOpened: (Long) -> Unit, onOpenMessage: (Long) -> Unit
) {
    val listState = rememberLazyListState()
    val nearEnd by remember(tab) { derivedStateOf { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.let { it.index >= tab.messages.size - PREFETCH_ROWS } ?: true } }
    LaunchedEffect(nearEnd, tab.messages.size, tab.hasOlder) { if (nearEnd && tab.hasOlder) onMore() }
    LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(vertical = 4.dp)) {
        items(tab.messages.asReversed(), key = { it.id }) { message ->
            SharedMediaRowItem(kind, chatId, message, observeFile, downloadFile, confirmExport, onContentOpened, onOpenMessage)
        }
        item(key = "footer") { SharedMediaFooter(tab, onRetry = onMore) }
    }
}

/** Строка списка. Ссылка может быть обычным текстом, поэтому для вкладки «Ссылки» вложение не нужно. */
@Composable
internal fun SharedMediaRowItem(
    kind: SharedMediaKind, chatId: Long, message: ChatMessage, observeFile: (Int) -> StateFlow<MediaFileState>,
    downloadFile: (Int) -> Unit, confirmExport: suspend (Long) -> Boolean, onContentOpened: (Long) -> Unit,
    onOpenMessage: (Long) -> Unit
) {
    val you = stringResource(R.string.search_you)
    val meta = listOf(if (message.isOutgoing) you else message.senderName, formatSearchDate(message.dateSeconds)).filter { it.isNotBlank() }.joinToString(" · ")
    when (kind) {
        SharedMediaKind.Files -> message.media?.let { SharedFileRow(message, it, meta, observeFile, downloadFile, confirmExport, onContentOpened, onOpenMessage) }
        SharedMediaKind.Links -> SharedLinkRow(message, meta, onOpenMessage)
        SharedMediaKind.Voice -> message.media?.let { SharedVoiceRow(chatId, message, it, meta, observeFile, downloadFile, onContentOpened, onOpenMessage) }
        SharedMediaKind.Media -> Unit
    }
}

@Composable
private fun SharedFileRow(
    message: ChatMessage, media: MessageMedia, meta: String, observeFile: (Int) -> StateFlow<MediaFileState>,
    downloadFile: (Int) -> Unit, confirmExport: suspend (Long) -> Boolean, onContentOpened: (Long) -> Unit,
    onOpenMessage: (Long) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val file by remember(media.fileId) { observeFile(media.fileId) }.collectAsStateWithLifecycle()
    val title = media.fileName.ifBlank { stringResource(R.string.media_kind_file) }
    SharedRow(
        Icons.Rounded.InsertDriveFile, title, listOf(formatMediaSize(file.size), meta).filter { it.isNotBlank() }.joinToString(" · "),
        onClick = {
            when (val action = sharedRowAction(media, file.localPath)) {
                SharedRowAction.ShowInChat -> onOpenMessage(message.id)
                SharedRowAction.Download -> downloadFile(media.fileId)
                // Открыть в другом приложении значит передать файл наружу, поэтому право на сообщение проверяем при каждом открытии.
                is SharedRowAction.Open -> scope.launch {
                    val error = if (confirmExport(message.id)) openExternalMedia(context, action.path, media.mimeType) else context.getString(R.string.media_export_denied)
                    // Открытый файл отмечается просмотренным, как в просмотрщике чата; отказ показываем сообщением.
                    if (error == null) onContentOpened(message.id) else Toast.makeText(context, error, Toast.LENGTH_SHORT).show()
                }
            }
        },
        onShowInChat = { onOpenMessage(message.id) }
    )
}

/** Голосовое играет на месте в общем плеере; сообщение передаём, чтобы мини-плеер мог открыть его в чате. */
@Composable
private fun SharedVoiceRow(
    chatId: Long, message: ChatMessage, media: MessageMedia, meta: String, observeFile: (Int) -> StateFlow<MediaFileState>,
    downloadFile: (Int) -> Unit, onContentOpened: (Long) -> Unit, onOpenMessage: (Long) -> Unit
) {
    val context = LocalContext.current
    val file by remember(media.fileId) { observeFile(media.fileId) }.collectAsStateWithLifecycle()
    val label = stringResource(R.string.media_kind_voice)
    SharedRow(
        Icons.Rounded.Mic, label + " · " + duration(media.durationSeconds), meta,
        onClick = {
            when (val action = sharedRowAction(media, file.localPath)) {
                SharedRowAction.ShowInChat -> onOpenMessage(message.id)
                SharedRowAction.Download -> downloadFile(media.fileId)
                is SharedRowAction.Open -> {
                    val state = PlaybackEngine.state.value
                    // Голосовое отмечаем прослушанным, когда плеер сообщит о старте, как в пузыре чата. Пауза не отмечает.
                    val pausing = state.item?.key == media.playbackKey() && state.playing
                    val onStarted = if (pausing) null else ({ onContentOpened(message.id) })
                    PlaybackEngine.toggle(context, media.playbackItem(action.path, label, PlaybackOrigin(chatId, message.id)), onStarted)
                }
            }
        },
        onShowInChat = { onOpenMessage(message.id) }
    )
}

/** Ссылка открывается с той же проверкой адреса, что и в тексте сообщения. */
@Composable
private fun SharedLinkRow(message: ChatMessage, meta: String, onOpenMessage: (Long) -> Unit) {
    val uri = LocalUriHandler.current
    val context = LocalContext.current
    val link = sharedLinkTitle(message)
    val underSpoiler = sharedLinkUnderSpoiler(message)
    SharedRow(
        Icons.Rounded.Link, link, meta,
        onClick = {
            // Ссылку под спойлером открываем только в чате: там она появляется после нажатия, как в тексте сообщения.
            if (underSpoiler) onOpenMessage(message.id) else {
                val safe = safeMessageUrl(link)
                if (safe == null || runCatching { uri.openUri(safe) }.isFailure) Toast.makeText(context, R.string.chat_link_failed, Toast.LENGTH_SHORT).show()
            }
        },
        onShowInChat = { onOpenMessage(message.id) }
    )
}

@Composable
private fun SharedRow(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit, onShowInChat: () -> Unit) {
    val palette = beyGramPalette()
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = palette.accentInk, modifier = Modifier.size(44.dp).background(palette.accentSoft, CircleShape).padding(11.dp))
        Column(Modifier.weight(1f).padding(start = 14.dp)) {
            Text(title, color = palette.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle.isNotBlank()) Text(subtitle, color = palette.textSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        TextButton(onClick = onShowInChat) { Text(stringResource(R.string.media_show_in_chat), fontSize = 13.sp, maxLines = 1) }
    }
}

/**
 * Превью грузим, только когда спойлер открыт: до этого файл на устройство не скачивается.
 * Секретные вложения и видео без миниатюры превью не имеют.
 */
internal fun shouldLoadSharedPreview(media: MessageMedia, revealed: Boolean): Boolean =
    revealed && !media.isSecret && (media.thumbnailFileId != null || media.kind == MediaKind.Photo)

/** Что делает нажатие на вложение в списке: секретное открываем в чате, ещё не скачанное сначала скачиваем, скачанное открываем. */
internal sealed class SharedRowAction {
    object ShowInChat : SharedRowAction()
    object Download : SharedRowAction()
    data class Open(val path: String) : SharedRowAction()
}

internal fun sharedRowAction(media: MessageMedia, localPath: String?): SharedRowAction = when {
    media.isSecret -> SharedRowAction.ShowInChat
    localPath == null -> SharedRowAction.Download
    else -> SharedRowAction.Open(localPath)
}

/**
 * Превью в сетке. Спойлер: первое нажатие открывает превью, второе открывает вложение, как в ленте чата.
 * Видео без превью не грузим: TDLib отдал бы весь файл, а картинки нет. Секретные вложения не грузим и не показываем.
 */
@Composable
internal fun SharedMediaCell(media: MessageMedia, observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val palette = beyGramPalette()
    val thumbId = media.thumbnailFileId ?: media.fileId
    val thumb by remember(thumbId) { observeFile(thumbId) }.collectAsStateWithLifecycle()
    // У секретного вложения превью не показываем, поэтому спойлер ему не нужен: сразу открываем.
    var revealed by remember(media.fileId) { mutableStateOf(!media.hasSpoiler || media.isSecret) }
    val loadPreview = shouldLoadSharedPreview(media, revealed)
    LaunchedEffect(thumbId, loadPreview) { if (loadPreview) downloadFile(thumbId) }
    Box(
        modifier.aspectRatio(1f).clip(RoundedCornerShape(4.dp)).background(palette.disabled)
            .clickable(onClick = { if (!revealed) revealed = true else onClick() }),
        contentAlignment = Alignment.Center
    ) {
        val path = thumb.localPath
        if (loadPreview && path != null) LocalMediaImage(path, Modifier.fillMaxSize(), maxDimension = GRID_PREVIEW_PX)
        if (!revealed) Text(stringResource(R.string.profile_shared_spoiler), color = palette.textSecondary, fontSize = 11.sp,
            textAlign = TextAlign.Center, modifier = Modifier.padding(4.dp))
        if (media.isSecret) Icon(Icons.Rounded.Lock, null, tint = palette.textSecondary, modifier = Modifier.size(22.dp))
        if (revealed && media.kind == MediaKind.Video && media.durationSeconds > 0) Text(
            duration(media.durationSeconds), color = Color.White, fontSize = 11.sp,
            modifier = Modifier.align(Alignment.BottomStart).padding(4.dp).background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp)
        )
    }
}

/** Адрес для строки вкладки «Ссылки»: адрес, спрятанный под текстом, или сам текст ссылки. Без ссылки показываем текст сообщения. */
internal fun sharedLinkTitle(message: ChatMessage): String {
    val link = validTextEntities(message.text, message.entities).firstOrNull { it.kind == TextStyleKind.Url }
        ?: return message.text.trim()
    return link.argument.ifEmpty { message.text.substring(link.offset, link.offset + link.length) }
}

/** Ссылка, которую скрывает спойлер: в тексте сообщения такая ссылка открывается только после нажатия на спойлер. */
internal fun sharedLinkUnderSpoiler(message: ChatMessage): Boolean {
    val entities = validTextEntities(message.text, message.entities)
    val link = entities.firstOrNull { it.kind == TextStyleKind.Url } ?: return false
    return entities.any { it.kind == TextStyleKind.Spoiler && it.offset < link.offset + link.length && link.offset < it.offset + it.length }
}

private fun SharedMediaKind.titleRes(): Int = when (this) {
    SharedMediaKind.Media -> R.string.profile_shared_media
    SharedMediaKind.Files -> R.string.profile_shared_files
    SharedMediaKind.Links -> R.string.profile_shared_links
    SharedMediaKind.Voice -> R.string.profile_shared_voice
}

private fun SharedMediaKind.emptyRes(): Int = when (this) {
    SharedMediaKind.Media -> R.string.profile_shared_empty_media
    SharedMediaKind.Files -> R.string.profile_shared_empty_files
    SharedMediaKind.Links -> R.string.profile_shared_empty_links
    SharedMediaKind.Voice -> R.string.profile_shared_empty_voice
}

internal fun SharedCounts.countOf(kind: SharedMediaKind): Int? = when (kind) {
    SharedMediaKind.Media -> media
    SharedMediaKind.Files -> files
    SharedMediaKind.Links -> links
    SharedMediaKind.Voice -> voice
}
