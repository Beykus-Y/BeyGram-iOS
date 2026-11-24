import Foundation

/// Plural categories following CLDR rules.
public enum BeyGramPluralCategory: String, CaseIterable {
    case one
    case few
    case many
    case other
}

/// Unified localization keys for all BeyGram features.
public enum BeyGramStringKey: String, CaseIterable {
    // BG Wave: the hint for a session that failed where a denied Local Network permission may be the cause
    case bgWaveLocalNetworkTitle = "bgwave.localNetwork.title"
    case bgWaveLocalNetworkMessage = "bgwave.localNetwork.message"
    case bgWaveLocalNetworkSettings = "bgwave.localNetwork.settings"
    case bgWaveLocalNetworkNotNow = "bgwave.localNetwork.notNow"
    // Music player sleep timer
    case sleepTimerTitle = "music.sleepTimer.title"
    case sleepTimerMinutes = "music.sleepTimer.minutes"
    case sleepTimerUntilTrackEnd = "music.sleepTimer.untilTrackEnd"
    case sleepTimerExtend = "music.sleepTimer.extend"
    case sleepTimerCancel = "music.sleepTimer.cancel"
    // Music player equalizer
    case equalizerTitle = "music.equalizer.title"
    case equalizerEnable = "music.equalizer.enable"
    case equalizerReset = "music.equalizer.reset"
    case equalizerPresetFlat = "music.equalizer.preset.flat"
    case equalizerPresetBass = "music.equalizer.preset.bass"
    case equalizerPresetVocal = "music.equalizer.preset.vocal"
    case equalizerPresetPop = "music.equalizer.preset.pop"
    case equalizerPresetRock = "music.equalizer.preset.rock"
    case equalizerPresetElectronic = "music.equalizer.preset.electronic"
    case equalizerPresetClassical = "music.equalizer.preset.classical"
    case equalizerPresetJazz = "music.equalizer.preset.jazz"
    case equalizerPresetCustom = "music.equalizer.preset.custom"
    // Common
    case commonBack = "common.back"
    case commonCancel = "common.cancel"
    case commonSave = "common.save"
    case commonDelete = "common.delete"
    case commonEdit = "common.edit"
    case commonDone = "common.done"
    case commonRetry = "common.retry"
    case commonCopy = "common.copy"
    case commonCopied = "common.copied"
    case commonError = "common.error"
    case commonLoading = "common.loading"
    case commonExperimental = "common.experimental"
    case commonEnabled = "common.enabled"
    case commonDisabled = "common.disabled"
    case commonOn = "common.on"
    case commonOff = "common.off"
    case commonDetails = "common.details"
    case commonClose = "common.close"
    case commonSearch = "common.search"
    case commonClear = "common.clear"
    case commonOk = "common.ok"

    // Main Settings & BeyGram Hub
    case settingsSectionTitle = "settings.section.title"
    case settingsHubTitle = "settings.hub.title"
    case settingsHubSubtitle = "settings.hub.subtitle"
    case settingsPrivacyTitle = "settings.privacy.title"
    case settingsMusicTitle = "settings.music.title"
    case settingsMihomoTitle = "settings.mihomo.title"
    case settingsTriggerWordsTitle = "settings.triggerWords.title"
    case settingsBgPushTitle = "settings.bgPush.title"
    case settingsAppearanceTitle = "settings.appearance.title"
    case settingsDiagnosticsTitle = "settings.diagnostics.title"
    case settingsUpdatesTitle = "settings.updates.title"
    case settingsAboutTitle = "settings.about.title"
    case settingsAboutSectionInfo = "settings.about.section.info"
    case settingsAboutVersion = "settings.about.version"
    case settingsAboutBuild = "settings.about.build"
    case settingsAboutChannel = "settings.about.channel"
    case settingsAboutCommit = "settings.about.commit"
    case settingsAboutFooter = "settings.about.footer"

