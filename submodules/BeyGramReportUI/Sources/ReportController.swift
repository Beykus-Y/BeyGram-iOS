import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramDiagnostics
import BeyGramKit

private let reportServerURL = URL(string: "https://beygram.beykus.fun")!

private final class ReportViewControllerImpl: BeyGramScrollViewController, UITextViewDelegate, UITextFieldDelegate {
    private let client = BugReportClient(baseURL: reportServerURL)
    private var flow: BugReportFlowState = .idle
    private var isSending = false

    private let introCard = BeyGramCardView(spacing: 8)
    private let introTitle = BeyGramTypography.makeLabel(style: .headline, weight: .semibold, lines: 0)
    private let introBody = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)

    private let formCard = BeyGramCardView(spacing: 12)
    private let descHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let descView = UITextView()
    private let nonceHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let nonceField = UITextField()
    private let sendButton = BeyGramActionButton(style: .primary)
    private let statusBadge = BeyGramPillBadge()
    private let statusLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .medium, lines: 0)

    private let previewCard = BeyGramCardView(spacing: 8)
    private let previewTitle = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let previewBody = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.render()
    }

    private func setupUI() {
        self.introCard.contentStack.addArrangedSubview(self.introTitle)
        self.introCard.contentStack.addArrangedSubview(self.introBody)
        self.stackView.addArrangedSubview(self.introCard)

        self.descView.font = BeyGramTypography.font(style: .body)
        self.descView.adjustsFontForContentSizeCategory = true
        self.descView.layer.cornerRadius = 10
        self.descView.layer.borderWidth = 1.0 / UIScreen.main.scale
        self.descView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        self.descView.delegate = self
        self.descView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.descView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])

        self.nonceField.borderStyle = .roundedRect
        self.nonceField.autocorrectionType = .no
        self.nonceField.autocapitalizationType = .none
        self.nonceField.font = BeyGramTypography.font(style: .body)
        self.nonceField.adjustsFontForContentSizeCategory = true
        self.nonceField.delegate = self
        self.nonceField.addTarget(self, action: #selector(self.nonceChanged), for: .editingChanged)

        self.sendButton.addTarget(self, action: #selector(self.sendTapped), for: .touchUpInside)

        self.formCard.contentStack.addArrangedSubview(self.descHeader)
        self.formCard.contentStack.addArrangedSubview(self.descView)
        self.formCard.contentStack.addArrangedSubview(self.nonceHeader)
        self.formCard.contentStack.addArrangedSubview(self.nonceField)
        self.formCard.contentStack.addArrangedSubview(self.sendButton)
        self.formCard.contentStack.addArrangedSubview(self.statusBadge)
        self.formCard.contentStack.addArrangedSubview(self.statusLabel)
        self.stackView.addArrangedSubview(self.formCard)

        self.previewCard.contentStack.addArrangedSubview(self.previewTitle)
        self.previewCard.contentStack.addArrangedSubview(self.previewBody)
        self.stackView.addArrangedSubview(self.previewCard)
    }

    override func applyPresentationData(_ presentationData: PresentationData) {
        super.applyPresentationData(presentationData)
        self.render()
    }

    private func render() {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let isRu = lang.lowercased().hasPrefix("ru")
        let l10n = BeyGramL10n.shared
        let palette = BeyGramThemePalette(theme: self.presentationData.theme)

        self.title = l10n.string(.diagnosticsTitle, languageCode: lang)

        self.introCard.apply(palette: palette)
        self.introTitle.text = l10n.string(.diagnosticsTitle, languageCode: lang)
        self.introTitle.textColor = palette.primaryText
        self.introBody.text = l10n.string(.diagnosticsInstructions, languageCode: lang)
        self.introBody.textColor = palette.secondaryText

        self.formCard.apply(palette: palette)
        self.descHeader.text = (isRu ? "ОПИСАНИЕ ПРОБЛЕМЫ" : "PROBLEM DESCRIPTION")
        self.descHeader.textColor = palette.secondaryText
        self.descView.backgroundColor = palette.elevatedBackground
        self.descView.textColor = palette.primaryText
        self.descView.layer.borderColor = palette.separator.withAlphaComponent(0.35).cgColor

        self.nonceHeader.text = (isRu ? "КОД ПОДТВЕРЖДЕНИЯ (NONCE)" : "VERIFICATION NONCE")
        self.nonceHeader.textColor = palette.secondaryText
        self.nonceField.placeholder = l10n.string(.diagnosticsNoncePlaceholder, languageCode: lang)
        self.nonceField.backgroundColor = palette.elevatedBackground
        self.nonceField.textColor = palette.primaryText

        let descTrimmed = (self.descView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nonceTrimmed = (self.nonceField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !self.isSending && !descTrimmed.isEmpty && !nonceTrimmed.isEmpty
        self.sendButton.configure(
            title: l10n.string(.diagnosticsSendAction, languageCode: lang),
            style: .primary,
            palette: palette,
            isLoading: self.isSending,
            isEnabled: canSend
        )

        self.statusBadge.isHidden = true
        self.statusLabel.isHidden = true
        switch self.flow {
        case .idle, .awaitingNonce:
            break
        case .uploading:
            self.statusBadge.isHidden = false
            self.statusBadge.configure(text: l10n.string(.diagnosticsStatusSending, languageCode: lang), textColor: palette.warning, backgroundColor: palette.warningSoft)
        case let .delivered(reportId):
            self.statusBadge.isHidden = false
            self.statusBadge.configure(text: l10n.string(.diagnosticsStatusSent, languageCode: lang), textColor: palette.success, backgroundColor: palette.successSoft)
            self.statusLabel.isHidden = false
            self.statusLabel.text = "ID: \(reportId)"
            self.statusLabel.textColor = palette.secondaryText
        case let .failed(_, reason):
            self.statusBadge.isHidden = false
            self.statusBadge.configure(text: l10n.string(.commonError, languageCode: lang), textColor: palette.destructive, backgroundColor: palette.destructiveSoft)
            self.statusLabel.isHidden = false
            self.statusLabel.text = l10n.string(.diagnosticsStatusFailed(String(describing: reason)), languageCode: lang)
            self.statusLabel.textColor = palette.destructive
        }

        self.previewCard.apply(palette: palette)
        self.previewTitle.text = l10n.string(.diagnosticsPreviewHeader, languageCode: lang).uppercased()
        self.previewTitle.textColor = palette.secondaryText
        let meta = BugReportDeviceInfo.current()
        let deviceLine = [meta.deviceModel, meta.osVersion, meta.appBuild].compactMap { $0 }.joined(separator: " · ")
        self.previewBody.text = l10n.string(.diagnosticsPreviewBody, languageCode: lang) + (deviceLine.isEmpty ? "" : "\n\n\(deviceLine)")
        self.previewBody.textColor = palette.secondaryText
    }

    func textViewDidChange(_ textView: UITextView) {
        self.render()
    }

    @objc private func nonceChanged() {
        self.render()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc private func sendTapped() {
        let description = (self.descView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nonce = (self.nonceField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !self.isSending, !description.isEmpty, !nonce.isEmpty else { return }

        let reportId: String
        switch self.flow {
        case let .awaitingNonce(id), let .failed(id, _):
            reportId = id
        case .idle, .delivered, .uploading:
            guard case let .awaitingNonce(id) = BugReportFlow.reduce(.idle, .start) else { return }
            reportId = id
        }
        self.flow = .awaitingNonce(reportId: reportId)
        self.flow = BugReportFlow.reduce(self.flow, .nonceReceived(nonce))
        guard case let .uploading(id, sentNonce) = self.flow else {
            self.render()
            return
        }
        self.isSending = true
        self.render()

        Task { @MainActor in
            do {
                let (body, _) = try BugReportSnapshot.makeBody(reportId: id, description: description, meta: BugReportDeviceInfo.current())
                let event = await self.client.upload(body: body, nonce: sentNonce)
                self.flow = BugReportFlow.reduce(self.flow, event)
            } catch {
                self.flow = .failed(reportId: id, reason: .invalidBody)
            }
            self.isSending = false
            self.render()
        }
    }
}

public func reportController(context: AccountContext, appVersion: String) -> ViewController {
    return ReportViewControllerImpl(context: context)
}
