import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import BeyGramAppearance
import BeyGramDesign
import BeyGramKit
import BeyGramMusicUI
import BeyGramTriggerWordsUI
import BeyGramUpdatesUI
import BeyGramReportUI

private final class BeyGramSettingsHubViewControllerImpl: BeyGramScrollViewController {
    private let heroCard = BeyGramCardView(spacing: 8)
    private let heroTitleLabel = BeyGramTypography.makeLabel(style: .title2, weight: .bold, lines: 1)
    private let heroSubtitleLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)
    private let heroBadge = BeyGramPillBadge()

    private let featuresHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let featuresCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let privacyRow = BeyGramRowView()
    private let musicRow = BeyGramRowView()
    private let mihomoRow = BeyGramRowView()
    private let triggerRow = BeyGramRowView()
    private let pushRow = BeyGramRowView()

    private let interfaceHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let interfaceCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let appearanceRow = BeyGramRowView()

    private let maintenanceHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let maintenanceCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let diagnosticsRow = BeyGramRowView()
    private let updatesRow = BeyGramRowView()
    private let aboutRow = BeyGramRowView()

    private var settingsObserver: NSObjectProtocol?
    private var styleDisposable: Disposable?

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        self.styleDisposable?.dispose()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.settingsObserver = NotificationCenter.default.addObserver(forName: BeyGramSettings.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.render()
        }
        self.styleDisposable = (BeyGramAppearance.shared.styleSignal
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.render()
        })
        self.render()
    }

    private func setupUI() {
        let heroTop = UIStackView(arrangedSubviews: [self.heroTitleLabel, UIView(), self.heroBadge])
        heroTop.axis = .horizontal
        heroTop.alignment = .center
        heroTop.spacing = 8
        self.heroCard.contentStack.addArrangedSubview(heroTop)
        self.heroCard.contentStack.addArrangedSubview(self.heroSubtitleLabel)
        self.stackView.addArrangedSubview(self.heroCard)

        self.stackView.addArrangedSubview(self.featuresHeader)
        self.featuresCard.contentStack.addArrangedSubview(self.privacyRow)
        self.featuresCard.contentStack.addArrangedSubview(self.musicRow)
        self.featuresCard.contentStack.addArrangedSubview(self.mihomoRow)
        self.featuresCard.contentStack.addArrangedSubview(self.triggerRow)
        self.featuresCard.contentStack.addArrangedSubview(self.pushRow)
        self.stackView.addArrangedSubview(self.featuresCard)

        self.stackView.addArrangedSubview(self.interfaceHeader)
        self.interfaceCard.contentStack.addArrangedSubview(self.appearanceRow)
        self.stackView.addArrangedSubview(self.interfaceCard)

        self.stackView.addArrangedSubview(self.maintenanceHeader)
        self.maintenanceCard.contentStack.addArrangedSubview(self.diagnosticsRow)
        self.maintenanceCard.contentStack.addArrangedSubview(self.updatesRow)
        self.maintenanceCard.contentStack.addArrangedSubview(self.aboutRow)
        self.stackView.addArrangedSubview(self.maintenanceCard)
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

        self.title = l10n.string(.settingsHubTitle, languageCode: lang)

        self.heroCard.apply(palette: palette)
        self.heroTitleLabel.text = "BeyGram"
        self.heroTitleLabel.textColor = palette.primaryText
        self.heroSubtitleLabel.text = l10n.string(.settingsHubSubtitle, languageCode: lang)
        self.heroSubtitleLabel.textColor = palette.secondaryText
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "dev"
        self.heroBadge.configure(text: "Build \(build)", textColor: palette.accent, backgroundColor: palette.accentSoft)

        self.featuresHeader.text = (isRu ? "МОДУЛИ BEYGRAM" : "BEYGRAM FEATURES").uppercased()
        self.featuresHeader.textColor = palette.secondaryText
        self.featuresCard.apply(palette: palette)

        let privacyOn = BeyGramSettings.shared.isEnabled(.privacyPolicy)
        self.privacyRow.configure(
            iconName: "eye.slash.fill",
            iconTint: privacyOn ? palette.success : palette.accent,
            title: l10n.string(.settingsPrivacyTitle, languageCode: lang),
            value: l10n.string(privacyOn ? .commonOn : .commonOff, languageCode: lang),
            valueColor: privacyOn ? palette.success : palette.secondaryText,
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                self.pushController(beyGramPrivacyController(context: self.context))
            }
        )

        self.musicRow.configure(
            iconName: "music.note",
            iconTint: palette.accent,
            title: l10n.string(.settingsMusicTitle, languageCode: lang),
            subtitle: isRu ? "Яндекс.Музыка, Моя волна, BG Mix, BG Wave" : "Yandex Music, My Wave, BG Mix, BG Wave",
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                self.pushController(beyGramMusicSettingsController(context: self.context))
            }
        )

        let mihomoRunning = BeyGramMihomoRuntime.shared.controller.currentState.isRunning
        self.mihomoRow.configure(
            iconName: mihomoRunning ? "checkmark.shield.fill" : "shield",
            iconTint: mihomoRunning ? palette.success : palette.accent,
            title: l10n.string(.settingsMihomoTitle, languageCode: lang),
            value: l10n.string(mihomoRunning ? .mihomoStatusConnected : .mihomoStatusDisconnected, languageCode: lang),
            valueColor: mihomoRunning ? palette.success : palette.secondaryText,
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                let updated = self.context.sharedContext.presentationData
                self.pushController(beyGramMihomoController(
                    accountManager: self.context.sharedContext.accountManager,
                    presentationData: self.presentationData,
                    updatedPresentationData: updated
                ))
            }
        )

        let triggerOn = BeyGramSettings.shared.isEnabled(.triggerWords)
        self.triggerRow.configure(
            iconName: "text.magnifyingglass",
            iconTint: palette.accent,
            title: l10n.string(.settingsTriggerWordsTitle, languageCode: lang),
            value: l10n.string(triggerOn ? .commonOn : .commonOff, languageCode: lang),
            valueColor: triggerOn ? palette.success : palette.secondaryText,
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                self.pushController(triggerWordsSettingsController(context: self.context))
            }
        )

        let pushOn = BeyGramSettings.shared.isEnabled(.bgPush)
        self.pushRow.configure(
            iconName: "bell.badge.fill",
            iconTint: palette.accent,
            title: l10n.string(.settingsBgPushTitle, languageCode: lang),
            value: l10n.string(pushOn ? .commonOn : .commonOff, languageCode: lang),
            valueColor: pushOn ? palette.success : palette.secondaryText,
            showsChevron: true,
            showSeparator: false,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                self.pushController(beyGramPushController(context: self.context))
            }
        )

        // Interface
        self.interfaceHeader.text = (isRu ? "ИНТЕРФЕЙС" : "INTERFACE").uppercased()
        self.interfaceHeader.textColor = palette.secondaryText
        self.interfaceCard.apply(palette: palette)

        let styleValue = BeyGramAppearance.shared.isEnabled
            ? l10n.string(.appearanceStyleBeyGram, languageCode: lang)
            : l10n.string(.appearanceStyleTelegram, languageCode: lang)
        self.appearanceRow.configure(
            iconName: "paintbrush.fill",
            iconTint: palette.accent,
            title: l10n.string(.settingsAppearanceTitle, languageCode: lang),
            value: styleValue,
            showsChevron: true,
            showSeparator: false,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                self.pushController(beyGramStyleController(context: self.context))
            }
        )

        // Maintenance
        self.maintenanceHeader.text = (isRu ? "ОБСЛУЖИВАНИЕ" : "MAINTENANCE").uppercased()
        self.maintenanceHeader.textColor = palette.secondaryText
        self.maintenanceCard.apply(palette: palette)

        self.diagnosticsRow.configure(
            iconName: "stethoscope",
            iconTint: palette.accent,
            title: l10n.string(.settingsDiagnosticsTitle, languageCode: lang),
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
                self.pushController(reportController(context: self.context, appVersion: version))
            }
        )
        self.updatesRow.configure(
            iconName: "arrow.down.circle.fill",
            iconTint: palette.accent,
            title: l10n.string(.settingsUpdatesTitle, languageCode: lang),
            value: BeyGramBuildInfo.currentVersionLabel(),
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                self.pushController(beyGramUpdatesController(context: self.context))
            }
        )
        self.aboutRow.configure(
            iconName: "info.circle.fill",
            iconTint: palette.secondaryText,
            title: l10n.string(.settingsAboutTitle, languageCode: lang),
            showsChevron: true,
            showSeparator: false,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                self.pushController(beyGramAboutController(context: self.context))
            }
        )
    }

    private func pushController(_ controller: ViewController) {
        (self.navigationController as? NavigationController)?.pushViewController(controller)
    }
}

