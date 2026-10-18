package com.beykus.beygram.ui.screens.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Done
import androidx.compose.material.icons.rounded.DoneAll
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.beykus.beygram.R
import com.beykus.beygram.domain.model.*
import com.beykus.beygram.domain.repository.ConversationRepository
import com.beykus.beygram.data.media.VideoMessageSettingsStore
import com.beykus.beygram.data.media.ComposerRecordingMode
import com.beykus.beygram.data.presence.LastSeenStyle
import com.beykus.beygram.playback.PlaybackEngine
import com.beykus.beygram.playback.PlaybackOrigin
import com.beykus.beygram.ui.components.TelegramAvatar
import com.beykus.beygram.ui.components.beyGramPalette
import com.beykus.beygram.ui.screens.playback.NowPlayingBar
import com.beykus.beygram.ui.components.beyGramFilledTextFieldColors
import com.beykus.beygram.ui.components.beyGramTextFieldColors
import com.beykus.beygram.ui.text.resolve
import com.beykus.beygram.ui.text.userMessage
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

@OptIn(FlowPreview::class)
@Composable
fun ChatScreen(
    chat: ChatPreview, info: ProfileInfo?, lastSeenStyle: LastSeenStyle, history: ChatHistory, conversation: ConversationRepository, chats: List<ChatPreview>,
    observeFile: (Int) -> StateFlow<MediaFileState>, onDownloadFile: (Int) -> Unit,
    onBack: () -> Unit, onChatInfo: () -> Unit, connectionState: TelegramConnectionState,
    recordingSettings: VideoMessageSettingsStore, focusMessageId: Long = 0L, onFocusHandled: () -> Unit = {}
) {
    var draft by rememberSaveable(chat.id) { mutableStateOf("") }
    var draftEntities by rememberSaveable(chat.id) { mutableStateOf(arrayListOf<MessageTextEntity>()) }
    var editEntities by remember(chat.id) { mutableStateOf<List<MessageTextEntity>>(emptyList()) }
    val botKeyboard by remember(conversation, chat.id) { conversation.observeBotKeyboard(chat.id) }.collectAsStateWithLifecycle()
    var replyId by rememberSaveable(chat.id) { mutableStateOf<Long?>(null) }
    // Bumped whenever a reply starts, so the composer takes focus and the keyboard opens.
    var replyFocusRequest by remember(chat.id) { mutableIntStateOf(0) }
    // The message of the latest swipe; a slower capability check for an older swipe is ignored.
    var swipedReplyId by remember(chat.id) { mutableLongStateOf(0L) }
    var actionsId by rememberSaveable(chat.id) { mutableStateOf<Long?>(null) }
    var editId by rememberSaveable(chat.id) { mutableStateOf<Long?>(null) }
    var editText by rememberSaveable(chat.id) { mutableStateOf("") }
    var editBusy by remember { mutableStateOf(false) }
    var editError by remember { mutableStateOf<String?>(null) }
    var deleting by rememberSaveable(chat.id) { mutableStateOf(false) }
    var deleteEveryone by remember { mutableStateOf(false) }
    var deleteBusy by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }
    var capabilities by remember { mutableStateOf<MessageCapabilities?>(null) }
    var capabilitiesError by remember { mutableStateOf<String?>(null) }
    var capabilitiesAttempt by remember { mutableIntStateOf(0) }
    var selectedMediaId by rememberSaveable(chat.id) { mutableStateOf<Long?>(null) }
    var viewerRights by remember { mutableStateOf<MessageRights?>(null) }
    var viewerPosition by remember { mutableStateOf<MediaPosition?>(null) }
    var forwardId by rememberSaveable(chat.id) { mutableStateOf<Long?>(null) }
    var forwardBusy by remember { mutableStateOf(false) }
    var forwardError by remember { mutableStateOf<String?>(null) }
    var contextChatId by rememberSaveable(chat.id) { mutableStateOf(0L) }
    var contextMessageId by rememberSaveable(chat.id) { mutableStateOf<Long?>(null) }
    var highlighted by remember { mutableStateOf<Long?>(null) }
    // A message outside the loaded history is scrolled to once the window around it reaches the list.
    var pendingJumpId by remember(chat.id) { mutableStateOf<Long?>(null) }
    var searching by rememberSaveable(chat.id) { mutableStateOf(false) }
    var searchQuery by rememberSaveable(chat.id) { mutableStateOf("") }
    var searchResults by remember(chat.id) { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var searchNextId by remember(chat.id) { mutableLongStateOf(0L) }
    var searchBusy by remember(chat.id) { mutableStateOf(false) }
    var searchError by remember(chat.id) { mutableStateOf<String?>(null) }
    fun closeSearch() { searching = false; searchQuery = "" }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var reactionOptions by remember(chat.id) { mutableStateOf<List<ReactionOption>>(emptyList()) }
    val limits by conversation.messageLimits.collectAsStateWithLifecycle()
    val typingFlow = remember(conversation, chat.id) { conversation.observeTyping(chat.id) }
    val typingNames by typingFlow.collectAsStateWithLifecycle()
    val palette = beyGramPalette()
    val scrollPosition: ChatScrollPositionViewModel = viewModel(key = "chat-scroll-${chat.id}")
    val listState = rememberLazyListState(scrollPosition.firstVisibleItemIndex, scrollPosition.firstVisibleItemScrollOffset)
    DisposableEffect(listState) {
        onDispose {
            scrollPosition.firstVisibleItemIndex = listState.firstVisibleItemIndex
            scrollPosition.firstVisibleItemScrollOffset = listState.firstVisibleItemScrollOffset
        }
    }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val clipboard = LocalContext.current.getSystemService(ClipboardManager::class.java)
    val recordingMode by recordingSettings.recordingMode.collectAsStateWithLifecycle()
    val recordingRecovery: ChatRecordingRecoveryViewModel = viewModel(key = "chat-recording-${chat.id}")
    val recordingPreview by recordingRecovery.preview.collectAsStateWithLifecycle()
    val recordingPreviewIndex by recordingRecovery.selectedIndex.collectAsStateWithLifecycle()
    var sentRecordingPaths by remember(chat.id) { mutableStateOf(emptySet<String>()) }
    var recordingQueueSending by remember(chat.id) { mutableStateOf(false) }
    var recordingQueueProgress by remember(chat.id) { mutableIntStateOf(0) }
    // Voice messages use this local queue; video notes are owned by VideoNoteExportCenter.
    val pendingRecordingSends = remember(chat.id) { ArrayDeque<List<OutgoingMedia>>() }
    val videoExports by VideoNoteExportCenter.results.collectAsStateWithLifecycle()
    val videoPreview = videoExports.firstOrNull { it.chatId == chat.id && it.requiresPreview }
    val videoPending by VideoNoteExportCenter.pendingNotes.collectAsStateWithLifecycle()
    // Автоматический кружок виден в ленте сразу: сначала обработка, потом отправка, пока TDLib не примет сообщение.
    val pendingVideoNotes = remember(videoPending, videoExports, chat.id) { pendingVideoNotesFor(chat.id, videoPending, videoExports) }
    fun startRecordingSendWorker() {
        if (recordingQueueSending) return
        if (pendingRecordingSends.isEmpty()) return
        recordingQueueSending = true
        // Worker живёт в scope восстановления записи: переживает recomposition и не бросает очередь на полпути.
        recordingRecovery.processingScope.launch {
            try {
                while (pendingRecordingSends.isNotEmpty()) {
                    val mediaList = pendingRecordingSends.removeFirst()
                    mediaList.forEachIndexed { index, media ->
                        if (media.path in sentRecordingPaths) return@forEachIndexed
                        recordingQueueProgress = index + 1
                        val result = conversation.sendMedia(chat.id, media, "", replyId)
                        if (result.isSuccess) {
                            sentRecordingPaths = sentRecordingPaths + media.path
                            replyId = null
                        } else {
                            recordingRecovery.showPreview(mediaList, index)
                            error = result.exceptionOrNull().userMessage(context, R.string.chat_video_note_send_failed)
                            pendingRecordingSends.clear()
                            return@launch
                        }
                    }
                }
                sentRecordingPaths = emptySet()
                recordingRecovery.dismissPreview()
            } finally {
                recordingQueueSending = false
            }
        }
    }
    /** Ставит запись в отправку. Пропусков нет: занятый worker сам подхватит очередь. */
    fun sendRecordedMedia(mediaList: List<OutgoingMedia>) {
        pendingRecordingSends.addLast(mediaList)
        startRecordingSendWorker()
    }
    /** Typing is shown from each keystroke; clearing the field ends it. */
    fun typedDraft(text: String) {
        draft = text
        if (text.isBlank()) conversation.endChatActivity(chat.id, ChatActivity.Typing)
        else conversation.startChatActivity(chat.id, ChatActivity.Typing)
    }
    fun setReaction(messageId: Long, reaction: ReactionOption, addToRecent: Boolean) {
        scope.launch {
            conversation.toggleReaction(chat.id, messageId, reaction, addToRecent).onFailure { error = it.userMessage(context, R.string.chat_reaction_failed) }
        }
    }
    // Chip taps leave the user's recent reactions alone; only a reaction picked from the extended menu is added there.
    fun react(messageId: Long, reaction: ReactionOption) = setReaction(messageId, reaction, addToRecent = false)
    fun retryFailedMessages(messageIds: List<Long>) {
        scope.launch {
            val result = conversation.retryMessages(chat.id, messageIds)
            result.exceptionOrNull()?.let { error = it.message ?: context.getString(R.string.chat_retry_send_failed) }
        }
    }
    fun capturedRecording(media: OutgoingMedia, previewFirst: Boolean) {
        if (previewFirst) recordingRecovery.showPreview(listOf(media))
        else sendRecordedMedia(listOf(media))
    }
    val attachments = rememberAttachmentState(chat.id) { media, caption ->
        val result = if (media.size > 1) conversation.sendMediaAlbum(chat.id, media, caption, replyId, draftEntities)
        else conversation.sendMedia(chat.id, media.single(), caption, replyId, draftEntities)
        if (result.isSuccess) replyId = null
        result
    }
    val videoNote = rememberVideoNoteRecorder(recordingSettings, recordingRecovery.processingScope, chat.id, onError = { error = it })
    // Video delivery, including TDLib send retries, belongs to the app-wide center.
    // Only automatic notes are claimed here; preview and failed notes remain visible.
    LaunchedEffect(chat.id, conversation) {
        launch {
            VideoNoteExportCenter.results.collect { list ->
                list.filter { it.chatId == chat.id && !it.requiresPreview && !it.sending }.forEach { item ->
                    val accepted = VideoNoteExportCenter.send(item.chatId, item.sessionName, replyId) { media, targetReply ->
                        conversation.sendMedia(item.chatId, media, "", targetReply).map { Unit }
                    }
                    if (accepted) replyId = null
                }
            }
        }
        launch {
            VideoNoteExportCenter.failures.collect {
                if (VideoNoteExportCenter.consumeFailure(chat.id)) error = context.getString(R.string.recorder_save_failed)
            }
        }
    }
    val audioNote = rememberAudioNoteRecorder(::capturedRecording) { error = it }
    // The other members see a recording while it runs; the recorder's own state ends it.
    DisposableEffect(chat.id, audioNote.active) {
        val chatId = chat.id
        val recording = audioNote.active
        if (recording) conversation.startChatActivity(chatId, ChatActivity.RecordingVoice)
        onDispose { if (recording) conversation.endChatActivity(chatId, ChatActivity.RecordingVoice) }
    }
    DisposableEffect(chat.id, videoNote.active) {
        val chatId = chat.id
        val recording = videoNote.active
        if (recording) conversation.startChatActivity(chatId, ChatActivity.RecordingVideoNote)
        onDispose { if (recording) conversation.endChatActivity(chatId, ChatActivity.RecordingVideoNote) }
    }
    val videoPermissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        if (!granted.values.all { it }) error = context.getString(R.string.chat_video_note_permission_denied)
    }
    val audioPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) Toast.makeText(context, context.getString(R.string.voice_recorder_permission_granted_retry), Toast.LENGTH_SHORT).show()
        else error = context.getString(R.string.voice_recorder_permission_denied)
    }
    fun startRecording() {
        if (videoNote.active || audioNote.active) return
        // Микрофон записывает и звук из общего плеера, поэтому музыку ставим на паузу, когда запись начинается.
        if (recordingMode == ComposerRecordingMode.Voice) {
            if (androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                PlaybackEngine.pause()
                audioNote.press()
            } else audioPermission.launch(android.Manifest.permission.RECORD_AUDIO)
        } else if (!VIDEO_NOTE_RECORDING_ENABLED) {
            error = context.getString(R.string.recorder_video_note_unavailable)
        } else if (videoNoteAllowed(context)) {
            PlaybackEngine.pause()
            videoNote.press()
        } else videoPermissions.launch(videoNotePermissions)
    }
    val messages = history.messages
    // Кружки в обработке стоят в списке первыми (внизу ленты), чтобы индексы прокрутки и дат учитывали их тоже.
    val messageListItems = remember(messages, pendingVideoNotes) {
        pendingVideoNotes.map { ChatMessageListItem("pending-video:${it.sessionName}", emptyList(), pendingVideoNote = it) } + groupTelegramMediaAlbums(messages)
    }
    val messageItemsByKey = remember(messageListItems) { messageListItems.associateBy { it.key } }
    val currentMessageItemsByKey by rememberUpdatedState(messageItemsByKey)
    val currentMessages by rememberUpdatedState(messages)
    val newest = messages.lastOrNull()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    // Запись кружка и голосового в фоне отменяется. Воспроизведение идёт через общий плеер и продолжается вне ленты.
    DisposableEffect(lifecycle) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                videoNote.stopForRecovery()
                audioNote.stopForRecovery()
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val window = LocalWindowInfo.current
    val minimumVisible = with(LocalDensity.current) { 64.dp.roundToPx() }
    val actionMessage = messages.firstOrNull { it.id == actionsId }
    // An album's reactions sit on one of its messages, so the picker and the chips act on that message.
    val reactionOwner = actionMessage?.let { target -> messageListItems.firstOrNull { item -> item.messages.any { it.id == target.id } }?.messages?.let(::reactionMessage) }
    val editMessage = messages.firstOrNull { it.id == editId }
    // A swipe reply needs an idle composer on screen: no search, deletion, edit, recording or open action menu, and no
    // send in flight, because a finished send clears the reply target it used.
    val swipeReplyAllowed = !searching && !deleting && editMessage == null && actionMessage == null && !videoNote.active && !audioNote.active &&
        !sending && !attachments.sending && !recordingQueueSending && pendingVideoNotes.isEmpty()
    LaunchedEffect(editId) { editEntities = editMessage?.entities.orEmpty() }
    LaunchedEffect(botKeyboard?.messageId) { if (botKeyboard?.forceReply == true) replyId = botKeyboard?.messageId }
    val editLimit = if (editMessage?.media == null) limits.text else limits.caption
    fun closeActions() { actionsId = null; deleting = false; deleteError = null; capabilities = null; capabilitiesError = null }
    fun closeEdit() { editId = null; editText = ""; editError = null }
    LaunchedEffect(actionMessage) {
        if (actionMessage == null) { deleting = false; deleteError = null; capabilities = null; capabilitiesError = null }
    }
    LaunchedEffect(actionsId, capabilitiesAttempt) {
        val id = actionsId ?: return@LaunchedEffect
        capabilities = null; capabilitiesError = null
        val result = conversation.messageCapabilities(chat.id, id)
        capabilities = result.getOrNull()
        capabilitiesError = result.exceptionOrNull()?.userMessage(context, R.string.err_chat_actions_load_failed)
    }
    LaunchedEffect(chat.id, reactionOwner?.id) {
        reactionOptions = emptyList()
        val id = reactionOwner?.id ?: return@LaunchedEffect
        reactionOptions = conversation.availableReactions(chat.id, id).getOrNull().orEmpty()
    }
    // Фото и видео листаются по всему чату: окно грузится вокруг открытого вложения, а не только по загруженной истории.
    val mediaWindow = remember(chat.id) {
        SharedMediaWindow(
            load = { from, newer -> conversation.sharedMessages(chat.id, SharedMediaKind.Media, from, newer) },
            failure = { it.userMessage(context, R.string.err_chat_history_load_failed) }
        )
    }
    LaunchedEffect(selectedMediaId) {
        val id = selectedMediaId ?: return@LaunchedEffect
        val kind = currentMessages.firstOrNull { it.id == id }?.media?.kind
        // Вложение, которое уже в окне, не перезагружаем: так просмотрщик возвращается к нему на том же месте.
        if (kind != null && kind in viewerSwipeKinds && mediaWindow.messages.none { it.id == id }) {
            mediaWindow.restart(id)
            mediaWindow.loadOlder()
        }
        // Новее догружаем от края: открытое вложение обычно стоит у правого края окна, а прерванная загрузка не оставляет дыр.
        mediaWindow.loadNear(id)
    }
    LaunchedEffect(selectedMediaId) {
        // Счётчик при свайпе держит прежнее значение до ответа, чтобы не мигал. Права так не держим: см. MediaViewerPolicy.rightsFor.
        if (selectedMediaId == null) { viewerRights = null; viewerPosition = null }
        val id = selectedMediaId ?: return@LaunchedEffect
        viewerRights = conversation.messageCapabilities(chat.id, id).getOrNull()?.let { MessageRights(id, it) }
        val kind = (currentMessages.firstOrNull { it.id == id } ?: mediaWindow.messages.firstOrNull { it.id == id })?.media?.kind
        viewerPosition = kind?.let { conversation.mediaPosition(chat.id, id, it).getOrNull() }
    }
    BackHandler(enabled = searching || actionMessage != null || editMessage != null || attachments.menuOpen || attachments.active) {
        when {
            searching -> closeSearch()
            deleting -> { deleting = false; deleteError = null }
            actionMessage != null -> closeActions()
            editMessage != null -> closeEdit()
            else -> attachments.discardAll()
        }
    }
    BackHandler(enabled = actionMessage == null && editMessage == null && !attachments.menuOpen && !attachments.active && !searching, onBack = onBack)
    BackHandler(enabled = videoNote.active || audioNote.active) {
        videoNote.stopForRecovery()
        audioNote.stopForRecovery()
    }

    // Loading/caching messages never triggers receipts; only the focused, resumed viewport does.
    LaunchedEffect(chat.id, lifecycle, conversation) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            snapshotFlow {
                if (!window.isWindowFocused || searching) emptyList() else {
                    val layout = listState.layoutInfo
                    val eligible = currentMessages.filter { it.sendState == MessageSendState.Sent }.mapTo(hashSetOf()) { it.id }
                    layout.visibleItemsInfo.filter { item ->
                        val visible = minOf(item.offset + item.size, layout.viewportEndOffset) - maxOf(item.offset, layout.viewportStartOffset)
                        visible >= minOf(item.size / 2, minimumVisible).coerceAtLeast(1)
                    }.flatMap { visibleItem ->
                        currentMessageItemsByKey[visibleItem.key as? String]?.messages.orEmpty().map { it.id }
                    }.filter { it in eligible }.distinct().sorted()
                }
            }.debounce(350).distinctUntilChanged().collect { ids -> if (ids.isNotEmpty()) conversation.messagesVisible(chat.id, ids) }
        }
    }
    // Появление кружка в ленте прокручивает к низу, как и исходящее сообщение.
    LaunchedEffect(pendingVideoNotes.firstOrNull()?.sessionName) {
        if (pendingVideoNotes.isNotEmpty()) listState.animateScrollToItem(0)
    }
    LaunchedEffect(chat.id, newest?.id) {
        if (!history.hasNewerMessages && messages.isNotEmpty() && (listState.firstVisibleItemIndex < 2 || newest?.isOutgoing == true)) listState.animateScrollToItem(0)
    }
    LaunchedEffect(pendingJumpId, messageListItems) {
        val target = pendingJumpId ?: return@LaunchedEffect
        val index = messageListItems.indexOfFirst { item -> item.messages.any { it.id == target } }
        if (index < 0) return@LaunchedEffect
        listState.animateScrollToItem(index)
        highlighted = target
        // Cleared last: changing the key earlier would cancel the scroll that is still running.
        pendingJumpId = null
    }
    LaunchedEffect(highlighted) { if (highlighted != null) { delay(2200); highlighted = null } }
    fun jump(reply: MessageReply) {
        if (reply.isUnavailable || reply.messageId <= 0) { error = context.getString(R.string.chat_reply_original_unavailable); return }
        val index = messageListItems.indexOfFirst { item -> item.messages.any { it.id == reply.messageId && it.chatId == reply.chatId } }
        if (index >= 0) scope.launch { listState.animateScrollToItem(index); highlighted = reply.messageId }
        else { contextChatId = reply.chatId; contextMessageId = reply.messageId }
    }
    // The reply is checked on the server first: a channel, or a chat without reply rights, must not enter reply mode.
    // Only the latest swipe may apply its answer, so a slower check cannot reopen the composer for an older message.
    fun swipeReply(messageId: Long) {
        swipedReplyId = messageId
        scope.launch {
            val result = conversation.messageCapabilities(chat.id, messageId)
            if (swipedReplyId != messageId) return@launch
            result
                .onSuccess {
                    if (it.canReply) {
                        replyId = messageId
                        replyFocusRequest++
                    } else {
                        error = context.getString(R.string.err_message_cannot_reply)
                    }
                }
                .onFailure { error = it.userMessage(context, R.string.err_chat_actions_load_failed) }
        }
    }
    // Results refresh after a short pause in typing; a new query replaces the pending request.
    LaunchedEffect(searching, searchQuery) {
        searchResults = emptyList(); searchNextId = 0L; searchError = null
        val needle = searchQuery.trim()
        searchBusy = searching && needle.isNotEmpty()
        if (!searching || needle.isEmpty()) return@LaunchedEffect
        delay(300)
        conversation.searchMessages(chat.id, needle, 0L)
            .onSuccess { page -> searchResults = page.messages; searchNextId = page.nextFromMessageId }
            .onFailure { searchError = it.userMessage(context, R.string.chat_search_failed) }
        searchBusy = false
    }
    fun loadMoreResults() {
        val needle = searchQuery.trim()
        scope.launch {
            searchBusy = true
            conversation.searchMessages(chat.id, needle, searchNextId)
                .onSuccess { page -> if (searchQuery.trim() == needle) { searchResults = searchResults + page.messages; searchNextId = page.nextFromMessageId } }
                .onFailure { if (searchQuery.trim() == needle) { searchError = it.userMessage(context, R.string.chat_search_failed) } }
            if (searchQuery.trim() == needle) { searchBusy = false }
        }
    }
    fun openSearchResult(message: ChatMessage) {
        val index = messageListItems.indexOfFirst { item -> item.messages.any { it.id == message.id } }
        closeSearch()
        if (index >= 0) scope.launch { listState.animateScrollToItem(index); highlighted = message.id }
        else { contextChatId = chat.id; contextMessageId = message.id }
    }
    fun jumpToMessage(messageId: Long, failure: Int) {
        val index = messageListItems.indexOfFirst { item -> item.messages.any { it.id == messageId } }
        if (index >= 0) { scope.launch { listState.animateScrollToItem(index); highlighted = messageId }; return }
        scope.launch {
            conversation.loadMessagesAround(chat.id, messageId)
                .onSuccess { applied -> if (applied) pendingJumpId = messageId }
                .onFailure { error = it.userMessage(context, failure) }
        }
    }
    fun jumpToPinned(message: ChatMessage) = jumpToMessage(message.id, R.string.chat_pinned_failed)
    // Переход из профиля к вложению: чат открывается у сообщения один раз, после этого запрос сбрасывается.
    LaunchedEffect(focusMessageId) {
        if (focusMessageId == 0L) return@LaunchedEffect
        jumpToMessage(focusMessageId, R.string.chat_message_open_failed)
        onFocusHandled()
    }

    Column(Modifier.fillMaxSize().background(palette.screen).windowInsetsPadding(WindowInsets.safeDrawing)) {
        if (actionMessage != null) MessageActionsBar(
            capabilities = capabilities, error = capabilitiesError, hasText = actionMessage.text.isNotBlank(), isMedia = actionMessage.media != null,
            onClose = ::closeActions, onRetry = { capabilitiesAttempt++ },
            onReply = { replyId = actionMessage.id; replyFocusRequest++; closeActions() },
            onCopy = { clipboard.setPrimaryClip(ClipData.newPlainText(context.getString(R.string.chat_message), actionMessage.text)); closeActions() },
            onEdit = { editId = actionMessage.id; editText = actionMessage.text; closeActions() },
            onDelete = { deleteEveryone = capabilities?.canDeleteForSelf == false; deleting = true }
        ) else if (searching) ChatSearchBar(searchQuery, { searchQuery = it }, ::closeSearch)
        else ChatTopBar(chat, info, lastSeenStyle, onBack, onChatInfo, { searching = true }, observeFile, onDownloadFile)
        reactionOwner?.takeIf { !deleting }?.let { owner ->
            MessageReactionPicker(reactionOptions, owner.reactions.filter { it.isChosen }.mapTo(hashSetOf()) { it.option }, conversation::observeCustomEmoji, observeFile, onDownloadFile) { option ->
                setReaction(owner.id, option, addToRecent = true)
                closeActions()
            }
        }
        PinnedMessagesBar(chat.id, conversation, connectionState == TelegramConnectionState.Connected, ::jumpToPinned)
        if (connectionState == TelegramConnectionState.WaitingForNetwork) Row(
            Modifier.fillMaxWidth().background(palette.warningSurface).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Rounded.WifiOff, null, tint = palette.warningText, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.chat_network_waiting), color = palette.warningText, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        }
        Box(Modifier.fillMaxWidth().weight(1f)) {
        val metrics = LocalBubbleMetrics.current
        LazyColumn(state = listState, reverseLayout = true, modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(vertical = metrics.listPadding), verticalArrangement = Arrangement.spacedBy(metrics.itemSpacing)) {
            items(messageListItems, key = { it.key }) { listItem ->
                if (listItem.pendingVideoNote != null) {
                    PendingVideoNoteBubble(listItem.pendingVideoNote)
                } else if (listItem.mediaAlbumId != 0L) {
                    val latest = listItem.messages.maxByOrNull { it.id }
                    MessageAlbumBubble(listItem.messages, observeFile, onDownloadFile,
                        isRead = latest?.let { it.isOutgoing && it.sendState == MessageSendState.Sent && it.id <= history.lastReadOutboxMessageId } == true,
                        highlighted = listItem.messages.any { it.id == highlighted || it.id == actionsId },
                        onOpen = { selectedMediaId = it }, onActions = { actionsId = it }, onReplyClick = ::jump, onReply = if (swipeReplyAllowed) ::swipeReply else null,
                        onReaction = ::react, observeCustomEmoji = conversation::observeCustomEmoji, onRetry = { retryFailedMessages(listItem.messages.filter { it.sendState == MessageSendState.Failed }.map { it.id }) })
                } else {
                    val message = listItem.messages.single()
                    MessageBubble(message, observeFile, onDownloadFile, isRead = message.isOutgoing && message.sendState == MessageSendState.Sent && message.id <= history.lastReadOutboxMessageId,
                        highlighted = message.id == highlighted || message.id == actionsId, onOpen = { selectedMediaId = message.id }, onActions = { actionsId = message.id }, onReplyClick = ::jump, onReply = if (swipeReplyAllowed) ::swipeReply else null,
                        onPlayed = { conversation.openMessageContent(chat.id, message.id) },
                        onRetry = { retryFailedMessages(listOf(message.id)) }, onReaction = ::react, observeCustomEmoji = conversation::observeCustomEmoji, inlineContent = { InlineBotButtons(message, conversation) })
                }
            }
            history.error?.let { item(key = "history_error") { Text(it.resolve(), color = palette.warningText, modifier = Modifier.padding(8.dp)) } }
            if (history.isLoading) item(key = "history_loading") { Text(stringResource(R.string.chat_history_loading), color = palette.textSecondary, modifier = Modifier.padding(8.dp)) }
            else if (history.hasOlderMessages) item(key = "history_more") { TextButton(onClick = { conversation.loadOlderMessages(chat.id) }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.chat_history_load_older)) } }
            else if (messages.isEmpty() && history.error == null) item(key = "history_empty") { Text(stringResource(R.string.chat_history_empty), color = palette.textSecondary, modifier = Modifier.padding(8.dp)) }
        }
        if (!searching) FloatingMessageDate(listState, messageListItems, Modifier.align(Alignment.TopCenter).padding(top = 8.dp))
        val away by remember { derivedStateOf { listState.firstVisibleItemIndex > 3 } }
        if (away || history.hasNewerMessages) Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp).clip(RoundedCornerShape(50)).background(palette.surface)
            .border(1.dp, palette.divider, RoundedCornerShape(50)).clickable {
                if (history.hasNewerMessages) { conversation.loadLatestMessages(chat.id); scope.launch { listState.scrollToItem(0) } }
                else scope.launch { listState.animateScrollToItem(0) }
            }
            .padding(start = 12.dp, end = 16.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.ArrowDownward, null, tint = palette.accent, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.chat_jump_to_latest), color = palette.accentInk, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        }
        if (searching) ChatSearchResults(searchQuery, searchResults, searchBusy, searchError, hasMore = searchNextId != 0L,
            onOpen = ::openSearchResult, onMore = ::loadMoreResults)
        if (videoNote.active) VideoNoteRecordingOverlay(videoNote)
        }
        error?.let { failure -> Row(Modifier.fillMaxWidth().background(palette.warningSurface).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(failure, color = palette.warningText, fontSize = 12.sp, modifier = Modifier.weight(1f))
            IconButton(onClick = { error = null }) { Icon(Icons.Rounded.Close, stringResource(R.string.common_close), tint = palette.warningText) }
        } }
        val replyTarget = messages.firstOrNull { it.id == replyId }
        if (deleting && actionMessage != null) {
            val caps = capabilities
            if (caps != null) DeleteConfirmPanel(caps, deleteEveryone, deleteBusy, deleteError, onChoose = { deleteEveryone = it },
                onCancel = { deleting = false; deleteError = null }, onConfirm = { scope.launch {
                    deleteBusy = true; deleteError = null
                    try {
                        val result = conversation.deleteMessage(actionMessage.chatId, actionMessage.id, if (deleteEveryone) DeleteMessageScope.ForEveryone else DeleteMessageScope.ForSelf)
                        if (result.isSuccess) closeActions() else deleteError = result.exceptionOrNull()?.userMessage(context, R.string.err_chat_delete_failed)
                    } finally { deleteBusy = false }
                } })
        } else if (editMessage != null) {
            EditBanner(editMessage.text.ifBlank { editMessage.summary() }, editMessage.media != null, editText.codePointCount(0, editText.length), editLimit, editError, onClose = ::closeEdit)
        } else if (!searching) {
            AttachmentPanel(attachments, draft, limits.caption)
            if (replyId != null) Row(Modifier.fillMaxWidth().background(palette.surface).padding(start = 18.dp, end = 6.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).border(1.dp, palette.accent.copy(alpha = 0.45f), RoundedCornerShape(12.dp)).padding(horizontal = 10.dp, vertical = 6.dp)) {
                    Text(stringResource(R.string.chat_reply_label) + " · " + (replyTarget?.senderName?.ifBlank { if (replyTarget.isOutgoing) stringResource(R.string.chat_you) else chat.title } ?: stringResource(R.string.chat_message)), color = palette.accentInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Text(replyTarget?.summary() ?: stringResource(R.string.chat_message_unavailable), color = palette.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 14.sp)
                }
                IconButton(enabled = !sending, onClick = { replyId = null }) { Icon(Icons.Rounded.Close, stringResource(R.string.chat_cancel_reply_description), tint = palette.textSecondary) }
            }
        }
        val editing = editMessage != null
        val fieldText = if (editing) editText else draft
        val fieldLimit = when { editing -> editLimit; attachments.active -> limits.caption; else -> limits.text }
        val overLimit = fieldText.codePointCount(0, fieldText.length) > fieldLimit
        val busy = sending || editBusy || attachments.sending
        val canSend = !busy && !overLimit && when {
            editing -> fieldText != editMessage?.text && (editMessage?.media != null || fieldText.isNotBlank())
            attachments.active -> attachments.pending.isNotEmpty() && !attachments.importing
            else -> fieldText.isNotBlank()
        }
        val recordingActive = videoNote.active || audioNote.active
        val recordingLocked = if (recordingMode == ComposerRecordingMode.Voice) audioNote.locked else videoNote.locked
        val recordingCanceling = if (recordingMode == ComposerRecordingMode.Voice) audioNote.canceling else videoNote.canceling
        val showRecord = recordingActive || (!editing && !attachments.active && fieldText.isBlank())
        if (!deleting && !searching && typingNames.isNotEmpty()) TypingRow(typingNames)
        // Мини-плеер стоит над полем ввода и остаётся на месте при поиске и при выборе сообщений. Без поля ввода он внизу экрана, поэтому отступает от системной навигации.
        NowPlayingBar(bottomInset = deleting || searching)
        if (!deleting && !searching) Column(Modifier.fillMaxWidth().background(palette.surface).navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
            if (!recordingActive) {
                if (!editing) AttachmentButton(attachments, enabled = !sending)
                else Spacer(Modifier.width(8.dp))
            }
            if (audioNote.active) AudioNoteRecordingDock(audioNote, Modifier.weight(1f), onCancel = audioNote::discardLocked)
            else if (videoNote.active) VideoNoteRecordingDock(videoNote, Modifier.weight(1f), onCancel = videoNote::discardLocked)
            else FormattingTextField(fieldText, if (editing) editEntities else draftEntities,
                onChange = { if (editing) editText = it else typedDraft(it) },
                onEntitiesChange = { if (editing) editEntities = it else draftEntities = ArrayList(it) },
                placeholder = if (attachments.active) stringResource(R.string.chat_caption_placeholder) else botKeyboard?.placeholder?.takeIf { it.isNotBlank() } ?: stringResource(R.string.chat_message),
                locked = busy, isError = overLimit, modifier = Modifier.weight(1f), focusRequest = replyFocusRequest)
            Spacer(Modifier.width(8.dp))
            // Keep the same pointer-input node mounted while recording. Removing the button here
            // cancels its gesture coroutine immediately after onStart changes active to true.
            if (recordingActive && recordingLocked) Box(Modifier.size(44.dp).clip(CircleShape)
                .background(palette.accent).clickable(enabled = !busy) {
                    if (recordingMode == ComposerRecordingMode.Voice) audioNote.finishLocked() else videoNote.sendLocked()
                }, contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Rounded.Send, stringResource(R.string.recorder_send), tint = Color.White, modifier = Modifier.size(21.dp))
            }
            else if (showRecord) RecordingControlButton(
                mode = recordingMode, active = recordingActive, canceling = recordingCanceling, enabled = !sending && !busy,
                onTap = { if (!recordingActive) recordingSettings.setRecordingMode(if (recordingMode == ComposerRecordingMode.Voice) ComposerRecordingMode.Video else ComposerRecordingMode.Voice) },
                onStart = { if (!recordingActive) startRecording() },
                onCanceling = { if (recordingMode == ComposerRecordingMode.Voice) audioNote.onDrag(it) else videoNote.onDrag(it) },
                onLock = { if (recordingMode == ComposerRecordingMode.Voice) audioNote.lock() else videoNote.lock() },
                onRelease = { if (recordingMode == ComposerRecordingMode.Voice) audioNote.release(it) else videoNote.release(it) }
            )
            else Box(Modifier.size(40.dp).clip(CircleShape).background(palette.accent.copy(alpha = if (canSend || busy) 1f else 0.4f))
                // A tap must not move focus off the text field, or the keyboard closes.
                .focusProperties { canFocus = false }
                .clickable(enabled = canSend) {
                    when {
                        editing -> scope.launch {
                            val target = editMessage ?: return@launch
                            editBusy = true; editError = null
                            try {
                                val result = conversation.editMessage(target.chatId, target.id, editText, editEntities)
                                if (result.isSuccess) closeEdit() else editError = result.exceptionOrNull()?.userMessage(context, R.string.err_chat_edit_failed)
                            } finally { editBusy = false }
                        }
                        attachments.active -> attachments.send(draft) { draft = it; if (it.isEmpty()) draftEntities = arrayListOf() }
                        else -> scope.launch {
                            sending = true; error = null
                            try {
                                val result = conversation.sendMessage(chat.id, draft, replyId, draftEntities)
                                if (result.isSuccess) {
                                    draft = ""; draftEntities = arrayListOf(); replyId = null
                                    botKeyboard?.takeIf { it.forceReply }?.let { conversation.dismissBotKeyboard(chat.id, it.messageId) }
                                } else error = result.exceptionOrNull()?.userMessage(context, R.string.err_chat_send_failed)
                            } finally { sending = false }
                        }
                    }
                }, contentAlignment = Alignment.Center) {
                if (busy) CircularProgressIndicator(Modifier.size(20.dp), color = palette.onAccent, strokeWidth = 2.dp)
                else Icon(if (editing) Icons.Rounded.Check else Icons.AutoMirrored.Rounded.Send, if (editing) stringResource(R.string.common_save) else stringResource(R.string.common_send),
                    tint = palette.onAccent.copy(alpha = if (canSend) 1f else 0.8f), modifier = Modifier.size(22.dp))
            }
        }
        if (!recordingActive && !editing && !attachments.active) BotReplyKeyboard(chat.id, botKeyboard, conversation)
        }
    }
    // Each unacknowledged video draft remains in the app center. Only the oldest is shown;
    // later previews are retained, not overwritten by a second showPreview() call.
    videoPreview?.let { video ->
        RecordingPreviewDialog(
            mediaList = video.media,
            selectedIndex = recordingPreviewIndex,
            sentPaths = video.media.take(video.nextIndex).mapTo(mutableSetOf()) { it.path },
            sending = video.sending,
            progress = (video.nextIndex + 1).coerceAtMost(video.media.size),
            onSelect = recordingRecovery::select,
            onDelete = { VideoNoteExportCenter.discard(video.chatId, video.sessionName) },
            onSend = {
                val accepted = VideoNoteExportCenter.send(video.chatId, video.sessionName, replyId) { media, targetReply ->
                    conversation.sendMedia(video.chatId, media, "", targetReply).map { Unit }
                }
                if (accepted) replyId = null
            }
        )
    }
    if (videoPreview == null) recordingPreview?.let { mediaList -> RecordingPreviewDialog(
        mediaList = mediaList,
        selectedIndex = recordingPreviewIndex,
        sentPaths = sentRecordingPaths,
        sending = recordingQueueSending,
        progress = recordingQueueProgress,
        onSelect = recordingRecovery::select,
        onDelete = { mediaList.firstOrNull()?.let { java.io.File(it.path).parentFile?.deleteRecursively() }; sentRecordingPaths = emptySet(); recordingRecovery.dismissPreview() },
        onSend = { sendRecordedMedia(mediaList) }
    ) }
    val viewedRights = selectedMediaId?.let { MediaViewerPolicy.rightsFor(it, viewerRights) }
    // Фото и видео листаются вместе; остальные вложения открываются по одному.
    // Действия над сообщением есть только у сообщений из загруженной истории: редактирование ищет их в ленте.
    val viewedInChat = messages.firstOrNull { it.id == selectedMediaId }
    val viewed = viewedInChat ?: mediaWindow.messages.firstOrNull { it.id == selectedMediaId }
    val windowPages = mediaWindow.messages.mapNotNull { m -> m.media?.let { MediaViewerItem(m.id, it) } }
    val historyPages = remember(messages) { messages.mapNotNull { m -> m.media?.takeIf { it.kind in viewerSwipeKinds }?.let { MediaViewerItem(m.id, it) } } }
    // Пока окно не пришло или не загрузилось, листаем уже загруженную историю чата; без неё показываем вложение одно.
    val viewerPages = listOf(windowPages, historyPages).firstOrNull { pages -> pages.any { it.messageId == selectedMediaId } }
        ?: listOfNotNull(viewed?.let { m -> m.media?.let { MediaViewerItem(m.id, it) } })
    if (viewed != null && viewed.media != null) MediaViewer(
        pages = viewerPages, selectedId = viewed.id, onSelect = { selectedMediaId = it },
        observeFile = observeFile, downloadFile = onDownloadFile, onViewed = { id -> conversation.openMessageContent(chat.id, id) }, onClose = { selectedMediaId = null },
        title = if (viewed.isOutgoing) stringResource(R.string.chat_you) else viewed.senderName.ifBlank { chat.title }, subtitle = listOfNotNull(viewed.time, viewerPosition?.let { stringResource(R.string.chat_media_position, it.number, it.total) }).joinToString(" · "),
        canExport = viewedRights?.canSave == true, confirmExport = { id -> conversation.messageCapabilities(chat.id, id).getOrNull()?.canSave == true },
        actions = viewedInChat?.let { MediaViewerActions(
            canForward = viewedRights?.canForward == true,
            canEdit = viewedRights?.canEdit == true,
            canDelete = viewedRights?.let { it.canDeleteForSelf || it.canDeleteForAll } == true,
            onForward = { forwardId = viewed.id; selectedMediaId = null },
            onEdit = { editId = viewed.id; editText = viewed.text; selectedMediaId = null },
            onDelete = { deleteEveryone = viewedRights?.canDeleteForSelf == false; actionsId = viewed.id; deleting = true; selectedMediaId = null }
        ) }, onShowInChat = { id -> selectedMediaId = null; jumpToMessage(id, R.string.err_chat_history_load_failed) })
    forwardId?.let { id ->
        ForwardChatDialog(chats, forwardBusy, forwardError,
            onPick = { target -> scope.launch {
                forwardBusy = true; forwardError = null
                try {
                    val result = conversation.forwardMessage(chat.id, id, target.id)
                    if (result.isSuccess) { forwardId = null; Toast.makeText(context, context.getString(R.string.chat_message_forwarded), Toast.LENGTH_SHORT).show() }
                    else forwardError = result.exceptionOrNull().userMessage(context, R.string.chat_forward_failed)
                } finally { forwardBusy = false }
            } },
            onClose = { forwardId = null; forwardError = null })
    }
    contextMessageId?.let { id -> MessageContextDialog(contextChatId, id, conversation, observeFile, onDownloadFile, onClose = { contextMessageId = null }) }
}

