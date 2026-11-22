import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import UniformTypeIdentifiers
import BeyGramChatExport
import BeyGramChatExportTelegram
import BeyGramDesign
import BeyGramKit

private final class ChatExportViewControllerImpl: BeyGramScrollViewController, UIDocumentPickerDelegate {
    private let peerId: EnginePeer.Id
    private let chatTitle: String
    private let accountLabel: String
    private let hasProtectedContent: Bool

    private var format: ChatExportFormat = .json
    private var status: String?
    private var isRunning = false
    private var exportTask: Task<Void, Never>?
    private var handle: FileHandle?
    private var folderURL: URL?

    private let headerCard = BeyGramCardView(spacing: 8)
    private let chatTitleLabel = BeyGramTypography.makeLabel(style: .headline, weight: .semibold, lines: 2)
    private let noticeLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)

    private let formatHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let formatCard = BeyGramCardView(spacing: 10)
    private let formatControl = UISegmentedControl(items: ["JSON", "HTML"])

    private let actionCard = BeyGramCardView(spacing: 10)
    private let exportButton = BeyGramActionButton(style: .primary)
    private let cancelButton = BeyGramActionButton(style: .destructive)
    private let statusLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .medium, lines: 0)

    init(context: AccountContext, peerId: EnginePeer.Id, chatTitle: String, accountLabel: String, hasProtectedContent: Bool) {
        self.peerId = peerId
        self.chatTitle = chatTitle
        self.accountLabel = accountLabel
        self.hasProtectedContent = hasProtectedContent
        super.init(context: context)
    }

    deinit {
        self.exportTask?.cancel()
        try? self.handle?.close()
        self.folderURL?.stopAccessingSecurityScopedResource()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.headerCard.contentStack.addArrangedSubview(self.chatTitleLabel)
        self.headerCard.contentStack.addArrangedSubview(self.noticeLabel)
        self.stackView.addArrangedSubview(self.headerCard)

        self.stackView.addArrangedSubview(self.formatHeader)
        self.formatControl.selectedSegmentIndex = 0
        self.formatControl.addTarget(self, action: #selector(self.formatChanged), for: .valueChanged)
        self.formatCard.contentStack.addArrangedSubview(self.formatControl)
        self.stackView.addArrangedSubview(self.formatCard)

        self.exportButton.addTarget(self, action: #selector(self.chooseFolderTapped), for: .touchUpInside)
        self.cancelButton.addTarget(self, action: #selector(self.cancelTapped), for: .touchUpInside)
        self.actionCard.contentStack.addArrangedSubview(self.exportButton)
        self.actionCard.contentStack.addArrangedSubview(self.statusLabel)
        self.actionCard.contentStack.addArrangedSubview(self.cancelButton)
        self.stackView.addArrangedSubview(self.actionCard)

        self.render()
    }

    override func applyPresentationData(_ presentationData: PresentationData) {
        super.applyPresentationData(presentationData)
        self.render()
    }

    private func render() {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let palette = BeyGramThemePalette(theme: self.presentationData.theme)

        self.title = l10n.string(.exportTitle, languageCode: lang)

        self.headerCard.apply(palette: palette)
        self.chatTitleLabel.text = self.chatTitle
        self.chatTitleLabel.textColor = palette.primaryText
        self.noticeLabel.text = l10n.string(.exportProtectedNotice, languageCode: lang)
        self.noticeLabel.textColor = palette.secondaryText

        self.formatHeader.text = l10n.string(.exportSectionFormat, languageCode: lang).uppercased()
        self.formatHeader.textColor = palette.secondaryText
        self.formatCard.apply(palette: palette)
        self.formatControl.setTitle(l10n.string(.exportFormatJson, languageCode: lang), forSegmentAt: 0)
        self.formatControl.setTitle(l10n.string(.exportFormatHtml, languageCode: lang), forSegmentAt: 1)
        self.formatControl.isEnabled = !self.isRunning

        self.actionCard.apply(palette: palette)
        self.exportButton.configure(
            title: l10n.string(.exportChooseFolder, languageCode: lang),
            style: .primary,
            palette: palette,
            isLoading: self.isRunning,
            isEnabled: !self.isRunning
        )
        if let status = self.status {
            self.statusLabel.isHidden = false
            self.statusLabel.text = status
            self.statusLabel.textColor = palette.secondaryText
        } else {
            self.statusLabel.isHidden = true
        }
        self.cancelButton.isHidden = !self.isRunning
        self.cancelButton.configure(title: l10n.string(.exportCancel, languageCode: lang), style: .destructive, palette: palette)
    }

    @objc private func formatChanged() {
        self.format = self.formatControl.selectedSegmentIndex == 0 ? .json : .html
        self.render()
    }

    @objc private func chooseFolderTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = self
        self.present(picker, animated: true, completion: nil)
    }

    @objc private func cancelTapped() {
        self.exportTask?.cancel()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let folder = urls.first else { return }
        self.startExport(folder: folder)
    }

    private func startExport(folder: URL) {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let accessed = folder.startAccessingSecurityScopedResource()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let ext = self.format == .json ? "json" : "html"
        let fileURL = folder.appendingPathComponent("BeyGram-chat-\(stamp).\(ext)")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            if accessed { folder.stopAccessingSecurityScopedResource() }
            self.status = l10n.string(.commonError, languageCode: lang)
            self.render()
            return
        }
        self.folderURL = accessed ? folder : nil
        self.handle = handle
        self.isRunning = true
        self.status = l10n.format(.exportProgress, languageCode: lang, 0)
        self.render()

        let cleanup: () -> Void = {
            try? handle.truncate(atOffset: 0)
            try? handle.close()
            try? FileManager.default.removeItem(at: fileURL)
        }
        self.exportTask = Task { @MainActor in
            do {
                let summary = try await runChatExport(
                    context: self.context,
                    peerId: self.peerId,
                    chatTitle: self.chatTitle,
                    accountLabel: self.accountLabel,
                    hasProtectedContent: self.hasProtectedContent,
                    format: self.format,
                    range: ChatExportRange(),
                    sink: ChatExportFileHandleSink(handle: handle),
                    cleanup: cleanup,
                    onProgress: { progress in
                        self.status = l10n.format(.exportProgress, languageCode: lang, progress.exportedMessages)
                        self.render()
                    }
                )
                self.finishRun(message: l10n.format(.exportCompleted, languageCode: lang, "\(summary.exportedMessages)"))
            } catch is CancellationError {
                self.finishRun(message: l10n.string(.exportCancelled, languageCode: lang))
            } catch {
                self.finishRun(message: l10n.string(.commonError, languageCode: lang))
            }
        }
    }

    private func finishRun(message: String?) {
        self.isRunning = false
        self.status = message
        self.exportTask = nil
        try? self.handle?.close()
        self.handle = nil
        self.folderURL?.stopAccessingSecurityScopedResource()
        self.folderURL = nil
        self.render()
    }
}

public func chatExportController(context: AccountContext, peerId: EnginePeer.Id, chatTitle: String, accountLabel: String, hasProtectedContent: Bool) -> ViewController {
    return ChatExportViewControllerImpl(
        context: context,
        peerId: peerId,
        chatTitle: chatTitle,
        accountLabel: accountLabel,
        hasProtectedContent: hasProtectedContent
    )
}
