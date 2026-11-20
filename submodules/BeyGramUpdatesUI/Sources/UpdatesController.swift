import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit
import BeyGramUpdates

private final class UpdatesState {
    var isChecking = false
    var result: UpdateCheckResult?
}

private final class UpdatesArguments {
    let check: () -> Void
    let openRelease: (URL) -> Void

    init(check: @escaping () -> Void, openRelease: @escaping (URL) -> Void) {
        self.check = check
        self.openRelease = openRelease
    }
}

private enum UpdatesSection: Int32 {
    case current
    case check
    case available
}

private enum UpdatesEntry: ItemListNodeEntry, Equatable {
    case currentHeader(PresentationTheme, String)
    case infoRow(Int32, PresentationTheme, String, String)
    case explanation(PresentationTheme, String)
    case check(PresentationTheme, String, Bool)
    case status(PresentationTheme, String)
    case availableHeader(PresentationTheme, String)
    case availableVersion(PresentationTheme, String)
    case release(PresentationTheme, String, URL)

    var section: ItemListSectionId {
        switch self {
        case .currentHeader, .infoRow:
            return UpdatesSection.current.rawValue
        case .explanation, .check, .status:
            return UpdatesSection.check.rawValue
        case .availableHeader, .availableVersion, .release:
            return UpdatesSection.available.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .currentHeader: return 0
        case let .infoRow(id, _, _, _): return Int64(id)
        case .explanation: return 10
        case .check: return 11
        case .status: return 12
        case .availableHeader: return 20
        case .availableVersion: return 21
        case .release: return 22
        }
    }

    static func == (lhs: UpdatesEntry, rhs: UpdatesEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.currentHeader(lt, lText), .currentHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.infoRow(lId, lt, lTitle, lVal), .infoRow(rId, rt, rTitle, rVal)):
            return lId == rId && lt === rt && lTitle == rTitle && lVal == rVal
        case let (.explanation(lt, lText), .explanation(rt, rText)):
            return lt === rt && lText == rText
        case let (.check(lt, lTitle, lEnabled), .check(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.status(lt, lText), .status(rt, rText)):
            return lt === rt && lText == rText
        case let (.availableHeader(lt, lText), .availableHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.availableVersion(lt, lText), .availableVersion(rt, rText)):
            return lt === rt && lText == rText
        case let (.release(lt, lTitle, lUrl), .release(rt, rTitle, rUrl)):
            return lt === rt && lTitle == rTitle && lUrl == rUrl
        default:
            return false
        }
    }

    static func < (lhs: UpdatesEntry, rhs: UpdatesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UpdatesArguments
        switch self {
        case let .currentHeader(_, text), let .availableHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .infoRow(_, _, title, value):
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
        case let .explanation(_, text), let .status(_, text), let .availableVersion(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .check(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.check() }
                }
            )
        case let .release(_, title, url):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openRelease(url)
                }
            )
        }
    }
}

/// Manual update screen showing installed version/build/channel and checking GitHub Releases.
public func beyGramUpdatesController(context: AccountContext) -> ViewController {
    let state = UpdatesState()
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let bump: () -> Void = {
        counter += 1
        revision.set(counter)
    }
    let info = Bundle.main.infoDictionary ?? [:]
    let installedBuild = Int(info["CFBundleVersion"] as? String ?? "") ?? 0
    let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.0.1"
    let channelRaw = (info["BeyGramBuildChannel"] as? String)?.lowercased()
    let isDev = channelRaw == "dev" || (info["CFBundleIdentifier"] as? String)?.lowercased().contains("dev") == true
    let channel: UpdateChannel = isDev ? .dev : .release
    let commitSha = (info["BeyGramGitCommit"] as? String) ?? (info["GitCommit"] as? String)

    let arguments = UpdatesArguments(
        check: {
            guard !state.isChecking else { return }
            state.isChecking = true
            state.result = nil
            bump()
            Task { @MainActor in
                state.result = await UpdateCheck.check(
                    installedVersionName: shortVersion,
                    installedBuildNumber: installedBuild,
                    channel: channel
                )
                state.isChecking = false
                bump()
            }
        },
        openRelease: { url in
            context.sharedContext.applicationBindings.openUrl(url.absoluteString)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let theme = presentationData.theme

        var entries: [UpdatesEntry] = [
            .currentHeader(theme, l10n.string(.updatesSectionCurrent, languageCode: lang).uppercased()),
            .infoRow(1, theme, l10n.string(.updatesVersion, languageCode: lang), shortVersion),
            .infoRow(2, theme, l10n.string(.updatesBuild, languageCode: lang), "\(installedBuild)"),
            .infoRow(3, theme, l10n.string(.updatesChannel, languageCode: lang), isDev ? l10n.string(.updatesChannelDev, languageCode: lang) : l10n.string(.updatesChannelRelease, languageCode: lang))
        ]
        if isDev, let sha = commitSha, !sha.isEmpty {
            entries.append(.infoRow(4, theme, l10n.string(.updatesCommit, languageCode: lang), String(sha.prefix(8))))
        }

        let checkTitle = state.isChecking
            ? l10n.string(.updatesChecking, languageCode: lang)
            : l10n.string(.updatesCheckButton, languageCode: lang)
        entries.append(.check(theme, checkTitle, !state.isChecking))
        entries.append(.explanation(theme, l10n.string(.updatesManualNote, languageCode: lang)))

        if !state.isChecking {
            switch state.result {
            case nil:
                break
            case .upToDate?, .noReleases?:
                entries.append(.status(theme, l10n.string(.updatesUpToDate, languageCode: lang)))
            case let .available(updateInfo)?:
                entries.append(.availableHeader(theme, l10n.string(.updatesAvailableTitle, languageCode: lang).uppercased()))
                var versionSummary = l10n.format(.updatesAvailableVersion, languageCode: lang, "\(updateInfo.versionName) (\(updateInfo.buildNumber))")
                if let sha = updateInfo.commitSha, !sha.isEmpty {
                    versionSummary += " · \(String(sha.prefix(8)))"
                }
                if let changelog = updateInfo.changelog, !changelog.isEmpty {
                    versionSummary += "\n\n\(changelog)"
                }
                entries.append(.availableVersion(theme, versionSummary))
                entries.append(.release(theme, l10n.string(.updatesOpenRelease, languageCode: lang), updateInfo.releaseURL))
            case .failed?:
                entries.append(.status(theme, l10n.format(.updatesErrorPrefix, languageCode: lang, l10n.string(.commonError, languageCode: lang))))
            }
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(l10n.string(.updatesTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