@Composable
private fun ChatTopBar(chat: ChatPreview, info: ProfileInfo?, lastSeenStyle: LastSeenStyle, onBack: () -> Unit, onInfo: () -> Unit, onSearch: () -> Unit, observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit) {
    val palette = beyGramPalette()
    // Время в строке статуса пересчитывается отдельно от экрана: тик перерисовывает только шапку.
    val now by rememberPresenceClock(info?.status is ProfilePresence.LastSeen)
    Column(Modifier.fillMaxWidth().background(palette.surface)) {
        Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp, top = 6.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.common_back), tint = palette.textPrimary) }
            TelegramAvatar(chat.initials, Color(chat.avatarColorArgb), 40.dp, chat.photo, observeFile, downloadFile, Modifier.clickable(onClick = onInfo))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f).clickable(onClick = onInfo)) {
                Text(chat.title, color = palette.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(chatPresenceLine(chat, info, lastSeenStyle, now).resolve(), color = palette.textSecondary, fontSize = 13.sp)
            }
            IconButton(onClick = onSearch) { Icon(Icons.Rounded.Search, stringResource(R.string.chat_search_description), tint = palette.textSecondary) }
        }
        HorizontalDivider(color = palette.divider)
    }
}

@Composable
internal fun MessageBubble(message: ChatMessage, observeFile: (Int) -> StateFlow<MediaFileState>, onDownloadFile: (Int) -> Unit,
    isRead: Boolean = false, highlighted: Boolean = false, onOpen: () -> Unit, onActions: (() -> Unit)? = null, onReplyClick: (MessageReply) -> Unit = {}, onPlayed: () -> Unit = {}, onRetry: () -> Unit = {}, onReply: ((Long) -> Unit)? = null, onReaction: (Long, ReactionOption) -> Unit, observeCustomEmoji: (Long) -> StateFlow<CustomEmoji?>, inlineContent: @Composable () -> Unit = {}) {
    val palette = beyGramPalette()
    val metrics = LocalBubbleMetrics.current
    val shape = bubbleShape(message.isOutgoing, metrics)
    val hasText = message.text.isNotBlank()
    val circle = message.media?.kind == MediaKind.VideoNote
    // Стикер лежит без пузыря: ни цвета, ни ширины фото.
    val sticker = message.media?.kind == MediaKind.Sticker
    // Время и статус кружка находятся под кругом, вне обрезки видео.
    val inCircle = circle && message.sendState != MessageSendState.Failed
    // Пока сообщение отправляется или не ушло, его id временный и потом меняется: место для общего плеера не ставим.
    val playbackOrigin = if (message.sendState == MessageSendState.Sent) PlaybackOrigin(message.chatId, message.id) else null
    val statusIcon = when {
        !message.isOutgoing -> null
        message.sendState == MessageSendState.Sending -> Icons.Rounded.Schedule
        message.sendState == MessageSendState.Sent -> if (isRead) Icons.Rounded.DoneAll else Icons.Rounded.Done
        else -> null
    }
    // Фото, видео и гифки без подписи: время ставится поверх нижнего правого угла, как в Telegram.
    val overlayMeta = !circle && !hasText && message.reply == null && message.sendState != MessageSendState.Failed &&
        message.media?.kind?.let { it == MediaKind.Photo || it == MediaKind.Video || it == MediaKind.Animation } == true
    Column(Modifier.fillMaxWidth().then(if (circle) Modifier else Modifier.padding(horizontal = metrics.sideInset)), horizontalAlignment = if (message.isOutgoing) Alignment.End else Alignment.Start) {
        SwipeToReply(enabled = onReply != null && message.sendState == MessageSendState.Sent, outgoing = message.isOutgoing,
            onReply = { onReply?.invoke(message.id) }) { swipe ->
            // Голосовое и кружок управляются своими элементами в пузыре и не открывают просмотрщик.
            BubbleLayout(
                swipe.widthIn(max = if (circle) androidx.compose.ui.unit.Dp.Infinity else 292.dp)
                    .then(if (message.media != null && !circle && !sticker) Modifier.width(244.dp) else Modifier).clip(shape)
                    .background(if (circle || sticker) Color.Transparent else if (message.isOutgoing) palette.outgoingBubble else palette.incomingBubble)
                    .then(if (highlighted && !circle) Modifier.border(2.dp, palette.accent, shape) else Modifier)
                    .combinedClickable(onClick = { if (message.media != null && !message.media.kind.playsInline()) onOpen() }, onLongClick = onActions),
                overlayMeta = overlayMeta,
                body = {
                    Column {
                        if (!message.isOutgoing && message.senderName.isNotBlank()) Text(message.senderName, color = palette.accentInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                        // Media sits flush against the bubble's top and side edges; text keeps its own padding.
                        message.media?.let { media ->
                            if (media.kind == MediaKind.VideoNote) VideoNoteBubble(media, observeFile, onDownloadFile, onPlayed, onActions,
                                time = if (inCircle) message.time else "", statusIcon = if (inCircle) statusIcon else null,
                                statusDescription = when {
                                    !message.isOutgoing -> null
                                    message.sendState == MessageSendState.Sending -> stringResource(R.string.chat_sending_description)
                                    isRead -> stringResource(R.string.chat_read_description)
                                    else -> stringResource(R.string.chat_sent_description)
                                }, unseen = !message.isOutgoing && !media.isViewed, highlighted = highlighted, origin = playbackOrigin)
                            else MediaPreview(media, observeFile, onDownloadFile, onOpen, onActions, onPlayed, origin = playbackOrigin)
                        }
                        // Без текста и ответа под фото нет строки: время уже стоит поверх него.
                        if (hasText || message.reply != null || !overlayMeta) Column(Modifier.padding(start = metrics.textInset, end = metrics.textInset, top = if (circle) metrics.circleTopInset else metrics.textTopInset)) {
                            message.reply?.let { reply ->
                                Column(Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(metrics.replyRadius))
                                    .border(1.dp, palette.accent, RoundedCornerShape(metrics.replyRadius))
                                    .clickable { onReplyClick(reply) }.padding(horizontal = 10.dp, vertical = 8.dp)) {
                                    Text(reply.senderName.ifBlank { stringResource(R.string.chat_reply_to_message) }, color = palette.accentInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                    Text(reply.text.resolve(), color = palette.textSecondary, fontSize = 14.sp, lineHeight = 19.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                }
                            }
                            if (hasText) FormattedMessageText(message)
                        }
                    }
                },
                meta = {
                    if (!inCircle) BubbleMeta(message, isRead, retryAvailable = message.isOutgoing && message.sendState == MessageSendState.Failed,
                        overlay = overlayMeta, onRetry = onRetry)
                },
                footer = inlineContent
            )
        }
        MessageReactionChips(message.reactions, observeCustomEmoji, observeFile, onDownloadFile, onToggle = { onReaction(message.id, it) }, modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp))
    }
}
