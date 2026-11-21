import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramKit
import BeyGramUpdates

private final class UpdatesViewControllerImpl: BeyGramScrollViewController {
    private var isChecking = false
    private var result: UpdateCheckResult?

    private let currentCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let versionRow = BeyGramRowView()
    private let channelRow = BeyGramRowView()
    private let commitRow = BeyGramRowView()

    private let actionCard = BeyGramCardView(spacing: 10)
    private let checkButton = BeyGramActionButton(style: .primary)
    private let statusBadge = BeyGramPillBadge()
    private let statusLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)
    private let releaseButton = BeyGramActionButton(style: .secondary)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.currentCard.contentStack.addArrangedSubview(self.versionRow)
        self.currentCard.contentStack.addArrangedSubview(self.channelRow)
        self.currentCard.contentStack.addArrangedSubview(self.commitRow)
        self.stackView.addArrangedSubview(self.currentCard)

        self.checkButton.addTarget(self, action: #selector(self.checkTapped), for: .touchUpInside)
        self.releaseButton.addTarget(self, action: #selector(self.releaseTapped), for: .touchUpInside)
        self.actionCard.contentStack.addArrangedSubview(self.checkButton)
        self.actionCard.contentStack.addArrangedSubview(self.statusBadge)
        self.actionCard.contentStack.addArrangedSubview(self.statusLabel)
        self.actionCard.contentStack.addArrangedSubview(self.releaseButton)
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

        self.title = l10n.string(.updatesTitle, languageCode: lang)
        self.currentCard.apply(palette: palette)

        self.versionRow.configure(title: l10n.string(.updatesCurrentVersion, languageCode: lang), value: BeyGramBuildInfo.currentVersionLabel(), showSeparator: true, palette: palette)
        self.channelRow.configure(title: l10n.string(.updatesCurrentChannel, languageCode: lang), value: BeyGramBuildInfo.channelName(), showSeparator: true, palette: palette)
        self.commitRow.configure(title: l10n.string(.updatesCurrentCommit, languageCode: lang), value: BeyGramBuildInfo.shortCommit(), showSeparator: false, palette: palette)

        self.actionCard.apply(palette: palette)
        self.checkButton.configure(
            title: l10n.string(.updatesCheckAction, languageCode: lang),
            style: .primary,
            palette: palette,
            isLoading: self.isChecking,
            isEnabled: !self.isChecking
        )

        self.statusBadge.isHidden = true
        self.statusLabel.isHidden = false
        self.releaseButton.isHidden = true

        if self.isChecking {
            self.statusLabel.text = l10n.string(.updatesStatusChecking, languageCode: lang)
            self.statusLabel.textColor = palette.secondaryText
        } else if let result = self.result {
            switch result {
            case .upToDate:
                self.statusBadge.isHidden = false
                self.statusBadge.configure(text: l10n.string(.updatesStatusUpToDate, languageCode: lang), textColor: palette.success, backgroundColor: palette.successSoft)
                self.statusLabel.isHidden = true
            case let .available(info):
                self.statusBadge.isHidden = false
                self.statusBadge.configure(text: l10n.string(.updatesAvailableHeader, languageCode: lang), textColor: palette.accent, backgroundColor: palette.accentSoft)
                self.statusLabel.text = info.version
                self.statusLabel.textColor = palette.primaryText
                self.releaseButton.isHidden = false
                self.releaseButton.configure(title: l10n.string(.updatesOpenRelease, languageCode: lang), style: .secondary, palette: palette)
            case let .failed(message):
                self.statusBadge.isHidden = false
                self.statusBadge.configure(text: l10n.string(.commonError, languageCode: lang), textColor: palette.destructive, backgroundColor: palette.destructiveSoft)
                self.statusLabel.text = l10n.string(.updatesStatusFailed(message), languageCode: lang)
                self.statusLabel.textColor = palette.destructive
            }
        } else {
            self.statusLabel.text = l10n.string(.updatesManualExplanation, languageCode: lang)
            self.statusLabel.textColor = palette.secondaryText
        }
    }

    @objc private func checkTapped() {
        guard !self.isChecking else { return }
        self.isChecking = true
        self.render()
        Task { @MainActor in
            let manifestURL = BeyGramBuildInfo.channelName() == "dev" ? UpdateManifestSource.devURL : UpdateManifestSource.releaseURL
            self.result = await UpdateChecker().check(manifestURL: manifestURL, currentVersion: BeyGramBuildInfo.currentVersionLabel())
            self.isChecking = false
            self.render()
        }
    }

    @objc private func releaseTapped() {
        if case let .available(info) = self.result {
            UIApplication.shared.open(info.releasePageURL)
        }
    }
}

public func beyGramUpdatesController(context: AccountContext) -> ViewController {
    return UpdatesViewControllerImpl(context: context)
}