    // Appearance
    case appearanceTitle = "appearance.title"
    case appearanceSectionStyle = "appearance.section.style"
    case appearanceStyleTelegram = "appearance.style.telegram"
    case appearanceStyleBeyGram = "appearance.style.beygram"
    case appearanceStyleDefault = "appearance.style.default"
    case appearanceStyleMaterial2 = "appearance.style.material2"
    case appearanceStyleMaterial3 = "appearance.style.material3"
    case appearanceStyleLiquidGlass = "appearance.style.liquidGlass"
    case appearanceStyleSignature = "appearance.style.signature"
    case appearanceSectionGlass = "appearance.section.glass"
    case appearanceGlassAuto = "appearance.glass.auto"
    case appearanceGlassHigh = "appearance.glass.high"
    case appearanceGlassBalanced = "appearance.glass.balanced"
    case appearanceGlassLite = "appearance.glass.lite"
    case appearanceSectionNavigation = "appearance.section.navigation"
    case appearanceNavAuto = "appearance.nav.auto"
    case appearanceNavPinned = "appearance.nav.pinned"
    case appearanceNavFloating = "appearance.nav.floating"
    case appearanceDescription = "appearance.description"

    // Privacy & Stealth
    case privacyTitle = "privacy.title"
    case privacyMasterTitle = "privacy.master.title"
    case privacyMasterActiveSummary = "privacy.master.activeSummary"
    case privacyMasterInactiveSummary = "privacy.master.inactiveSummary"
    case privacySectionHide = "privacy.section.hide"
    case privacyHideTyping = "privacy.hideTyping"
    case privacyNoReadReceipts = "privacy.noReadReceipts"
    case privacyHideOnline = "privacy.hideOnline"
    case privacySectionSend = "privacy.section.send"
    case privacyDelayedSend = "privacy.delayedSend"
    case privacyDelayPickerTitle = "privacy.delay.pickerTitle"
    case privacyDelaySheetTitle = "privacy.delay.sheetTitle"
    case privacyRestrictionsTitle = "privacy.restrictions.title"
    case privacyRestrictionsSummary = "privacy.restrictions.summary"
    case privacyHowItWorksTitle = "privacy.howItWorks.title"
    case privacyHowItWorksBody = "privacy.howItWorks.body"
    case privacyDisclaimer = "privacy.disclaimer"
    case stealthRefusedTitle = "stealth.refused.title"
    case stealthRefusedBody = "stealth.refused.body"
    case stealthSendNowAction = "stealth.sendNow.action"
    case stealthSendNowConfirm = "stealth.sendNow.confirm"

    // Mihomo
    case mihomoTitle = "mihomo.title"
    case mihomoStatusConnected = "mihomo.status.connected"
    case mihomoStatusConnecting = "mihomo.status.connecting"
    case mihomoStatusReconnecting = "mihomo.status.reconnecting"
    case mihomoStatusDisconnected = "mihomo.status.disconnected"
    case mihomoStatusError = "mihomo.status.error"
    case mihomoConnect = "mihomo.connect"
    case mihomoDisconnect = "mihomo.disconnect"
    case mihomoActiveServer = "mihomo.activeServer"
    case mihomoLatency = "mihomo.latency"
    case mihomoLatencyUnavailable = "mihomo.latency.unavailable"
    case mihomoSectionSubscription = "mihomo.section.subscription"
    case mihomoSubscriptionLinkLabel = "mihomo.subscription.linkLabel"
    case mihomoSubscriptionPlaceholder = "mihomo.subscription.placeholder"
    case mihomoSubscriptionHidden = "mihomo.subscription.hidden"
    case mihomoSubscriptionReveal = "mihomo.subscription.reveal"
    case mihomoSubscriptionHide = "mihomo.subscription.hide"
    case mihomoSubscriptionUpdate = "mihomo.subscription.update"
    case mihomoSubscriptionLastUpdated = "mihomo.subscription.lastUpdated"
    case mihomoSubscriptionNeverUpdated = "mihomo.subscription.neverUpdated"
    case mihomoSectionServers = "mihomo.section.servers"
    case mihomoSearchPlaceholder = "mihomo.search.placeholder"
    case mihomoSortTitle = "mihomo.sort.title"
    case mihomoSortDefault = "mihomo.sort.default"
    case mihomoSortName = "mihomo.sort.name"
    case mihomoSortLatency = "mihomo.sort.latency"
    case mihomoAutoSelect = "mihomo.autoSelect"
    case mihomoMeasureDelays = "mihomo.measureDelays"
    case mihomoMeasureProgressFormat = "mihomo.measureProgress.format"
    case mihomoEmptyServers = "mihomo.emptyServers"
    case mihomoSectionDetails = "mihomo.section.details"
    case mihomoLocalAddressTitle = "mihomo.localAddress.title"
    case mihomoBackgroundLimitTitle = "mihomo.backgroundLimit.title"
    case mihomoBackgroundLimitBody = "mihomo.backgroundLimit.body"

