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

    private let installedBuild: Int
    private let shortVersion: String
    private let isDev: Bool
    private let channel: UpdateChannel
    private let commitSha: String?

    private let currentCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let versionRow = BeyGramRowView()
    private let buildRow = BeyGramRowView()
    private let channelRow = BeyGramRowView()
    private let commitRow = BeyGramRowView()

    private let actionCard = BeyGramCardView(spacing: 10)
    private let checkButton = BeyGramActionButton(style: .primary)
    private let statusBadge = BeyGramPillBadge()
    private let statusLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)
    private let releaseButton = BeyGramActionButton(style: .secondary)

    override init(context: AccountContext) {
        let info = Bundle.main.infoDictionary ?? [:]
        self.installedBuild = Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        self.shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.0.1"
        let channelRaw = (info["BeyGramBuildChannel"] as? String)?.lowercased()
        self.isDev = channelRaw == "dev" || (info["CFBundleIdentifier"] as? String)?.lowercased().contains("dev") == true
        self.channel = self.isDev ? .dev : .release
        self.commitSha = (info["BeyGramGitCommit"] as? String) ?? (info["GitCommit"] as? String)
        super.init(context: context)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.currentCard.contentStack.addArrangedSubview(self.versionRow)
        self.currentCard.contentStack.addArrangedSubview(self.buildRow)
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

        let hasCommit = self.isDev && !(self.commitSha ?? "").isEmpty
        self.versionRow.configure(title: l10n.string(.updatesVersion, languageCode: lang), value: self.shortVersion, showSeparator: true, palette: palette)
        self.buildRow.configure(title: l10n.string(.updatesBuild, languageCode: lang), value: "\(self.installedBuild)", showSeparator: true, palette: palette)
        self.channelRow.configure(
            title: l10n.string(.updatesChannel, languageCode: lang),
            value: self.isDev ? l10n.string(.updatesChannelDev, languageCode: lang) : l10n.string(.updatesChannelRelease, languageCode: lang),
            showSeparator: hasCommit,
            palette: palette
        )
        if hasCommit, let sha = self.commitSha {
            self.commitRow.isHidden = false
            self.commitRow.configure(title: l10n.string(.updatesCommit, languageCode: lang), value: String(sha.prefix(8)), showSeparator: false, palette: palette)
        } else {
            self.commitRow.isHidden = true
        }

        self.actionCard.apply(palette: palette)
        self.checkButton.configure(
            title: self.isChecking ? l10n.string(.updatesChecking, languageCode: lang) : l10n.string(.updatesCheckButton, languageCode: lang),
            style: .primary,
            palette: palette,
            isLoading: self.isChecking,
            isEnabled: !self.isChecking
        )

        self.statusBadge.isHidden = true
        self.statusLabel.isHidden = false
        self.releaseButton.isHidden = true

        if self.isChecking {
            self.statusLabel.text = l10n.string(.updatesChecking, languageCode: lang)
            self.statusLabel.textColor = palette.secondaryText
        } else if let result = self.result {
            switch result {
            case .upToDate, .noReleases:
                self.statusBadge.isHidden = false
                self.statusBadge.configure(text: l10n.string(.updatesUpToDate, languageCode: lang), textColor: palette.success, backgroundColor: palette.successSoft)
                self.statusLabel.isHidden = true
            case let .available(updateInfo):
                self.statusBadge.isHidden = false
                self.statusBadge.configure(text: l10n.string(.updatesAvailableTitle, languageCode: lang), textColor: palette.accent, backgroundColor: palette.accentSoft)
                var versionSummary = l10n.format(.updatesAvailableVersion, languageCode: lang, "\(updateInfo.versionName) (\(updateInfo.buildNumber))")
                if let sha = updateInfo.commitSha, !sha.isEmpty {
                    versionSummary += " · \(String(sha.prefix(8)))"
                }
                if let changelog = updateInfo.changelog, !changelog.isEmpty {
                    versionSummary += "\n\n\(changelog)"
                }
                self.statusLabel.text = versionSummary
                self.statusLabel.textColor = palette.primaryText
                self.releaseButton.isHidden = false
                self.releaseButton.configure(title: l10n.string(.updatesOpenRelease, languageCode: lang), style: .secondary, palette: palette)
            case .failed:
                self.statusBadge.isHidden = false
                self.statusBadge.configure(text: l10n.string(.commonError, languageCode: lang), textColor: palette.destructive, backgroundColor: palette.destructiveSoft)
                self.statusLabel.text = l10n.format(.updatesErrorPrefix, languageCode: lang, l10n.string(.commonError, languageCode: lang))
                self.statusLabel.textColor = palette.destructive
            }
        } else {
            self.statusLabel.text = l10n.string(.updatesManualNote, languageCode: lang)
            self.statusLabel.textColor = palette.secondaryText
        }
    }

    @objc private func checkTapped() {
        guard !self.isChecking else { return }
        self.isChecking = true
        self.result = nil
        self.render()
        Task { @MainActor in
            self.result = await UpdateCheck.check(
                installedVersionName: self.shortVersion,
                installedBuildNumber: self.installedBuild,
                channel: self.channel
            )
            self.isChecking = false
            self.render()
        }
    }

    @objc private func releaseTapped() {
        if case let .available(updateInfo) = self.result {
            self.context.sharedContext.applicationBindings.openUrl(updateInfo.releaseURL.absoluteString)
        }
    }
}

public func beyGramUpdatesController(context: AccountContext) -> ViewController {
    return UpdatesViewControllerImpl(context: context)
}
