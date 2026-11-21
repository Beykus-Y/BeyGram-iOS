import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramKit

private final class BeyGramMixSettingsViewControllerImpl: BeyGramScrollViewController {
    private var stateDisposable: Disposable?
    private var musicState = BeyGramMusicSession.shared.currentState

    private let headerCard = BeyGramCardView(spacing: 8)
    private let headerTitle = BeyGramTypography.makeLabel(style: .headline, weight: .semibold, lines: 0)
    private let headerSubtitle = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)

    private let durationHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let durationCard = BeyGramCardView(spacing: 10)
    private let durationStack = UIStackView()
    private var durationButtons: [(Double, UIButton)] = []

    private let engineHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let engineCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let adaptiveRow = BeyGramRowView()
    private let bassSwapRow = BeyGramRowView()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.stateDisposable = (BeyGramMusicSession.shared.stateSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else { return }
            self.musicState = state
            self.render()
        })
    }

    deinit {
        self.stateDisposable?.dispose()
    }

    private func setupUI() {
        self.headerCard.contentStack.addArrangedSubview(self.headerTitle)
        self.headerCard.contentStack.addArrangedSubview(self.headerSubtitle)
        self.stackView.addArrangedSubview(self.headerCard)

        self.stackView.addArrangedSubview(self.durationHeader)
        self.durationStack.axis = .horizontal
        self.durationStack.spacing = 6
        self.durationStack.distribution = .fillEqually
        for value in [0.0, 2.0, 4.0, 6.0, 8.0, 12.0] {
            let btn = UIButton(type: .system)
            btn.layer.cornerRadius = 10
            btn.layer.cornerCurve = .continuous
            btn.titleLabel?.font = BeyGramTypography.font(style: .footnote, weight: .semibold)
            btn.titleLabel?.adjustsFontForContentSizeCategory = true
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 2, bottom: 8, right: 2)
            btn.tag = Int(value)
            btn.addTarget(self, action: #selector(self.durationTapped(_:)), for: .touchUpInside)
            self.durationButtons.append((value, btn))
            self.durationStack.addArrangedSubview(btn)
        }
        self.durationCard.contentStack.addArrangedSubview(self.durationStack)
        self.stackView.addArrangedSubview(self.durationCard)

        self.stackView.addArrangedSubview(self.engineHeader)
        self.engineCard.contentStack.addArrangedSubview(self.adaptiveRow)
        self.engineCard.contentStack.addArrangedSubview(self.bassSwapRow)
        self.stackView.addArrangedSubview(self.engineCard)
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

        self.title = l10n.string(.bgMixSettingsTitle, languageCode: lang)

        self.headerCard.apply(palette: palette)
        self.headerTitle.text = "BG Mix · BG Beat"
        self.headerTitle.textColor = palette.primaryText
        self.headerSubtitle.text = isRu
            ? "Автоматический анализ BPM и плавное сведение треков в реальном времени."
            : "Real-time BPM analysis and beat-matched crossfades between tracks."
        self.headerSubtitle.textColor = palette.secondaryText

        self.durationHeader.text = l10n.string(.bgMixTransitionDuration, languageCode: lang).uppercased()
        self.durationHeader.textColor = palette.secondaryText
        self.durationCard.apply(palette: palette)
        for (value, btn) in self.durationButtons {
            let title = value == 0.0 ? (isRu ? "Авто" : "Auto") : "\(Int(value))s"
            let selected = abs(self.musicState.transitionDuration - value) < 0.01
            btn.setTitle(title, for: .normal)
            btn.backgroundColor = selected ? palette.accent : palette.accentSoft
            btn.setTitleColor(selected ? palette.onAccent : palette.accent, for: .normal)
        }

        self.engineHeader.text = (isRu ? "ДВИЖОК СВЕДЕНИЯ" : "MIX ENGINE").uppercased()
        self.engineHeader.textColor = palette.secondaryText
        self.engineCard.apply(palette: palette)
        self.adaptiveRow.configure(
            iconName: "waveform.path.ecg",
            iconTint: palette.accent,
            title: l10n.string(.bgMixAdaptiveTransitions, languageCode: lang),
            subtitle: isRu ? "Подбирает точку перехода по структуре и темпу трека" : "Aligns transition points to track tempo and energy",
            switchValue: self.musicState.adaptiveTransitions,
            showSeparator: true,
            palette: palette,
            onSwitch: { val in BeyGramMusicSession.shared.setAdaptiveTransitions(val) }
        )
        self.bassSwapRow.configure(
            iconName: "slider.vertical.3",
            iconTint: palette.accent,
            title: l10n.string(.bgMixBassSwap, languageCode: lang),
            subtitle: isRu ? "Плавно заменяет низкие частоты во время сведения" : "Smoothly swaps low-end frequencies during crossfades",
            switchValue: self.musicState.bassSwap,
            showSeparator: false,
            palette: palette,
            onSwitch: { val in BeyGramMusicSession.shared.setBassSwap(val) }
        )
    }

    @objc private func durationTapped(_ sender: UIButton) {
        BeyGramMusicSession.shared.setTransitionDuration(Double(sender.tag))
    }
}

public func beyGramMixController(context: AccountContext) -> ViewController {
    return BeyGramNowPlayingViewController(context: context)
}

public func beyGramMixSettingsController(context: AccountContext) -> ViewController {
    return BeyGramMixSettingsViewControllerImpl(context: context)
}