    // Music Center
    case musicTitle = "music.title"
    case musicTabHome = "music.tab.home"
    case musicTabLibrary = "music.tab.library"
    case musicTabQueue = "music.tab.queue"
    case musicTabSources = "music.tab.sources"
    case musicTabSettings = "music.tab.settings"
    case musicNowPlaying = "music.nowPlaying"
    case musicNothingPlaying = "music.nothingPlaying"
    case musicRecentTracks = "music.recentTracks"
    case musicCollections = "music.collections"
    case musicSourcesTitle = "music.sources.title"
    case musicSourceLocalFiles = "music.source.localFiles"
    case musicSourceBGMix = "music.source.bgMix"
    case musicSourceBGWave = "music.source.bgWave"
    case musicSourceYandex = "music.source.yandex"
    case musicPlaybackSettings = "music.playbackSettings"
    case musicEmptyLibrary = "music.empty.library"
    case musicEmptyQueue = "music.empty.queue"
    case musicAddTracks = "music.addTracks"
    case musicPlay = "music.play"
    case musicPause = "music.pause"
    case musicNext = "music.next"
    case musicPrevious = "music.previous"
    case musicClearQueue = "music.clearQueue"
    case musicRemoveFromQueue = "music.removeFromQueue"
    case musicTrackPreparing = "music.track.preparing"
    case musicTrackReady = "music.track.ready"

    // BG Mix & BG Beat
    case bgMixTitle = "bgMix.title"
    case bgMixCurrentTrack = "bgMix.currentTrack"
    case bgMixNextTrack = "bgMix.nextTrack"
    case bgMixNoNextTrack = "bgMix.noNextTrack"
    case bgMixTransitionActive = "bgMix.transitionActive"
    case bgMixBpmFormat = "bgMix.bpm.format"
    case bgMixSettingsTitle = "bgMix.settings.title"
    case bgMixTransitionDuration = "bgMix.transitionDuration"
    case bgMixTransitionAuto = "bgMix.transitionAuto"
    case bgMixTransitionSecondsFormat = "bgMix.transitionSeconds.format"
    case bgMixAdaptiveTransitions = "bgMix.adaptiveTransitions"
    case bgMixAdaptiveDescription = "bgMix.adaptiveDescription"
    case bgMixBassSwap = "bgMix.bassSwap"
    case bgMixBassSwapDescription = "bgMix.bassSwapDescription"
    case bgMixEmptyTitle = "bgMix.empty.title"
    case bgMixEmptySubtitle = "bgMix.empty.subtitle"
    case bgMixQueueHeader = "bgMix.queue.header"
    case bgMixReorderHint = "bgMix.reorderHint"

