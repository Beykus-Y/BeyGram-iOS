import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramKit
import BeyGramMedia
import BGWaveListenerSession

private final class BeyGramWaveViewControllerImpl: BeyGramScrollViewController, UITextFieldDelegate {
    private var inviteText = ""
    private var validationResult: Bool?
    private var listenerSession: BGWaveListenerSession?
    private var isListening = false
    private var sessionStatusText: String?
    private var outboundLink: String?
    private var pollTimer: Timer?
    private var lastFailure: BGWaveListenerFailure = .none
    private var shownLocalNetworkHint = false

    private let heroCard = BeyGramCardView(spacing: 10)
    private let heroIcon = UIImageView()
    private let heroTitle = BeyGramTypography.makeLabel(style: .headline, weight: .semibold, lines: 0)
    private let statusBadge = BeyGramPillBadge()
    private let heroBody = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)

    private let inviteHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let inviteCard = BeyGramCardView(spacing: 10)
    private let inviteField = UITextField()
    private let checkButton = BeyGramActionButton(style: .primary)
    private let stopButton = BeyGramActionButton(style: .destructive)
    private let copyOutboundButton = BeyGramActionButton(style: .secondary)
    private let resultBadge = BeyGramPillBadge()

    deinit {
        self.pollTimer?.invalidate()
        self.listenerSession?.stop()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.heroIcon.image = UIImage(systemName: "dot.radiowaves.left.and.right")
        self.heroIcon.contentMode = .scaleAspectFit
        self.heroIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.heroIcon.widthAnchor.constraint(equalToConstant: 26),
            self.heroIcon.heightAnchor.constraint(equalToConstant: 26)
        ])
        let heroTop = UIStackView(arrangedSubviews: [self.heroIcon, self.heroTitle, UIView(), self.statusBadge])
        heroTop.axis = .horizontal
        heroTop.alignment = .center
        heroTop.spacing = 10
        self.heroCard.contentStack.addArrangedSubview(heroTop)
        self.heroCard.contentStack.addArrangedSubview(self.heroBody)
        self.stackView.addArrangedSubview(self.heroCard)

        self.stackView.addArrangedSubview(self.inviteHeader)
        self.inviteField.borderStyle = .roundedRect
        self.inviteField.autocorrectionType = .no
        self.inviteField.autocapitalizationType = .none
        self.inviteField.font = BeyGramTypography.font(style: .body)
        self.inviteField.adjustsFontForContentSizeCategory = true
        self.inviteField.delegate = self
        self.inviteField.addTarget(self, action: #selector(self.inviteChanged), for: .editingChanged)
        self.checkButton.addTarget(self, action: #selector(self.joinTapped), for: .touchUpInside)
        self.stopButton.addTarget(self, action: #selector(self.stopTapped), for: .touchUpInside)
        self.copyOutboundButton.addTarget(self, action: #selector(self.copyOutboundTapped), for: .touchUpInside)

        self.inviteCard.contentStack.addArrangedSubview(self.inviteField)
        self.inviteCard.contentStack.addArrangedSubview(self.checkButton)
        self.inviteCard.contentStack.addArrangedSubview(self.stopButton)
        self.inviteCard.contentStack.addArrangedSubview(self.copyOutboundButton)
        self.inviteCard.contentStack.addArrangedSubview(self.resultBadge)
        self.stackView.addArrangedSubview(self.inviteCard)

        self.render()
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

        self.title = l10n.string(.bgWaveTitle, languageCode: lang)

        self.heroCard.apply(palette: palette)
        if self.isListening {
            self.heroIcon.tintColor = palette.success
            self.heroTitle.text = l10n.string(.bgWaveTitle, languageCode: lang)
            self.statusBadge.configure(
                text: isRu ? "Подключено" : "Connected",
                textColor: palette.success,
                backgroundColor: palette.successSoft
            )
        } else if self.lastFailure != .none {
            self.heroIcon.tintColor = palette.destructive
            self.heroTitle.text = l10n.string(.bgWaveTitle, languageCode: lang)
            self.statusBadge.configure(
                text: l10n.string(.commonError, languageCode: lang),
                textColor: palette.destructive,
                backgroundColor: palette.destructiveSoft
            )
        } else {
            self.heroIcon.tintColor = palette.accent
            self.heroTitle.text = l10n.string(.bgWaveTitle, languageCode: lang)
            self.statusBadge.configure(
                text: l10n.string(.bgWaveStatusDisconnected, languageCode: lang),
                textColor: palette.secondaryText,
                backgroundColor: palette.separator.withAlphaComponent(0.2)
            )
        }
        self.heroTitle.textColor = palette.primaryText
        self.heroBody.text = self.sessionStatusText ?? l10n.string(.bgWaveUnavailableBody, languageCode: lang)
        self.heroBody.textColor = self.lastFailure != .none ? palette.destructive : palette.secondaryText

        self.inviteHeader.text = l10n.string(.bgWaveJoinByInvite, languageCode: lang).uppercased()
        self.inviteHeader.textColor = palette.secondaryText
        self.inviteCard.apply(palette: palette)
        self.inviteField.placeholder = l10n.string(.bgWaveInvitePlaceholder, languageCode: lang)
        self.inviteField.backgroundColor = palette.elevatedBackground
        self.inviteField.textColor = palette.primaryText

        let canJoin = !self.inviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.checkButton.configure(
            title: l10n.string(.bgWaveJoinByInvite, languageCode: lang),
            style: .primary,
            palette: palette,
            isEnabled: canJoin
        )
        self.stopButton.isHidden = !self.isListening && self.listenerSession == nil
        self.stopButton.configure(
            title: isRu ? "Остановить BG Wave" : "Stop BG Wave",
            style: .destructive,
            palette: palette,
            isEnabled: self.listenerSession != nil
        )

        if self.outboundLink != nil {
            self.copyOutboundButton.isHidden = false
            self.copyOutboundButton.configure(
                title: isRu ? "Скопировать ответную ссылку" : "Copy Answer Link",
                style: .secondary,
                palette: palette,
                isEnabled: true
            )
        } else {
            self.copyOutboundButton.isHidden = true
        }

        if let isValid = self.validationResult {
            self.resultBadge.isHidden = false
            self.resultBadge.configure(
                text: l10n.string(isValid ? .bgWaveInviteValid : .bgWaveInviteInvalid, languageCode: lang),
                textColor: isValid ? palette.success : palette.destructive,
                backgroundColor: isValid ? palette.successSoft : palette.destructiveSoft
            )
        } else {
            self.resultBadge.isHidden = true
        }
    }

    private func startPollingSession() {
        self.pollTimer?.invalidate()
        self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let session = self.listenerSession else { return }
            if let link = session.pollOutboundInvite(), !link.isEmpty {
                self.outboundLink = link
                self.render()
            }
            let failure = session.failure
            if failure != .none && failure != self.lastFailure {
                self.lastFailure = failure
                self.isListening = false
                if failure == .localNetworkSuspected && !self.shownLocalNetworkHint {
                    self.shownLocalNetworkHint = true
                    self.presentLocalNetworkHint()
                } else {
                    let lang = self.presentationData.strings.primaryComponent.languageCode
                    self.sessionStatusText = lang.lowercased().hasPrefix("ru")
                        ? "Сессия BG Wave завершилась с ошибкой."
                        : "BG Wave session ended with an error."
                }
                self.render()
            }
        }
    }

    private func presentLocalNetworkHint() {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let hint = BGWaveLocalNetworkHint.make(languageCode: lang)
        self.sessionStatusText = hint.message
        let alert = UIAlertController(title: hint.title, message: hint.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: hint.settingsButtonTitle, style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        })
        alert.addAction(UIAlertAction(title: hint.dismissButtonTitle, style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    @objc private func inviteChanged() {
        self.inviteText = self.inviteField.text ?? ""
        self.validationResult = nil
        self.render()
    }

    @objc private func joinTapped() {
        self.inviteField.resignFirstResponder()
        let trimmed = self.inviteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = BGWaveLinkLooksValid(trimmed)
        self.validationResult = valid
        guard valid else {
            self.render()
            return
        }

        self.pollTimer?.invalidate()
        self.listenerSession?.stop()
        self.lastFailure = .none
        self.shownLocalNetworkHint = false
        self.outboundLink = nil

        let session = BGWaveListenerSession()
        self.listenerSession = session
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let isRu = lang.lowercased().hasPrefix("ru")
        do {
            try session.acceptInviteLink(trimmed, nowUnixSeconds: Int64(Date().timeIntervalSince1970))
            try session.startListening()
            self.isListening = true
            self.sessionStatusText = isRu ? "Подключение к BG Wave..." : "Connecting to BG Wave..."
            if let link = session.pollOutboundInvite(), !link.isEmpty {
                self.outboundLink = link
            }
            self.startPollingSession()
        } catch {
            self.isListening = false
            self.lastFailure = session.failure != .none ? session.failure : .other
            if self.lastFailure == .localNetworkSuspected {
                self.presentLocalNetworkHint()
            } else {
                self.sessionStatusText = isRu
                    ? "Не удалось запустить сессию BG Wave."
                    : "Could not start BG Wave session."
            }
        }
        self.render()
    }

    @objc private func stopTapped() {
        self.pollTimer?.invalidate()
        self.pollTimer = nil
        self.listenerSession?.stop()
        self.listenerSession = nil
        self.isListening = false
        self.outboundLink = nil
        self.lastFailure = .none
        self.sessionStatusText = nil
        self.render()
    }

    @objc private func copyOutboundTapped() {
        guard let link = self.outboundLink else { return }
        UIPasteboard.general.string = link
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.joinTapped()
        return true
    }
}

public func beyGramWaveController(context: AccountContext) -> ViewController {
    return BeyGramWaveViewControllerImpl(context: context)
}
