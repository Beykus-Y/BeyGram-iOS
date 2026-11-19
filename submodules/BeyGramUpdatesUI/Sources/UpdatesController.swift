import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
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

private enum UpdatesEntry: ItemListNodeEntry, Equatable {
    case explanation
    case check(Bool)
    case status(String)
    case release(URL)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int64 {
        switch self {
        case .explanation: return 0
        case .check: return 1
        case .status: return 2
        case .release: return 3
        }
    }

    static func < (lhs: UpdatesEntry, rhs: UpdatesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UpdatesArguments
        switch self {
        case .explanation:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Updates are checked only when you tap the button. BeyGram does not download or install anything in the background. On iOS, open the release page to get the new version."), sectionId: self.section)
        case let .check(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Check for updates", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.check()
            })
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .release(url):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Open release page", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openRelease(url)
            })
        }
    }
}

/// Manual update screen. Installed build number comes from the bundle's CFBundleVersion.
public func beyGramUpdatesController(context: AccountContext) -> ViewController {
    let state = UpdatesState()
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let bump: () -> Void = {
        counter += 1
        revision.set(counter)
    }
    let installedBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0

    let arguments = UpdatesArguments(check: {
        guard !state.isChecking else {
            return
        }
        state.isChecking = true
        state.result = nil
        bump()
        Task { @MainActor in
            state.result = await UpdateCheck.check(installedVersionCode: installedBuild)
            state.isChecking = false
            bump()
        }
    }, openRelease: { url in
        context.sharedContext.applicationBindings.openUrl(url.absoluteString)
    })

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
        |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Updates"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
            var entries: [UpdatesEntry] = [.explanation, .check(!state.isChecking)]
            if state.isChecking {
                entries.append(.status("Checking…"))
            } else {
                switch state.result {
                case nil:
                    break
                case .upToDate?:
                    entries.append(.status("BeyGram is up to date."))
                case let .available(versionName, releaseURL)?:
                    entries.append(.status("New version \(versionName) is available."))
                    entries.append(.release(releaseURL))
                case .failed?:
                    entries.append(.status("Could not check for updates. Try again later."))
                }
            }
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
            return (controllerState, (listState, arguments))
        }

    return ItemListController(context: context, state: signal)
}
