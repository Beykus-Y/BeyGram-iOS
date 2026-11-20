import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UniformTypeIdentifiers
import BeyGramChatExport
import BeyGramChatExportTelegram
import BeyGramKit

private final class ChatExportRun {
    var format: ChatExportFormat = .json
    var status: String?
    var isRunning = false
    var task: Task<Void, Never>?
    var fileURL: URL?
    var handle: FileHandle?
    var folderURL: URL?
}

private final class ChatExportArguments {
    let setFormat: (ChatExportFormat) -> Void
    let chooseFolder: () -> Void
    let cancel: () -> Void

    init(setFormat: @escaping (ChatExportFormat) -> Void, chooseFolder: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.setFormat = setFormat
        self.chooseFolder = chooseFolder
        self.cancel = cancel
    }
}

private enum ChatExportSection: Int32 {
    case format
    case run
}

private enum ChatExportEntry: ItemListNodeEntry, Equatable {
    case formatHeader(PresentationTheme, String)
    case json(PresentationTheme, String, Bool)
    case html(PresentationTheme, String, Bool)
    case chooseFolder(PresentationTheme, String, Bool)
    case notice(PresentationTheme, String)
    case status(PresentationTheme, String)
    case cancel(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .formatHeader, .json, .html: return ChatExportSection.format.rawValue
        case .chooseFolder, .notice, .status, .cancel: return ChatExportSection.run.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .formatHeader: return 0
        case .json: return 1
        case .html: return 2
        case .chooseFolder: return 10
        case .notice: return 11
        case .status: return 12
        case .cancel: return 13
        }
    }

    static func == (lhs: ChatExportEntry, rhs: ChatExportEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.formatHeader(lt, lText), .formatHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.json(lt, lTitle, lSel), .json(rt, rTitle, rSel)):
            return lt === rt && lTitle == rTitle && lSel == rSel
        case let (.html(lt, lTitle, lSel), .html(rt, rTitle, rSel)):
            return lt === rt && lTitle == rTitle && lSel == rSel
        case let (.chooseFolder(lt, lTitle, lEnabled), .chooseFolder(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.notice(lt, lText), .notice(rt, rText)):
            return lt === rt && lText == rText
        case let (.status(lt, lText), .status(rt, rText)):
            return lt === rt && lText == rText
        case let (.cancel(lt, lTitle), .cancel(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        default:
            return false
        }
    }

    static func < (lhs: ChatExportEntry, rhs: ChatExportEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ChatExportArguments
        switch self {
        case let .formatHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .json(_, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setFormat(.json)
            })
        case let .html(_, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setFormat(.html)
            })
        case let .chooseFolder(_, title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled { arguments.chooseFolder() }
            })
        case let .notice(_, text), let .status(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .cancel(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.cancel)
        }
    }
}

private final class FolderPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void

    init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            self.onPick(url)
        }
    }
}

/// Export screen for one chat using unified BeyGram localization.
public func chatExportController(context: AccountContext, peerId: EnginePeer.Id, chatTitle: String, accountLabel: String, hasProtectedContent: Bool) -> ViewController {
    let run = ChatExportRun()
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let bump: () -> Void = {
        counter += 1
        revision.set(counter)
    }
    var presentPicker: ((UIDocumentPickerViewController) -> Void)?
    var folderDelegate: FolderPickerDelegate?

    func currentLang() -> String {
        return context.sharedContext.currentPresentationData.with { $0 }.strings.primaryComponent.languageCode
    }

    func finishRun(message: String?) {
        run.isRunning = false
        run.status = message
        run.task = nil
        try? run.handle?.close()
        run.handle = nil
        run.folderURL?.stopAccessingSecurityScopedResource()
        run.folderURL = nil
        bump()
    }

    func startExport(folder: URL) {
        let lang = currentLang()
        let l10n = BeyGramL10n.shared
        let accessed = folder.startAccessingSecurityScopedResource()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let ext = run.format == .json ? "json" : "html"
        let fileURL = folder.appendingPathComponent("BeyGram-chat-\(stamp).\(ext)")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            if accessed { folder.stopAccessingSecurityScopedResource() }
            run.status = l10n.string(.commonError, languageCode: lang)
            bump()
            return
        }
        run.folderURL = accessed ? folder : nil
        run.fileURL = fileURL
        run.handle = handle
        run.isRunning = true
        run.status = l10n.format(.exportProgress, languageCode: lang, 0)
        bump()

        let cleanup: () -> Void = {
            try? handle.truncate(atOffset: 0)
            try? handle.close()
            try? FileManager.default.removeItem(at: fileURL)
        }
        run.task = Task { @MainActor in
            do {
                let summary = try await runChatExport(
                    context: context,
                    peerId: peerId,
                    chatTitle: chatTitle,
                    accountLabel: accountLabel,
                    hasProtectedContent: hasProtectedContent,
                    format: run.format,
                    range: ChatExportRange(),
                    sink: ChatExportFileHandleSink(handle: handle),
                    cleanup: cleanup,
                    onProgress: { progress in
                        run.status = l10n.format(.exportProgress, languageCode: lang, progress.exportedMessages)
                        bump()
                    }
                )
                let details = "\(summary.exportedMessages)"
                finishRun(message: l10n.format(.exportCompleted, languageCode: lang, details))
            } catch is CancellationError {
                finishRun(message: l10n.string(.exportCancelled, languageCode: lang))
            } catch {
                finishRun(message: l10n.string(.commonError, languageCode: lang))
            }
        }
    }

    let arguments = ChatExportArguments(
        setFormat: { format in
            run.format = format
            bump()
        },
        chooseFolder: {
            let delegate = FolderPickerDelegate { url in
                startExport(folder: url)
            }
            folderDelegate = delegate
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
            picker.delegate = delegate
            presentPicker?(picker)
        },
        cancel: {
            run.task?.cancel()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let theme = presentationData.theme
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(l10n.string(.exportTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        var entries: [ChatExportEntry] = [
            .formatHeader(theme, l10n.string(.exportSectionFormat, languageCode: lang).uppercased()),
            .json(theme, l10n.string(.exportFormatJson, languageCode: lang), run.format == .json),
            .html(theme, l10n.string(.exportFormatHtml, languageCode: lang), run.format == .html),
            .chooseFolder(theme, l10n.string(.exportChooseFolder, languageCode: lang), !run.isRunning),
            .notice(theme, l10n.string(.exportProtectedNotice, languageCode: lang))
        ]
        if let status = run.status {
            entries.append(.status(theme, status))
        }
        if run.isRunning {
            entries.append(.cancel(theme, l10n.string(.exportCancel, languageCode: lang)))
        }
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentPicker = { [weak controller] picker in
        controller?.present(picker, animated: true, completion: nil)
    }
    _ = folderDelegate
    return controller
}
