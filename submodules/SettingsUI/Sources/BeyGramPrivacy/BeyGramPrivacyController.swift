import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramKit
import BeyGramStealth

private enum StealthPresetKind: Equatable {
    case normal
    case hiddenReading
    case maximum
    case custom
}

private func matchingStealthPreset(_ settings: BeyGramStealthSettings) -> StealthPresetKind {
    if settings.failClosed {
        return .custom
    }
    if !settings.hideTyping && !settings.hideReadReceipts && !settings.hideOnline && !settings.noStoryViews && !settings.serverScheduledSend {
        return .normal
    }
    if settings.hideTyping && settings.hideReadReceipts && !settings.hideOnline && settings.noStoryViews && !settings.serverScheduledSend {
        return .hiddenReading
    }
    if settings.hideTyping && settings.hideReadReceipts && settings.hideOnline && settings.noStoryViews && settings.serverScheduledSend {
        return .maximum
    }
    return .custom
}

private final class BeyGramPrivacyViewControllerImpl: BeyGramScrollViewController {
    private let accountPeerId: Int64
    private var featureEnabled: Bool
    private var settings: BeyGramStealthSettings

    private let statusCard = BeyGramCardView(spacing: 10)
    private let statusIcon = UIImageView()
    private let statusTitleLabel = BeyGramTypography.makeLabel(style: .headline, weight: .semibold, lines: 0)
    private let statusBadge = BeyGramPillBadge()
    private let statusBodyLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)
    private let masterSwitch = UISwitch()

    private let presetsHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let presetsCard = BeyGramCardView(spacing: 10)
    private let presetsStack = UIStackView()
    private var presetButtons: [(StealthPresetKind, UIButton)] = []

    private let hideHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let hideCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let hideTypingRow = BeyGramRowView()
    private let hideReadRow = BeyGramRowView()
    private let hideOnlineRow = BeyGramRowView()
    private let storyViewsRow = BeyGramRowView()

    private let sendHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let sendCard = BeyGramCardView(spacing: 12)
    private let scheduledRow = BeyGramRowView()
    private let delayLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .medium, lines: 1)
    private let delayStack = UIStackView()
    private var delayButtons: [(Int32, UIButton)] = []
    private let restrictionsLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)

    private let limitsCard = BeyGramCardView(spacing: 8)
    private let limitsTitleLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .semibold, lines: 0)
    private let limitsBodyLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)

    private var settingsObserver: NSObjectProtocol?
    private var featureObserver: NSObjectProtocol?

    override init(context: AccountContext) {
        self.accountPeerId = context.account.peerId.toInt64()
        self.featureEnabled = BeyGramSettings.shared.isEnabled(.privacyPolicy)
        self.settings = BeyGramStealthStore.shared.settings(accountPeerId: self.accountPeerId)
        super.init(context: context)
    }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let featureObserver { NotificationCenter.default.removeObserver(featureObserver) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()

        self.settingsObserver = NotificationCenter.default.addObserver(forName: BeyGramStealthStore.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.settings = BeyGramStealthStore.shared.settings(accountPeerId: self.accountPeerId)
            self.reloadContent()
        }
        self.featureObserver = NotificationCenter.default.addObserver(forName: BeyGramSettings.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.featureEnabled = BeyGramSettings.shared.isEnabled(.privacyPolicy)
            self.reloadContent()
        }
    }

    private func setupUI() {
        // Status Hero Card
        self.statusIcon.contentMode = .scaleAspectFit
        self.statusIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.statusIcon.widthAnchor.constraint(equalToConstant: 26),
            self.statusIcon.heightAnchor.constraint(equalToConstant: 26)
        ])
        self.masterSwitch.addTarget(self, action: #selector(self.masterToggled), for: .valueChanged)
        let headerRow = UIStackView(arrangedSubviews: [self.statusIcon, self.statusTitleLabel, self.statusBadge, UIView(), self.masterSwitch])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 10
        self.statusCard.contentStack.addArrangedSubview(headerRow)
        self.statusCard.contentStack.addArrangedSubview(self.statusBodyLabel)
        self.stackView.addArrangedSubview(self.statusCard)

        // Presets
        self.stackView.addArrangedSubview(self.presetsHeader)
        self.presetsStack.axis = .horizontal
        self.presetsStack.spacing = 8
        self.presetsStack.distribution = .fillEqually
        for kind in [StealthPresetKind.normal, .hiddenReading, .maximum] {
            let btn = UIButton(type: .system)
            btn.layer.cornerRadius = 11
            btn.layer.cornerCurve = .continuous
            btn.titleLabel?.font = BeyGramTypography.font(style: .footnote, weight: .semibold)
            btn.titleLabel?.adjustsFontForContentSizeCategory = true
            btn.titleLabel?.numberOfLines = 2
            btn.titleLabel?.textAlignment = .center
            btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
            btn.tag = self.presetButtons.count
            btn.addTarget(self, action: #selector(self.presetTapped(_:)), for: .touchUpInside)
            self.presetButtons.append((kind, btn))
            self.presetsStack.addArrangedSubview(btn)
        }
        self.presetsCard.contentStack.addArrangedSubview(self.presetsStack)
        self.stackView.addArrangedSubview(self.presetsCard)

        // Hide Activity Switches
        self.stackView.addArrangedSubview(self.hideHeader)
        self.hideCard.contentStack.addArrangedSubview(self.hideTypingRow)
        self.hideCard.contentStack.addArrangedSubview(self.hideReadRow)
        self.hideCard.contentStack.addArrangedSubview(self.hideOnlineRow)
        self.hideCard.contentStack.addArrangedSubview(self.storyViewsRow)
        self.stackView.addArrangedSubview(self.hideCard)

        // Server Scheduled Send + Delay Pills
        self.stackView.addArrangedSubview(self.sendHeader)
        self.sendCard.contentStack.addArrangedSubview(self.scheduledRow)
        self.sendCard.contentStack.addArrangedSubview(self.delayLabel)
        self.delayStack.axis = .horizontal
        self.delayStack.spacing = 8
        self.delayStack.distribution = .fillEqually
        for delay in BeyGramStealthSettings.scheduleDelayChoices {
            let btn = UIButton(type: .system)
            btn.layer.cornerRadius = 10
            btn.layer.cornerCurve = .continuous
            btn.titleLabel?.font = BeyGramTypography.font(style: .subheadline, weight: .semibold)
            btn.titleLabel?.adjustsFontForContentSizeCategory = true
            btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            btn.tag = Int(delay)
            btn.addTarget(self, action: #selector(self.delayTapped(_:)), for: .touchUpInside)
            self.delayButtons.append((delay, btn))
            self.delayStack.addArrangedSubview(btn)
        }
        self.sendCard.contentStack.addArrangedSubview(self.delayStack)
        self.sendCard.contentStack.addArrangedSubview(self.restrictionsLabel)
        self.stackView.addArrangedSubview(self.sendCard)

        // Honest Limits Card
        self.limitsCard.contentStack.addArrangedSubview(self.limitsTitleLabel)
        self.limitsCard.contentStack.addArrangedSubview(self.limitsBodyLabel)
        self.stackView.addArrangedSubview(self.limitsCard)

        self.reloadContent()
    }

    override func applyPresentationData(_ presentationData: PresentationData) {
        super.applyPresentationData(presentationData)
        self.reloadContent()
    }

    private func reloadContent() {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let isRu = lang.lowercased().hasPrefix("ru")
        let l10n = BeyGramL10n.shared
        let palette = BeyGramThemePalette(theme: self.presentationData.theme)

        self.title = l10n.string(.privacyTitle, languageCode: lang)

        // Status Card
        self.statusCard.apply(palette: palette)
        let active = self.featureEnabled
        self.masterSwitch.isOn = active
        self.masterSwitch.onTintColor = palette.accent
        self.statusIcon.image = UIImage(systemName: active ? "eye.slash.circle.fill" : "eye.circle")
        self.statusIcon.tintColor = active ? palette.success : palette.secondaryText
        self.statusTitleLabel.text = l10n.string(.privacyMasterTitle, languageCode: lang)
        self.statusTitleLabel.textColor = palette.primaryText

        let preset = matchingStealthPreset(self.settings)
        let badgeText: String
        if !active {
            badgeText = l10n.string(.commonOff, languageCode: lang)
            self.statusBadge.configure(text: badgeText, textColor: palette.secondaryText, backgroundColor: palette.separator.withAlphaComponent(0.2))
        } else {
            switch preset {
            case .normal:
                badgeText = isRu ? "Обычный" : "Normal"
            case .hiddenReading:
                badgeText = isRu ? "Скрытое чтение" : "Hidden reading"
            case .maximum:
                badgeText = isRu ? "Максимум" : "Maximum"
            case .custom:
                badgeText = isRu ? "Свой" : "Custom"
            }
            self.statusBadge.configure(text: badgeText, textColor: palette.success, backgroundColor: palette.successSoft)
        }
        if active && self.settings.failClosed {
            self.statusBodyLabel.text = isRu
                ? "Сохранённые настройки не удалось прочитать. Вся защита включена, а отправка идёт по расписанию, пока вы не измените переключатель."
                : "The saved settings could not be read. All protection stays on and sends are scheduled until you change a switch."
        } else {
            self.statusBodyLabel.text = active
                ? l10n.string(.privacyMasterActiveSummary, languageCode: lang)
                : l10n.string(.privacyMasterInactiveSummary, languageCode: lang)
        }
        self.statusBodyLabel.textColor = palette.secondaryText

        // Presets
        self.presetsHeader.text = (isRu ? "РЕЖИМЫ ЗАЩИТЫ" : "PROTECTION PRESETS")
        self.presetsHeader.textColor = palette.secondaryText
        self.presetsCard.apply(palette: palette)
        for (kind, btn) in self.presetButtons {
            let title: String
            switch kind {
            case .normal: title = isRu ? "Обычный" : "Normal"
            case .hiddenReading: title = isRu ? "Тихий" : "Quiet"
            case .maximum: title = isRu ? "Максимум" : "Maximum"
            case .custom: title = isRu ? "Свой" : "Custom"
            }
            let selected = active && (preset == kind)
            btn.setTitle(title, for: .normal)
            btn.isEnabled = active
            btn.alpha = active ? 1.0 : 0.5
            btn.backgroundColor = selected ? palette.accent : palette.accentSoft
            btn.setTitleColor(selected ? palette.onAccent : palette.accent, for: .normal)
        }

        // Hide Activity Switches
        self.hideHeader.text = l10n.string(.privacySectionHide, languageCode: lang).uppercased()
        self.hideHeader.textColor = palette.secondaryText
        self.hideCard.apply(palette: palette)

        let peerId = self.accountPeerId
        self.hideTypingRow.configure(
            iconName: "ellipsis.bubble",
            iconTint: palette.accent,
            title: l10n.string(.privacyHideTyping, languageCode: lang),
            subtitle: isRu ? "Не отправляет статус «печатает» и запись голоса" : "Suppresses typing and recording indicators",
            switchValue: self.settings.hideTyping,
            isEnabled: active,
            showSeparator: true,
            palette: palette,
            onSwitch: { val in
                BeyGramStealthStore.shared.update(accountPeerId: peerId) { $0.hideTyping = val }
            }
        )
        self.hideReadRow.configure(
            iconName: "checkmark.circle",
            iconTint: palette.accent,
            title: l10n.string(.privacyNoReadReceipts, languageCode: lang),
            subtitle: isRu ? "Включая темы, комментарии и «Прочитать все»" : "Covers chats, forum topics, comments, and Mark All Read",
            switchValue: self.settings.hideReadReceipts,
            isEnabled: active,
            showSeparator: true,
            palette: palette,
            onSwitch: { val in
                BeyGramStealthStore.shared.update(accountPeerId: peerId) { $0.hideReadReceipts = val }
            }
        )
        self.hideOnlineRow.configure(
            iconName: "moon.zzz",
            iconTint: palette.accent,
            title: l10n.string(.privacyHideOnline, languageCode: lang),
            subtitle: isRu ? "Применяется сразу для всего аккаунта" : "Applies immediately across the whole account",
            switchValue: self.settings.hideOnline,
            isEnabled: active,
            showSeparator: true,
            palette: palette,
            onSwitch: { val in
                BeyGramStealthStore.shared.update(accountPeerId: peerId) { $0.hideOnline = val }
            }
        )
        self.storyViewsRow.configure(
            iconName: "eye.slash",
            iconTint: palette.accent,
            title: isRu ? "Не отмечать просмотр историй" : "Don't mark story views",
            subtitle: isRu ? "Истории остаются непросмотренными, автор не видит просмотр" : "Stories stay unseen, so the author sees no view",
            switchValue: self.settings.noStoryViews,
            isEnabled: active,
            showSeparator: false,
            palette: palette,
            onSwitch: { val in
                BeyGramStealthStore.shared.update(accountPeerId: peerId) { $0.noStoryViews = val }
            }
        )

        // Scheduled Send
        self.sendHeader.text = l10n.string(.privacySectionSend, languageCode: lang).uppercased()
        self.sendHeader.textColor = palette.secondaryText
        self.sendCard.apply(palette: palette)

        self.scheduledRow.configure(
            iconName: "clock.arrow.circlepath",
            iconTint: palette.accent,
            title: l10n.string(.privacyDelayedSend, languageCode: lang),
            subtitle: isRu ? "Дата фиксируется на сервере после загрузки медиа" : "Scheduled on Telegram server after media upload completes",
            switchValue: self.settings.serverScheduledSend,
            isEnabled: active,
            showSeparator: false,
            palette: palette,
            onSwitch: { val in
                BeyGramStealthStore.shared.update(accountPeerId: peerId) { $0.serverScheduledSend = val }
            }
        )
        self.delayLabel.text = l10n.string(.privacyDelayPickerTitle, languageCode: lang)
        self.delayLabel.textColor = palette.secondaryText
        let delayInteractive = active && self.settings.serverScheduledSend
        for (delay, btn) in self.delayButtons {
            btn.setTitle("\(delay)s", for: .normal)
            btn.isEnabled = delayInteractive
            btn.alpha = delayInteractive ? 1.0 : 0.45
            let selected = self.settings.scheduledSendDelaySeconds == delay
            btn.backgroundColor = selected ? palette.accent : palette.accentSoft
            btn.setTitleColor(selected ? palette.onAccent : palette.accent, for: .normal)
        }
        self.restrictionsLabel.text = l10n.string(.privacyRestrictionsSummary, languageCode: lang)
        self.restrictionsLabel.textColor = palette.secondaryText

        // Honest Limits
        self.limitsCard.apply(palette: palette)
        self.limitsTitleLabel.text = l10n.string(.privacyHowItWorksTitle, languageCode: lang)
        self.limitsTitleLabel.textColor = palette.primaryText
        self.limitsBodyLabel.text = l10n.string(.privacyHowItWorksBody, languageCode: lang) + "\n\n" + l10n.string(.privacyDisclaimer, languageCode: lang)
        self.limitsBodyLabel.textColor = palette.secondaryText
    }

    @objc private func masterToggled() {
        BeyGramSettings.shared.setEnabled(self.masterSwitch.isOn, for: .privacyPolicy)
    }

    @objc private func presetTapped(_ sender: UIButton) {
        guard sender.tag >= 0 && sender.tag < self.presetButtons.count else { return }
        let kind = self.presetButtons[sender.tag].0
        BeyGramStealthStore.shared.update(accountPeerId: self.accountPeerId) { s in
            switch kind {
            case .normal:
                s.hideTyping = false
                s.hideReadReceipts = false
                s.hideOnline = false
                s.noStoryViews = false
                s.serverScheduledSend = false
            case .hiddenReading:
                s.hideTyping = true
                s.hideReadReceipts = true
                s.hideOnline = false
                s.noStoryViews = true
                s.serverScheduledSend = false
            case .maximum:
                s.hideTyping = true
                s.hideReadReceipts = true
                s.hideOnline = true
                s.noStoryViews = true
                s.serverScheduledSend = true
            case .custom:
                break
            }
        }
    }

    @objc private func delayTapped(_ sender: UIButton) {
        let delay = Int32(sender.tag)
        BeyGramStealthStore.shared.update(accountPeerId: self.accountPeerId) { s in
            s.scheduledSendDelaySeconds = max(BeyGramStealthSettings.minimumServerLeadSeconds, delay)
        }
    }
}

public func beyGramPrivacyController(context: AccountContext) -> ViewController {
    return BeyGramPrivacyViewControllerImpl(context: context)
}
