import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramAppearance
import BeyGramKit
import BeyGramMusicUI
import BeyGramTriggerWordsUI
import BeyGramUpdatesUI
import BeyGramReportUI

private final class BeyGramSettingsArguments {
    let openPrivacy: () -> Void
    let openMusic: () -> Void
    let openMihomo: () -> Void
    let openTriggerWords: () -> Void
    let openBgPush: () -> Void
    let openAppearance: () -> Void
    let openDiagnostics: () -> Void
    let openUpdates: () -> Void
    let openAbout: () -> Void

    init(
        openPrivacy: @escaping () -> Void,
        openMusic: @escaping () -> Void,
        openMihomo: @escaping () -> Void,
        openTriggerWords: @escaping () -> Void,
        openBgPush: @escaping () -> Void,
        openAppearance: @escaping () -> Void,
        openDiagnostics: @escaping () -> Void,
        openUpdates: @escaping () -> Void,
        openAbout: @escaping () -> Void
    ) {
        self.openPrivacy = openPrivacy
        self.openMusic = openMusic
        self.openMihomo = openMihomo
        self.openTriggerWords = openTriggerWords
        self.openBgPush = openBgPush
        self.openAppearance = openAppearance
        self.openDiagnostics = openDiagnostics
        self.openUpdates = openUpdates
        self.openAbout = openAbout
    }
}

private enum BeyGramSettingsSection: Int32 {
    case features
    case interface
    case maintenance
}