    // Yandex Music
    case yandexTitle = "yandex.title"
    case yandexWarningTitle = "yandex.warning.title"
    case yandexWarningBody = "yandex.warning.body"
    case yandexAcceptConsent = "yandex.acceptConsent"
    case yandexRevokeConsent = "yandex.revokeConsent"
    case yandexNotConfiguredTitle = "yandex.notConfigured.title"
    case yandexNotConfiguredBody = "yandex.notConfigured.body"
    case yandexSignIn = "yandex.signIn"
    case yandexSignOut = "yandex.signOut"
    case yandexWaitingTitle = "yandex.waiting.title"
    case yandexCodeLabel = "yandex.codeLabel"
    case yandexCopyCode = "yandex.copyCode"
    case yandexOpenVerification = "yandex.openVerification"
    case yandexCancelSignIn = "yandex.cancelSignIn"
    case yandexRetrySignIn = "yandex.retrySignIn"
    case yandexProfileTitle = "yandex.profile.title"
    case yandexSignedInStatus = "yandex.signedInStatus"
    case yandexSectionFeatures = "yandex.section.features"
    case yandexLibrary = "yandex.library"
    case yandexSearch = "yandex.search"
    case yandexLikes = "yandex.likes"
    case yandexPlaylists = "yandex.playlists"
    case yandexMyWave = "yandex.myWave"
    case yandexLyrics = "yandex.lyrics"
    case yandexFeaturePendingBackend = "yandex.featurePendingBackend"

    // BG Wave
    case bgWaveTitle = "bgWave.title"
    case bgWaveUnavailableTitle = "bgWave.unavailable.title"
    case bgWaveUnavailableBody = "bgWave.unavailable.body"
    case bgWaveCreateWave = "bgWave.createWave"
    case bgWaveJoinByInvite = "bgWave.joinByInvite"
    case bgWaveInvitePlaceholder = "bgWave.invitePlaceholder"
    case bgWaveCheckInvite = "bgWave.checkInvite"
    case bgWaveInviteValid = "bgWave.inviteValid"
    case bgWaveInviteInvalid = "bgWave.inviteInvalid"
    case bgWaveCurrentSession = "bgWave.currentSession"
    case bgWaveSourceInfo = "bgWave.sourceInfo"
    case bgWaveStatusDisconnected = "bgWave.status.disconnected"
    case bgWaveStatusConnecting = "bgWave.status.connecting"
    case bgWaveStatusConnected = "bgWave.status.connected"
    case bgWaveShareWave = "bgWave.shareWave"
    case bgWaveEndSession = "bgWave.endSession"
    case bgWaveReconnect = "bgWave.reconnect"

    // Trigger Words
    case triggerTitle = "trigger.title"
    case triggerEnable = "trigger.enable"
    case triggerSectionScope = "trigger.section.scope"
    case triggerScopeMuted = "trigger.scope.muted"
    case triggerScopeAll = "trigger.scope.all"
    case triggerSectionAdd = "trigger.section.add"
    case triggerInputPlaceholder = "trigger.input.placeholder"
    case triggerModeWholeWord = "trigger.mode.wholeWord"
    case triggerModeAnywhere = "trigger.mode.anywhere"
    case triggerModeRegex = "trigger.mode.regex"
    case triggerAddAction = "trigger.addAction"
    case triggerAddedStatus = "trigger.status.added"
    case triggerDuplicateStatus = "trigger.status.duplicate"
    case triggerEmptyPatternStatus = "trigger.status.empty"
    case triggerTooLongStatus = "trigger.status.tooLong"
    case triggerTooManyStatus = "trigger.status.tooMany"
    case triggerBadRegexStatus = "trigger.status.badRegex"
    case triggerRegexMatchesEmptyStatus = "trigger.status.regexMatchesEmpty"
    case triggerSectionRules = "trigger.section.rules"
    case triggerNoRules = "trigger.noRules"
    case triggerSectionFeed = "trigger.section.feed"
    case triggerFeedTitle = "trigger.feed.title"
    case triggerFeedEmpty = "trigger.feed.empty"
    case triggerClearFeed = "trigger.clearFeed"
    case triggerMatchJump = "trigger.match.jump"

    // Updates
    case updatesTitle = "updates.title"
    case updatesSectionCurrent = "updates.section.current"
    case updatesVersion = "updates.version"
    case updatesBuild = "updates.build"
    case updatesChannel = "updates.channel"
    case updatesChannelDev = "updates.channel.dev"
    case updatesChannelRelease = "updates.channel.release"
    case updatesCommit = "updates.commit"
    case updatesCheckButton = "updates.checkButton"
    case updatesChecking = "updates.checking"
    case updatesUpToDate = "updates.upToDate"
    case updatesAvailableTitle = "updates.available.title"
    case updatesAvailableVersion = "updates.available.version"
    case updatesChangelog = "updates.changelog"
    case updatesOpenRelease = "updates.openRelease"
    case updatesManualNote = "updates.manualNote"
    case updatesErrorPrefix = "updates.errorPrefix"

