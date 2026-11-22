import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramKit
import BeyGramMedia

private final class BeyGramWaveViewControllerImpl: BeyGramScrollViewController, UITextFieldDelegate {
    private var inviteText = ""
    private var validationResult: Bool?

    private let heroCard = BeyGramCardView(spacing: 10)
    private let heroIcon = UIImageView()
    private let heroTitle = BeyGramTypography.makeLabel(style: .headline, weight: .semibold, lines: 0)
    private let statusBadge = BeyGramPillBadge()
    private let heroBody = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)

    private let inviteHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let inviteCard = BeyGramCardView(spacing: 10)
    private let inviteField = UITextField()
    private let checkButton = BeyGramActionButton(style: .primary)
    private let resultBadge = BeyGramPillBadge()

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
        self.checkButton.addTarget(self, action: #selector(self.checkTapped), for: .touchUpInside)

        self.inviteCard.contentStack.addArrangedSubview(self.inviteField)
        self.inviteCard.contentStack.addArrangedSubview(self.checkButton)
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
        let l10n = BeyGramL10n.shared
        let palette = BeyGramThemePalette(theme: self.presentationData.theme)

        self.title = l10n.string(.bgWaveTitle, languageCode: lang)

        self.heroCard.apply(palette: palette)
        self.heroIcon.tintColor = palette.warning
        self.heroTitle.text = l10n.string(.bgWaveUnavailableTitle, languageCode: lang)
        self.heroTitle.textColor = palette.primaryText
        self.statusBadge.configure(text: l10n.string(.bgWaveStatusDisconnected, languageCode: lang), textColor: palette.secondaryText, backgroundColor: palette.separator.withAlphaComponent(0.2))
        self.heroBody.text = l10n.string(.bgWaveUnavailableBody, languageCode: lang)
        self.heroBody.textColor = palette.secondaryText

        self.inviteHeader.text = l10n.string(.bgWaveJoinByInvite, languageCode: lang).uppercased()
        self.inviteHeader.textColor = palette.secondaryText
        self.inviteCard.apply(palette: palette)
        self.inviteField.placeholder = l10n.string(.bgWaveInvitePlaceholder, languageCode: lang)
        self.inviteField.backgroundColor = palette.elevatedBackground
        self.inviteField.textColor = palette.primaryText

        let canCheck = !self.inviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.checkButton.configure(title: l10n.string(.bgWaveCheckInvite, languageCode: lang), style: .primary, palette: palette, isEnabled: canCheck)

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

    @objc private func inviteChanged() {
        self.inviteText = self.inviteField.text ?? ""
        self.validationResult = nil
        self.render()
    }

    @objc private func checkTapped() {
        self.inviteField.resignFirstResponder()
        self.validationResult = BGWaveLinkLooksValid(self.inviteText)
        self.render()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.checkTapped()
        return true
    }
}

/// Native BG Wave screen prepared for shared-listening transport without simulating fake connections.
public func beyGramWaveController(context: AccountContext) -> ViewController {
    return BeyGramWaveViewControllerImpl(context: context)
}