private enum BeyGramSettingsEntry: ItemListNodeEntry {
    case privacy(PresentationTheme, String, String)
    case music(PresentationTheme, String)
    case mihomo(PresentationTheme, String, String)
    case triggerWords(PresentationTheme, String, String)
    case bgPush(PresentationTheme, String, String)
    case appearance(PresentationTheme, String, String)
    case diagnostics(PresentationTheme, String)
    case updates(PresentationTheme, String, String)
    case about(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .privacy, .music, .mihomo, .triggerWords, .bgPush:
            return BeyGramSettingsSection.features.rawValue
        case .appearance:
            return BeyGramSettingsSection.interface.rawValue
        case .diagnostics, .updates, .about:
            return BeyGramSettingsSection.maintenance.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .privacy: return 0
        case .music: return 1
        case .mihomo: return 2
        case .triggerWords: return 3
        case .bgPush: return 4
        case .appearance: return 5
        case .diagnostics: return 6
        case .updates: return 7
        case .about: return 8
        }
    }

    static func == (lhs: BeyGramSettingsEntry, rhs: BeyGramSettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.privacy(lt, lTitle, lLabel), .privacy(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.music(lt, lTitle), .music(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.mihomo(lt, lTitle, lLabel), .mihomo(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.triggerWords(lt, lTitle, lLabel), .triggerWords(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.bgPush(lt, lTitle, lLabel), .bgPush(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.appearance(lt, lTitle, lLabel), .appearance(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.diagnostics(lt, lTitle), .diagnostics(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.updates(lt, lTitle, lLabel), .updates(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.about(lt, lTitle), .about(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        default:
            return false
        }
    }

    static func < (lhs: BeyGramSettingsEntry, rhs: BeyGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramSettingsArguments
        switch self {
        case let .privacy(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.security,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openPrivacy
            )
        case let .music(_, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.music,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: arguments.openMusic
            )
        case let .mihomo(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.proxy,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openMihomo
            )
        case let .triggerWords(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.messages,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openTriggerWords
            )
        case let .bgPush(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.notifications,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openBgPush
            )
        case let .appearance(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.appearance,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openAppearance
            )
        case let .diagnostics(_, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.stats,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: arguments.openDiagnostics
            )
        case let .updates(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.download,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openUpdates
            )
        case let .about(_, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.faq,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: arguments.openAbout
            )
        }
    }
}

private func beyGramSettingsEntries(presentationData: PresentationData) -> [BeyGramSettingsEntry] {
    let lang = presentationData.strings.primaryComponent.languageCode
    let l10n = BeyGramL10n.shared
    let theme = presentationData.theme

    let privacyLabel = BeyGramSettings.shared.isEnabled(.privacyPolicy)
        ? l10n.string(.commonOn, languageCode: lang)
        : l10n.string(.commonOff, languageCode: lang)

    let mihomoState = BeyGramMihomoRuntime.shared.controller.currentState
    let mihomoLabel = mihomoState.isRunning
        ? l10n.string(.mihomoStatusConnected, languageCode: lang)
        : l10n.string(.mihomoStatusDisconnected, languageCode: lang)

    let triggerLabel = BeyGramSettings.shared.isEnabled(.triggerWords)
        ? l10n.string(.commonOn, languageCode: lang)
        : l10n.string(.commonOff, languageCode: lang)

    let pushLabel = BeyGramSettings.shared.isEnabled(.bgPush)
        ? l10n.string(.commonOn, languageCode: lang)
        : l10n.string(.commonOff, languageCode: lang)

    let styleLabel = BeyGramAppearance.shared.isEnabled
        ? l10n.string(.appearanceStyleBeyGram, languageCode: lang)
        : l10n.string(.appearanceStyleTelegram, languageCode: lang)

    let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    let versionLabel = buildNumber.isEmpty ? shortVersion : "\(shortVersion) (\(buildNumber))"

    return [
        .privacy(theme, l10n.string(.settingsPrivacyTitle, languageCode: lang), privacyLabel),
        .music(theme, l10n.string(.settingsMusicTitle, languageCode: lang)),
        .mihomo(theme, l10n.string(.settingsMihomoTitle, languageCode: lang), mihomoLabel),
        .triggerWords(theme, l10n.string(.settingsTriggerWordsTitle, languageCode: lang), triggerLabel),
        .bgPush(theme, l10n.string(.settingsBgPushTitle, languageCode: lang), pushLabel),
        .appearance(theme, l10n.string(.settingsAppearanceTitle, languageCode: lang), styleLabel),
        .diagnostics(theme, l10n.string(.settingsDiagnosticsTitle, languageCode: lang)),
        .updates(theme, l10n.string(.settingsUpdatesTitle, languageCode: lang), versionLabel),
        .about(theme, l10n.string(.settingsAboutTitle, languageCode: lang))
    ]
}

/// Unified BeyGram Settings hub controller.
public func beyGramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let refreshPromise = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshCounter = 0
    let triggerRefresh: () -> Void = {
        refreshCounter += 1
        refreshPromise.set(refreshCounter)
    }

    let arguments = BeyGramSettingsArguments(
        openPrivacy: {
            pushControllerImpl?(beyGramPrivacyController(context: context))
        },
        openMusic: {
            pushControllerImpl?(beyGramMusicSettingsController(context: context))
        },
        openMihomo: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            pushControllerImpl?(beyGramMihomoController(
                accountManager: context.sharedContext.accountManager,
                presentationData: presentationData,
                updatedPresentationData: context.sharedContext.presentationData
            ))
        },
        openTriggerWords: {
            pushControllerImpl?(triggerWordsSettingsController(context: context))
        },
        openBgPush: {
            pushControllerImpl?(beyGramPushController(context: context))
        },
        openAppearance: {
            pushControllerImpl?(beyGramStyleController(context: context))
        },
        openDiagnostics: {
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            pushControllerImpl?(reportController(context: context, appVersion: appVersion))
        },
        openUpdates: {
            pushControllerImpl?(beyGramUpdatesController(context: context))
        },
        openAbout: {
            pushControllerImpl?(beyGramAboutController(context: context))
        }
    )

    let settingsChanged = NotificationCenter.default.addObserver(forName: BeyGramSettings.didChangeNotification, object: nil, queue: .main) { _ in
        triggerRefresh()
    }

    let signal = combineLatest(
        context.sharedContext.presentationData,
        BeyGramAppearance.shared.styleSignal,
        refreshPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let title = BeyGramL10n.shared.string(.settingsHubTitle, languageCode: lang)
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: beyGramSettingsEntries(presentationData: presentationData),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        triggerRefresh()
    }
    pushControllerImpl = { [weak controller] next in
        controller?.push(next)
    }
    _ = settingsChanged
    return controller
}

private enum BeyGramAboutEntry: ItemListNodeEntry {
    case header(PresentationTheme, String)
    case row(Int32, PresentationTheme, String, String)
    case footer(PresentationTheme, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .row(id, _, _, _): return id
        case .footer: return 100
        }
    }

    static func == (lhs: BeyGramAboutEntry, rhs: BeyGramAboutEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lt, lText), .header(rt, rText)):
            return lt === rt && lText == rText
        case let (.row(lId, lt, lTitle, lValue), .row(rId, rt, rTitle, rValue)):
            return lId == rId && lt === rt && lTitle == rTitle && lValue == rValue
        case let (.footer(lt, lText), .footer(rt, rText)):
            return lt === rt && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: BeyGramAboutEntry, rhs: BeyGramAboutEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .row(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// About BeyGram screen showing version, build number, channel, and commit SHA if present.
public func beyGramAboutController(context: AccountContext) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let theme = presentationData.theme
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let channelRaw = (info["BeyGramBuildChannel"] as? String)?.lowercased()
        let isDev = channelRaw == "dev" || (info["CFBundleIdentifier"] as? String)?.lowercased().contains("dev") == true
        let channel = isDev
            ? l10n.string(.updatesChannelDev, languageCode: lang)
            : l10n.string(.updatesChannelRelease, languageCode: lang)
        let commitSha = (info["BeyGramGitCommit"] as? String) ?? (info["GitCommit"] as? String)

        var entries: [BeyGramAboutEntry] = [
            .header(theme, l10n.string(.settingsAboutSectionInfo, languageCode: lang)),
            .row(1, theme, l10n.string(.settingsAboutVersion, languageCode: lang), version),
            .row(2, theme, l10n.string(.settingsAboutBuild, languageCode: lang), build),
            .row(3, theme, l10n.string(.settingsAboutChannel, languageCode: lang), channel)
        ]
        if let sha = commitSha, !sha.isEmpty {
            entries.append(.row(4, theme, l10n.string(.settingsAboutCommit, languageCode: lang), String(sha.prefix(8))))
        }
        entries.append(.footer(theme, l10n.string(.settingsAboutFooter, languageCode: lang)))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(l10n.string(.settingsAboutTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, ()))
    }
    return ItemListController(context: context, state: signal)
}