    // Diagnostics
    case diagnosticsTitle = "diagnostics.title"
    case diagnosticsInstructions = "diagnostics.instructions"
    case diagnosticsDescriptionPlaceholder = "diagnostics.description.placeholder"
    case diagnosticsNoncePlaceholder = "diagnostics.nonce.placeholder"
    case diagnosticsSendButton = "diagnostics.sendButton"
    case diagnosticsPreviewTitle = "diagnostics.preview.title"
    case diagnosticsPreviewBody = "diagnostics.preview.body"
    case diagnosticsStageAwaitingNonce = "diagnostics.stage.awaitingNonce"
    case diagnosticsStageUploading = "diagnostics.stage.uploading"
    case diagnosticsStageDelivered = "diagnostics.stage.delivered"
    case diagnosticsStageError = "diagnostics.stage.error"
    case diagnosticsPrivacyNote = "diagnostics.privacyNote"

    // Chat Export
    case exportTitle = "export.title"
    case exportSectionFormat = "export.section.format"
    case exportFormatJson = "export.format.json"
    case exportFormatHtml = "export.format.html"
    case exportSectionOptions = "export.section.options"
    case exportChooseFolder = "export.chooseFolder"
    case exportCancel = "export.cancel"
    case exportProgress = "export.progress"
    case exportCompleted = "export.completed"
    case exportCancelled = "export.cancelled"
    case exportProtectedNotice = "export.protectedNotice"

    // BG Push
    case pushTitle = "push.title"
    case pushEnable = "push.enable"
    case pushStatusRegistered = "push.status.registered"
    case pushStatusPending = "push.status.pending"
    case pushStatusInactive = "push.status.inactive"
    case pushStatusError = "push.status.error"
    case pushSetupStepsTitle = "push.setupSteps.title"
    case pushStep1 = "push.step1"
    case pushStep2 = "push.step2"
    case pushStep3 = "push.step3"
    case pushOpenPwa = "push.openPwa"
    case pushCheckNotifications = "push.checkNotifications"
    case pushNotificationsAllowed = "push.notifications.allowed"
    case pushNotificationsDenied = "push.notifications.denied"
    case pushDisconnect = "push.disconnect"
}

/// Pluralized localization keys for counts and units.
public enum BeyGramPluralKey: String, CaseIterable {
    case serversCount = "plural.servers"
    case tracksCount = "plural.tracks"
    case rulesCount = "plural.rules"
    case matchesCount = "plural.matches"
    case secondsShort = "plural.secondsShort"
    case secondsFull = "plural.secondsFull"
    case minutesFull = "plural.minutesFull"
}

/// Unified BeyGram localization engine synchronized with Telegram's selected language.
///
/// Language resolution never reads iOS system locale directly: it uses the language code
/// provided by Telegram's `PresentationStrings` (or the cached active language code updated
/// whenever `PresentationData` changes).
public final class BeyGramL10n {
    public static let shared = BeyGramL10n()

    public static let supportedLanguages: [String] = ["en", "ru"]
    public static let fallbackLanguage: String = "en"

    private let lock = NSLock()
    private var activeLanguageCode: String = BeyGramL10n.fallbackLanguage

    private init() {}

    /// Updates the active Telegram language code (called automatically by `PresentationData`).
    public func setLanguageCode(_ languageCode: String?) {
        // The Android-shared tables follow the same Telegram language (the native language screen), with their own fallback.
        BeyGramAndroidStrings.shared.setLanguageCode(languageCode)
        let normalized = BeyGramL10n.normalizeLanguageCode(languageCode)
        self.lock.lock()
        self.activeLanguageCode = normalized
        self.lock.unlock()
    }

    /// Returns the currently active normalized language code (e.g. `"ru"` or `"en"`).
    public var currentLanguageCode: String {
        self.lock.lock()
        let code = self.activeLanguageCode
        self.lock.unlock()
        return code
    }