private final class BeyGramAboutViewControllerImpl: BeyGramScrollViewController {
    private let card = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let versionRow = BeyGramRowView()
    private let buildRow = BeyGramRowView()
    private let channelRow = BeyGramRowView()
    private let commitRow = BeyGramRowView()
    private let footerLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.card.contentStack.addArrangedSubview(self.versionRow)
        self.card.contentStack.addArrangedSubview(self.buildRow)
        self.card.contentStack.addArrangedSubview(self.channelRow)
        self.card.contentStack.addArrangedSubview(self.commitRow)
        self.stackView.addArrangedSubview(self.card)
        self.stackView.addArrangedSubview(self.footerLabel)
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

        self.title = l10n.string(.settingsAboutTitle, languageCode: lang)
        self.card.apply(palette: palette)

        let info = Bundle.main.infoDictionary
        let shortVersion = (info?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let buildNumber = (info?["CFBundleVersion"] as? String) ?? "1"
        let channel = BeyGramBuildInfo.channelName()
        let commit = BeyGramBuildInfo.shortCommit()

        self.versionRow.configure(title: l10n.string(.settingsAboutVersion, languageCode: lang), value: shortVersion, showSeparator: true, palette: palette)
        self.buildRow.configure(title: l10n.string(.settingsAboutBuild, languageCode: lang), value: buildNumber, showSeparator: true, palette: palette)
        self.channelRow.configure(title: l10n.string(.settingsAboutChannel, languageCode: lang), value: channel, showSeparator: true, palette: palette)
        self.commitRow.configure(title: l10n.string(.settingsAboutCommit, languageCode: lang), value: commit, showSeparator: false, palette: palette)
        self.footerLabel.text = l10n.string(.settingsAboutFooter, languageCode: lang)
        self.footerLabel.textColor = palette.secondaryText
    }
}

public func beyGramSettingsController(context: AccountContext) -> ViewController {
    return BeyGramSettingsHubViewControllerImpl(context: context)
}

public func beyGramAboutController(context: AccountContext) -> ViewController {
    return BeyGramAboutViewControllerImpl(context: context)
}
