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

/// Holds the export run. The file goes straight into the folder the user chose: no temporary copy.
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
    case json(Bool)
    case html(Bool)
    case chooseFolder(Bool)
    case status(String)
    case cancel

    var section: ItemListSectionId {
        switch self {
        case .json, .html: return ChatExportSection.format.rawValue
        case .chooseFolder, .status, .cancel: return ChatExportSection.run.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .json: return 0
        case .html: return 1
        case .chooseFolder: return 2
        case .status: return 3
        case .cancel: return 4
        }
    }

    static func < (lhs: ChatExportEntry, rhs: ChatExportEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ChatExportArguments
        switch self {
        case let .json(selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "JSON", style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setFormat(.json)
            })
        case let .html(selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "HTML", style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setFormat(.html)
            })
        case let .chooseFolder(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Choose folder and export", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.chooseFolder()
            })
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .cancel:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Cancel export", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.cancel()
            })
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

/// Export screen for one chat. Opens a folder picker, writes `<chat>-<date>.<ext>` into the chosen folder,
/// and shows progress with a cancel action. On failure or cancel the file is removed; if removal fails it is truncated.
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
        let accessed = folder.startAccessingSecurityScopedResource()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let ext = run.format == .json ? "json" : "html"
        let fileURL = folder.appendingPathComponent("BeyGram-chat-\(stamp).\(ext)")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            if accessed { folder.stopAccessingSecurityScopedResource() }
            run.status = "Could not create the file in the folder."
            bump()
            return
        }
        run.folderURL = accessed ? folder : nil
        run.fileURL = fileURL
        run.handle = handle
        run.isRunning = true
        run.status = "Exporting…"
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
                        run.status = "Exported \(progress.exportedMessages) messages. Keep BeyGram open until this finishes."
                        bump()
                    }
                )
                finishRun(message: "Done: \(summary.exportedMessages) messages. Skipped (saving not allowed): \(summary.skippedNotSaveable).")
            } catch is CancellationError {
                finishRun(message: "Cancelled. The file was removed.")
            } catch {
                finishRun(message: "Export failed. The file was removed.")
            }
        }
    }

    let arguments = ChatExportArguments(setFormat: { format in
        run.format = format
        bump()
    }, chooseFolder: {
        let delegate = FolderPickerDelegate { url in
            startExport(folder: url)
        }
        folderDelegate = delegate
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = delegate
        presentPicker?(picker)
    }, cancel: {
        run.task?.cancel()
    })

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
        |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Export chat"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
            var entries: [ChatExportEntry] = [
                .json(run.format == .json),
                .html(run.format == .html)
            ]
            entries.append(.chooseFolder(!run.isRunning))
            if let status = run.status {
                entries.append(.status(status))
            }
            if run.isRunning {
                entries.append(.cancel)
            }
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
            return (controllerState, (listState, arguments))
        }

    let controller = ItemListController(context: context, state: signal)
    presentPicker = { [weak controller] picker in
        controller?.present(picker, animated: true, completion: nil)
    }
    _ = folderDelegate
    return controller
}