    /// Normalizes a Telegram or BCP-47 language code to a supported BeyGram language key.
    public static func normalizeLanguageCode(_ languageCode: String?) -> String {
        guard let raw = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return BeyGramL10n.fallbackLanguage
        }
        let base = raw.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? raw
        if BeyGramL10n.supportedLanguages.contains(base) {
            return base
        }
        return BeyGramL10n.fallbackLanguage
    }

    /// Resolves a localized string for the given key and optional Telegram language code.
    public func string(_ key: BeyGramStringKey, languageCode: String? = nil) -> String {
        let lang = languageCode.map(BeyGramL10n.normalizeLanguageCode) ?? self.currentLanguageCode
        if let table = BeyGramLocalizationTables.strings[lang], let value = table[key] {
            return value
        }
        return BeyGramLocalizationTables.strings[BeyGramL10n.fallbackLanguage]?[key] ?? key.rawValue
    }

    /// Formats a localized string using positional arguments (`%@`, `%d`, etc.).
    public func format(_ key: BeyGramStringKey, languageCode: String? = nil, _ arguments: CVarArg...) -> String {
        let template = self.string(key, languageCode: languageCode)
        return String(format: template, arguments: arguments)
    }

    /// Resolves a pluralized localized string for `count` using CLDR rules for `languageCode`.
    public func plural(_ key: BeyGramPluralKey, count: Int, languageCode: String? = nil) -> String {
        let lang = languageCode.map(BeyGramL10n.normalizeLanguageCode) ?? self.currentLanguageCode
        let category = BeyGramL10n.pluralCategory(for: count, languageCode: lang)
        let template = BeyGramLocalizationTables.plurals[lang]?[key]?[category]
            ?? BeyGramLocalizationTables.plurals[lang]?[key]?[.other]
            ?? BeyGramLocalizationTables.plurals[BeyGramL10n.fallbackLanguage]?[key]?[category]
            ?? BeyGramLocalizationTables.plurals[BeyGramL10n.fallbackLanguage]?[key]?[.other]
            ?? "%d"
        return String(format: template, count)
    }

    /// CLDR plural category for a given integer and normalized language code.
    public static func pluralCategory(for count: Int, languageCode: String) -> BeyGramPluralCategory {
        let n = abs(count)
        switch languageCode {
        case "ru":
            let mod10 = n % 10
            let mod100 = n % 100
            if mod10 == 1 && mod100 != 11 {
                return .one
            }
            if (2...4).contains(mod10) && !(12...14).contains(mod100) {
                return .few
            }
            return .many
        default:
            return n == 1 ? .one : .other
        }
    }

    /// Formats a network latency in milliseconds (or returns localized unavailable text if `< 0`).
    public func formatLatency(_ milliseconds: Int, languageCode: String? = nil) -> String {
        if milliseconds < 0 {
            return self.string(.mihomoLatencyUnavailable, languageCode: languageCode)
        }
        let lang = languageCode.map(BeyGramL10n.normalizeLanguageCode) ?? self.currentLanguageCode
        return lang == "ru" ? "\(milliseconds) мс" : "\(milliseconds) ms"
    }

    /// Formats a playback duration as `MM:SS` or `H:MM:SS`.
    public func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Formats a byte count using localized units (B, KB, MB, GB).
    public func formatDataSize(_ bytes: Int64, languageCode: String? = nil) -> String {
        let lang = languageCode.map(BeyGramL10n.normalizeLanguageCode) ?? self.currentLanguageCode
        let isRu = lang == "ru"
        let units = isRu ? ["Б", "КБ", "МБ", "ГБ"] : ["B", "KB", "MB", "GB"]
        if bytes < 1024 {
            return "\(bytes) \(units[0])"
        }
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }
        let formatted = String(format: "%.1f", value)
        let localizedNumber = isRu ? formatted.replacingOccurrences(of: ".", with: ",") : formatted
        return "\(localizedNumber) \(units[unitIndex])"
    }
}
