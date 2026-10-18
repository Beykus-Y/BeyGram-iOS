package com.beykus.beygram.ui.screens.profile

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beykus.beygram.data.media.OutgoingMediaImporter
import com.beykus.beygram.data.presence.LastSeenStyle
import com.beykus.beygram.domain.model.*
import com.beykus.beygram.navigation.MainTab
import com.beykus.beygram.ui.components.*
import com.beykus.beygram.ui.screens.chat.LocalMediaImage
import com.beykus.beygram.ui.screens.chat.MediaViewer
import com.beykus.beygram.ui.screens.chat.MediaViewerItem
import com.beykus.beygram.ui.screens.chat.presenceText
import com.beykus.beygram.ui.screens.chat.rememberPresenceClock
import com.beykus.beygram.ui.text.resolve
import com.beykus.beygram.ui.text.userMessage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import androidx.compose.ui.res.stringResource
import com.beykus.beygram.R
import java.time.LocalDate
import java.time.MonthDay
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun ProfileScreen(
    state: ProfileState, isOwnProfile: Boolean,
    observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit,
    onBack: () -> Unit, onRefresh: () -> Unit, onEdit: () -> Unit,
    setPhoto: suspend (OutgoingMedia) -> Result<Unit>,
    onOpenAppearance: () -> Unit = {}, lastSeenStyle: LastSeenStyle,
    onNotifications: () -> Unit = {}, onMembers: () -> Unit = {}, onOpenUser: (Long) -> Unit = {},
    hiddenTabs: List<MainTab> = emptyList(), onOpenTab: (MainTab) -> Unit = {},
    sharedMessages: (suspend (SharedMediaKind, Long, Boolean) -> Result<MessageSearchPage>)? = null,
    confirmExport: suspend (Long) -> Boolean = { false }, onContentOpened: (Long) -> Unit = {}, onOpenMessage: (Long) -> Unit = {}
) {
    val palette = beyGramPalette()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val importer = remember { OutgoingMediaImporter(context) }
    var showPhoto by rememberSaveable(state.info?.id) { mutableStateOf(false) }
    var pendingPhoto by rememberSaveable { mutableStateOf<OutgoingMedia?>(null) }
    var preparing by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var photoError by rememberSaveable { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            preparing = true; photoError = null
            try { pendingPhoto = replacePendingPhoto(pendingPhoto, { importer.prepare(uri, asDocument = false, squarePhoto = true) }, importer::discard) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { photoError = error.userMessage(context, R.string.profile_photo_prepare_failed) }
            finally { preparing = false }
        }
    }
    BackHandler { if (!saving && !preparing) onBack() }
    val groupInfo = state.info?.takeIf { it.kind == ProfileKind.Group }
    if (pendingPhoto == null && groupInfo != null) GroupProfileScreen(
        info = groupInfo, state = state, lastSeenStyle = lastSeenStyle, observeFile = observeFile, downloadFile = downloadFile,
        onBack = { if (!saving && !preparing) onBack() }, onRefresh = onRefresh, onAvatarClick = { showPhoto = true },
        onMembers = onMembers, onOpenUser = onOpenUser, sharedMessages = sharedMessages, confirmExport = confirmExport,
        onContentOpened = onContentOpened, onOpenMessage = onOpenMessage
    ) else if (pendingPhoto == null) Column(Modifier.fillMaxSize().background(palette.screen).windowInsetsPadding(WindowInsets.safeDrawing)) {
        ProfileToolbar(if (isOwnProfile) stringResource(R.string.profile_title_own) else stringResource(R.string.profile_title_chat), { if (!saving && !preparing) onBack() }) {
            IconButton(onClick = onRefresh, enabled = !state.isLoading && !saving) { Icon(Icons.Rounded.Refresh, stringResource(R.string.common_refresh), tint = palette.textSecondary) }
        }
        if (state.isLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 28.dp)) {
            state.info?.let { info ->
                Column(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    TelegramAvatar(info.initials, palette.accent, 112.dp, info.photo, observeFile, downloadFile,
                        Modifier.clickable(enabled = info.photo != null) { showPhoto = true })
                    Spacer(Modifier.height(16.dp))
                    Text(info.title.ifBlank { stringResource(R.string.user_name_unknown) }, color = palette.textPrimary, fontSize = 26.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(4.dp))
                    ProfileSubtitle(info, lastSeenStyle)
                    ProfileBadges(info)
                    if (isOwnProfile) {
                        Spacer(Modifier.height(14.dp))
                        FilledTonalButton(onClick = onEdit, enabled = !state.isLoading && state.error == null && !saving && !preparing, shape = RoundedCornerShape(14.dp),
                            modifier = Modifier.height(46.dp), colors = ButtonDefaults.filledTonalButtonColors(containerColor = palette.accentSoft, contentColor = palette.accentInk)) { Text(stringResource(R.string.profile_action_edit), fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
                        TextButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !saving && !preparing) { Text(if (preparing) stringResource(R.string.profile_photo_preparing) else stringResource(R.string.profile_action_change_photo), fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
                    }
                }
                ProfileRowsCard(profileRows(context, info, withSharedCounts = sharedMessages == null))
                if (info.administrators.isNotEmpty()) AdministratorsSection(info.administrators, onOpenUser)
                if (info.canListMembers && info.memberPreview.isNotEmpty()) MembersSection(info, observeFile, downloadFile, onMembers, onOpenUser)
                if (sharedMessages != null) SharedMediaSection(info.id, info.sharedCounts, sharedMessages, observeFile, downloadFile, confirmExport, onContentOpened, onOpenMessage)
                if (isOwnProfile && hiddenTabs.isNotEmpty()) HiddenTabsSection(hiddenTabs, onOpenTab)
                if (isOwnProfile) TextButton(onClick = onNotifications, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) { Text(stringResource(R.string.profile_notifications), fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
                if (isOwnProfile) Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(palette.surface).clickable(onClick = onOpenAppearance).padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Palette, null, tint = palette.accent, modifier = Modifier.size(22.dp))
                    Text(stringResource(R.string.theme_title), color = palette.textPrimary, fontSize = 16.sp, modifier = Modifier.weight(1f).padding(start = 14.dp))
                    Icon(Icons.Rounded.ChevronRight, null, tint = palette.textSecondary, modifier = Modifier.size(22.dp))
                }
            }
            if (state.info == null && !state.isLoading && state.error == null) Text(stringResource(R.string.profile_info_not_loaded), color = palette.textSecondary, modifier = Modifier.padding(24.dp))
            state.error?.let { Text(it.resolve(), color = palette.danger, modifier = Modifier.padding(20.dp)) }
            photoError?.let { Text(it, color = palette.danger, modifier = Modifier.padding(20.dp)) }
        }
    }
    val photo = state.info?.photo
    // Фото профиля не привязано к сообщению, поэтому у единственной страницы нет id (0).
    if (showPhoto && photo != null) MediaViewer(
        pages = listOf(MediaViewerItem(0L, MessageMedia(MediaKind.Photo, photo.bigFileId, photo.smallFileId, stringResource(R.string.profile_photo_title), "image/jpeg"))), selectedId = 0L,
        onSelect = {}, observeFile = observeFile, downloadFile = downloadFile, onViewed = {}, onClose = { showPhoto = false })
    pendingPhoto?.let { selected ->
        fun discard() { if (!saving) { pendingPhoto = null; scope.launch { importer.discard(selected) } } }
        BackHandler(onBack = ::discard)
        Column(Modifier.fillMaxSize().background(palette.screen).windowInsetsPadding(WindowInsets.safeDrawing)) {
            ProfileToolbar(stringResource(R.string.profile_photo_new_title), ::discard)
            Column(Modifier.weight(1f).fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                LocalMediaImage(selected.path, Modifier.size(240.dp).clip(CircleShape))
                Text(stringResource(R.string.profile_photo_preview_hint), color = palette.textSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 16.dp))
                TextButton(enabled = !saving, onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Text(stringResource(R.string.profile_photo_pick_other), fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
                if (saving) CircularProgressIndicator(Modifier.padding(top = 8.dp).size(24.dp), color = palette.accent)
                photoError?.let { Text(it, color = palette.danger, modifier = Modifier.padding(top = 12.dp)) }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                FilledTonalButton(onClick = ::discard, enabled = !saving, shape = RoundedCornerShape(16.dp), modifier = Modifier.weight(1f).height(50.dp),
                    colors = ButtonDefaults.filledTonalButtonColors(containerColor = palette.accentSoft, contentColor = palette.accentInk)) { Text(stringResource(R.string.common_cancel), fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
                Button(enabled = !saving, shape = RoundedCornerShape(16.dp), modifier = Modifier.weight(1f).height(50.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = palette.accent, contentColor = palette.onAccent), onClick = { scope.launch {
                        saving = true; photoError = null
                        try {
                            val result = setPhoto(selected)
                            if (result.isSuccess) pendingPhoto = null
                            else photoError = result.exceptionOrNull().userMessage(context, R.string.profile_photo_update_failed)
                        } finally { saving = false }
                    } }) { Text(if (saving) stringResource(R.string.common_saving) else stringResource(R.string.profile_photo_set), fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}

@Composable internal fun ProfileSubtitle(info: ProfileInfo, lastSeenStyle: LastSeenStyle) {
    val palette = beyGramPalette()
    // Тик времени перерисовывает только подпись, а не весь экран профиля.
    val now by rememberPresenceClock(info.status is ProfilePresence.LastSeen)
    Text(info.subtitle(lastSeenStyle, now), color = palette.textSecondary, fontSize = 14.sp)
}

@Composable private fun ProfileInfo.subtitle(lastSeenStyle: LastSeenStyle, nowMillis: Long): String = when (kind) {
    ProfileKind.Group -> memberCount?.let { count ->
        onlineMemberCount?.let { stringResource(R.string.profile_group_members_online_count, count, it) } ?: stringResource(R.string.profile_group_members_count, count)
    } ?: stringResource(R.string.profile_type_group)
    ProfileKind.Channel -> memberCount?.let { stringResource(R.string.profile_channel_subscribers_count, it) } ?: stringResource(R.string.profile_type_channel)
    ProfileKind.Secret -> stringResource(R.string.profile_secret_chat_status, status?.let { presenceText(it, lastSeenStyle, nowMillis).resolve() }.orEmpty())
    ProfileKind.Bot -> stringResource(R.string.profile_type_bot)
    ProfileKind.Person -> if (isSelf) stringResource(R.string.profile_own_account_telegram) else status?.let { presenceText(it, lastSeenStyle, nowMillis).resolve() }.orEmpty()
}

/** Подготавливает новое фото и удаляет прежнее. Если подготовка падает, прежнее фото не трогаем. */
internal suspend fun <T : Any> replacePendingPhoto(previous: T?, prepare: suspend () -> T, discard: suspend (T) -> Unit): T {
    val next = prepare()
    previous?.let { discard(it) }
    return next
}

/** День рождения для строки профиля; год показываем, только если аккаунт его указал. Null, если дата не сходится с календарём. */
internal fun birthdayText(birthday: ProfileBirthday, locale: Locale): String? = runCatching {
    if (birthday.year == null) MonthDay.of(birthday.month, birthday.day).format(DateTimeFormatter.ofPattern("d MMMM", locale))
    else LocalDate.of(birthday.year, birthday.month, birthday.day).format(DateTimeFormatter.ofPattern("d MMMM yyyy", locale))
}.getOrNull()

/** Строки карточки профиля. Счётчики медиа входят сюда, только если под профилем нет вкладок с ними. */
internal fun profileRows(context: Context, info: ProfileInfo, withSharedCounts: Boolean): List<Pair<String, String>> = buildList {
    if (info.phone.isNotBlank()) add(context.getString(R.string.profile_row_phone) to "+${info.phone.removePrefix("+")}")
    (info.usernames + info.username.takeIf { it.isNotBlank() }).filterNotNull().distinct().forEach { add(context.getString(R.string.profile_username) to "@$it") }
    if (info.bio.isNotBlank()) add((if (info.kind == ProfileKind.Group || info.kind == ProfileKind.Channel) context.getString(R.string.profile_row_description) else context.getString(R.string.profile_about_me)) to info.bio)
    info.birthday?.let { birthdayText(it, Locale.getDefault()) }?.let { add(context.getString(R.string.profile_row_birthday) to it) }
    if (info.address.isNotBlank()) add(context.getString(R.string.profile_row_address) to info.address)
    info.commonGroupCount?.let { add(context.getString(R.string.profile_row_common_groups) to it.toString()) }
    if (info.inviteLink.isNotBlank()) add(context.getString(R.string.profile_row_invite_link) to info.inviteLink)
    if (info.memberCount != null) add((if (info.kind == ProfileKind.Channel) context.getString(R.string.profile_row_subscribers) else context.getString(R.string.profile_row_members)) to info.memberCount.toString())
    info.administratorCount?.let { add(context.getString(R.string.profile_row_administrators) to it.toString()) }
    add(context.getString(R.string.profile_row_type) to when (info.kind) {
        ProfileKind.Person -> if (info.isSelf) context.getString(R.string.profile_type_own_account) else context.getString(R.string.profile_type_private_chat)
        ProfileKind.Bot -> context.getString(R.string.profile_type_bot)
        ProfileKind.Group -> context.getString(R.string.profile_type_group)
        ProfileKind.Channel -> context.getString(R.string.profile_type_channel)
        ProfileKind.Secret -> context.getString(R.string.profile_type_secret_chat)
    })
    // Со вкладками счётчики стоят в заголовках; без них (профиль участника) остаются строками карточки.
    if (withSharedCounts) info.sharedCounts?.let { counts ->
        counts.media?.let { add(context.getString(R.string.profile_shared_media) to it.toString()) }
        counts.files?.let { add(context.getString(R.string.profile_shared_files) to it.toString()) }
        counts.links?.let { add(context.getString(R.string.profile_shared_links) to it.toString()) }
        counts.voice?.let { add(context.getString(R.string.profile_shared_voice) to it.toString()) }
    }
}

/** Карточка строк профиля: подпись над значением, разделители между строками. */
@Composable
internal fun ProfileRowsCard(rows: List<Pair<String, String>>) {
    val palette = beyGramPalette()
    Column(Modifier.padding(horizontal = 16.dp).clip(RoundedCornerShape(20.dp)).background(palette.surface).padding(vertical = 4.dp)) {
        rows.forEachIndexed { index, (label, value) ->
            if (index > 0) HorizontalDivider(color = palette.divider, modifier = Modifier.padding(start = 20.dp))
            InfoRow(label, value)
        }
    }
}

/** Значки подтверждения и Premium под названием. */
@Composable
internal fun ProfileBadges(info: ProfileInfo) {
    val palette = beyGramPalette()
    if (info.isVerified || info.isPremium) Text(
        listOfNotNull(if (info.isVerified) stringResource(R.string.profile_badge_verified) else null, if (info.isPremium) stringResource(R.string.profile_badge_premium) else null).joinToString(" · "),
        color = palette.accentInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp)
    )
}

@Composable
internal fun InfoRow(label: String, value: String) {
    val palette = beyGramPalette()
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp)) {
        Text(label, color = palette.accentInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(2.dp))
        SelectionContainer { Text(value, color = palette.textPrimary, fontSize = 16.sp, lineHeight = 22.sp) }
    }
}

@Composable
internal fun AdministratorsSection(administrators: List<ProfileAdmin>, onOpenUser: (Long) -> Unit) {
    val palette = beyGramPalette()
    Text(stringResource(R.string.profile_admins_header), color = palette.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 6.dp))
    Column(Modifier.padding(horizontal = 16.dp).clip(RoundedCornerShape(20.dp)).background(palette.surface).padding(vertical = 4.dp)) {
        administrators.forEachIndexed { index, admin ->
            if (index > 0) HorizontalDivider(color = palette.divider, modifier = Modifier.padding(start = 20.dp))
            Box(Modifier.fillMaxWidth().clickable { onOpenUser(admin.userId) }) {
                InfoRow(adminRole(admin), admin.name.ifBlank { stringResource(R.string.user_name_unknown) })
            }
        }
    }
}

@Composable
private fun MembersSection(info: ProfileInfo, observeFile: (Int) -> StateFlow<MediaFileState>, downloadFile: (Int) -> Unit, onMembers: () -> Unit, onOpenUser: (Long) -> Unit) {
    val palette = beyGramPalette()
    Text(stringResource(R.string.profile_members_header), color = palette.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 6.dp))
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

@Composable private fun adminRole(admin: ProfileAdmin): String = when {
    admin.customTitle.isNotBlank() -> admin.customTitle
    admin.isOwner -> stringResource(R.string.profile_admin_owner)
    else -> stringResource(R.string.profile_admin_role)
}

/** Разделы, скрытые из нижнего меню, открываются отсюда так же, как с панели. */
@Composable
private fun HiddenTabsSection(hiddenTabs: List<MainTab>, onOpenTab: (MainTab) -> Unit) {
    val palette = beyGramPalette()
    Text(stringResource(R.string.profile_hidden_tabs_header), color = palette.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 6.dp))
    Column(Modifier.padding(horizontal = 16.dp).clip(RoundedCornerShape(20.dp)).background(palette.surface).padding(vertical = 4.dp)) {
        hiddenTabs.forEachIndexed { index, tab ->
            if (index > 0) HorizontalDivider(color = palette.divider, modifier = Modifier.padding(start = 56.dp))
            Row(Modifier.fillMaxWidth().clickable { onOpenTab(tab) }.padding(horizontal = 20.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(tab.icon, null, tint = palette.accent, modifier = Modifier.size(22.dp))
                Column(Modifier.weight(1f).padding(start = 14.dp)) {
                    Text(tab.title, color = palette.textPrimary, fontSize = 16.sp)
                    Text(stringResource(R.string.profile_hidden_tab_hint), color = palette.textSecondary, fontSize = 12.sp)
                }
                Icon(Icons.Rounded.ChevronRight, null, tint = palette.textSecondary, modifier = Modifier.size(22.dp))
            }
        }
    }
}

@Composable
internal fun ProfileToolbar(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit = {}) {
    val palette = beyGramPalette()
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.common_back), tint = palette.textPrimary) }
        Text(title, color = palette.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        actions()
    }
}

@Composable
fun EditProfileScreen(info: ProfileInfo, bioLimit: Int, onBack: () -> Unit, save: suspend (ProfileEdit) -> Result<Unit>) {
    val palette = beyGramPalette()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var first by rememberSaveable(info.id) { mutableStateOf(info.firstName) }
    var last by rememberSaveable(info.id) { mutableStateOf(info.lastName) }
    var username by rememberSaveable(info.id) { mutableStateOf(info.username) }
    var bio by rememberSaveable(info.id) { mutableStateOf(info.bio) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var discard by remember { mutableStateOf(false) }
    val changed = first.trim() != info.firstName || last.trim() != info.lastName || username.trim().removePrefix("@") != info.username || bio != info.bio
    val bioCount = bio.codePointCount(0, bio.length)
    fun back() { if (!saving) { if (changed && !discard) discard = true else onBack() } }
    BackHandler(onBack = ::back)
    Column(Modifier.fillMaxSize().background(palette.screen).windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
        ProfileToolbar(stringResource(R.string.profile_title_own), ::back) {
            TextButton(enabled = !saving && changed && first.isNotBlank() && bioCount <= bioLimit, onClick = { scope.launch {
                discard = false
                saving = true; error = null
                try {
                    val result = save(ProfileEdit(first, last, username, bio))
                    if (result.isSuccess) onBack()
                    else error = result.exceptionOrNull().userMessage(context, R.string.profile_save_failed) + "\n" + context.getString(R.string.profile_save_partial_hint)
                } finally { saving = false }
            } }) { Text(if (saving) "…" else stringResource(R.string.common_save)) }
        }
        if (saving) LinearProgressIndicator(Modifier.fillMaxWidth(), color = palette.accent)
        if (discard) Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).clip(RoundedCornerShape(16.dp)).background(palette.warningSurface).padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.profile_unsaved_changes), color = palette.warningText, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            TextButton(onClick = onBack) { Text(stringResource(R.string.profile_discard_changes), color = palette.warningText, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            OutlinedTextField(first, { first = it.take(64) }, label = { Text(stringResource(R.string.profile_first_name)) }, singleLine = true, enabled = !saving, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words), shape = RoundedCornerShape(14.dp), colors = beyGramTextFieldColors())
            OutlinedTextField(last, { last = it.take(64) }, label = { Text(stringResource(R.string.profile_last_name)) }, singleLine = true, enabled = !saving, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words), shape = RoundedCornerShape(14.dp), colors = beyGramTextFieldColors())
            OutlinedTextField(username, { username = it.removePrefix("@").take(32) }, label = { Text(stringResource(R.string.profile_username)) }, prefix = { Text("@") }, supportingText = { Text(stringResource(R.string.profile_username_hint)) }, singleLine = true, enabled = !saving, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii), shape = RoundedCornerShape(14.dp), colors = beyGramTextFieldColors())
            OutlinedTextField(bio, { bio = it }, label = { Text(stringResource(R.string.profile_about_me)) }, supportingText = { Text(stringResource(R.string.profile_bio_counter, bioCount, bioLimit)) }, isError = bioCount > bioLimit, minLines = 3, maxLines = 6, enabled = !saving, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences), shape = RoundedCornerShape(14.dp), colors = beyGramTextFieldColors())
            Text(stringResource(R.string.profile_save_hint), color = palette.textSecondary, fontSize = 13.sp)
            error?.let { Text(it, color = palette.danger) }
        }
    }
}
