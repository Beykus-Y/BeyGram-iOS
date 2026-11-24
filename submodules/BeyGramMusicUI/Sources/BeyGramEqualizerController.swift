import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramKit

private final class BeyGramEqualizerViewControllerImpl: BeyGramScrollViewController {
    private var disposable: Disposable?
    private var settings = BeyGramMusicSession.shared.currentEqualizer

    private let enableCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let enableRow = BeyGramRowView()

    private let presetCard = BeyGramCardView(spacing: 8)
    private let presetStack = UIStackView()
    private var presetButtons: [(BeyGramEqualizerPreset, UIButton)] = []

    private let bandsCard = BeyGramCardView(spacing: 6)
    private var bandRows: [(label: UILabel, slider: UISlider, value: UILabel)] = []
    private let resetButton = BeyGramActionButton(style: .secondary)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.disposable = (BeyGramMusicSession.shared.equalizerSignal
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else { return }
            self.settings = settings
            self.render()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    private func setupUI() {
        self.enableCard.contentStack.addArrangedSubview(self.enableRow)
        self.stackView.addArrangedSubview(self.enableCard)

        self.presetStack.axis = .vertical
        self.presetStack.spacing = 6
        var rowStack: UIStackView?
        for (index, preset) in BeyGramEqualizerPreset.allCases.enumerated() {
            if index % 3 == 0 {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 6
                row.distribution = .fillEqually
                self.presetStack.addArrangedSubview(row)
                rowStack = row
            }
            let button = UIButton(type: .system)
            button.layer.cornerRadius = 10
            button.layer.cornerCurve = .continuous
            button.titleLabel?.font = BeyGramTypography.font(style: .footnote, weight: .semibold)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            button.tag = index
            button.addTarget(self, action: #selector(self.presetTapped(_:)), for: .touchUpInside)
            self.presetButtons.append((preset, button))
            rowStack?.addArrangedSubview(button)
        }
        self.presetCard.contentStack.addArrangedSubview(self.presetStack)
        self.stackView.addArrangedSubview(self.presetCard)

        for (index, frequency) in BeyGramMusicSession.equalizerFrequenciesHz.enumerated() {
            let label = BeyGramTypography.makeLabel(style: .footnote, weight: .medium, lines: 1)
            label.text = frequency >= 1_000 ? "\(frequency / 1_000)k" : "\(frequency)"
            label.widthAnchor.constraint(equalToConstant: 40).isActive = true
            let slider = UISlider()
            slider.minimumValue = Float(BeyGramMusicSession.equalizerMinLevelMb) / 100.0
            slider.maximumValue = Float(BeyGramEqualizer.maxBoostMb) / 100.0
            slider.tag = index
            slider.addTarget(self, action: #selector(self.sliderChanged(_:)), for: .valueChanged)
            slider.addTarget(self, action: #selector(self.sliderEnded(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
            let value = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 1)
            value.textAlignment = .right
            value.widthAnchor.constraint(equalToConstant: 48).isActive = true
            let row = UIStackView(arrangedSubviews: [label, slider, value])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            self.bandsCard.contentStack.addArrangedSubview(row)
            self.bandRows.append((label, slider, value))
        }
        self.stackView.addArrangedSubview(self.bandsCard)

        self.resetButton.addTarget(self, action: #selector(self.resetTapped), for: .touchUpInside)
        self.stackView.addArrangedSubview(self.resetButton)
    }

    override func applyPresentationData(_ presentationData: PresentationData) {
        super.applyPresentationData(presentationData)
        self.render()
    }

    private func presetTitle(_ preset: BeyGramEqualizerPreset, lang: String) -> String {
        let key: String
        switch preset {
        case .flat: key = "equalizer_preset_flat"
        case .bass: key = "equalizer_preset_bass"
        case .vocal: key = "equalizer_preset_vocal"
        case .pop: key = "equalizer_preset_pop"
        case .rock: key = "equalizer_preset_rock"
        case .electronic: key = "equalizer_preset_electronic"
        case .classical: key = "equalizer_preset_classical"
        case .jazz: key = "equalizer_preset_jazz"
        case .custom: key = "equalizer_preset_custom"
        }
        return BeyGramAndroidStrings.shared.string(key, languageCode: lang)
    }

    private func render() {
        guard self.isViewLoaded else {
            return
        }
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let palette = BeyGramThemePalette(theme: self.presentationData.theme)

        self.title = BeyGramAndroidStrings.shared.string("equalizer_title", languageCode: lang)

        self.enableCard.apply(palette: palette)
        self.enableRow.configure(
            iconName: "slider.vertical.3",
            iconTint: palette.accent,
            title: BeyGramAndroidStrings.shared.string("equalizer_enabled_title", languageCode: lang),
            subtitle: nil,
            switchValue: self.settings.enabled,
            showSeparator: false,
            palette: palette,
            onSwitch: { value in BeyGramMusicSession.shared.setEqualizerEnabled(value) }
        )

        self.presetCard.apply(palette: palette)
        for (preset, button) in self.presetButtons {
            let selected = self.settings.selectedPreset == preset
            button.setTitle(self.presetTitle(preset, lang: lang), for: .normal)
            button.backgroundColor = selected ? palette.accent : palette.accentSoft
            button.setTitleColor(selected ? palette.onAccent : palette.accent, for: .normal)
            button.isEnabled = preset != .custom || self.settings.hasCustomPreset || selected
            button.alpha = button.isEnabled ? 1.0 : 0.4
        }

        self.bandsCard.apply(palette: palette)
        let levels = BeyGramMusicSession.shared.equalizerLevelsMb(for: self.settings)
        for (index, row) in self.bandRows.enumerated() where index < levels.count {
            row.label.textColor = palette.secondaryText
            row.value.textColor = palette.secondaryText
            row.slider.isEnabled = self.settings.enabled
            row.slider.tintColor = palette.accent
            if !row.slider.isTracking {
                row.slider.value = Float(levels[index]) / 100.0
            }
            row.value.text = String(format: "%+.1f dB", Float(levels[index]) / 100.0)
        }
        self.resetButton.configure(title: BeyGramAndroidStrings.shared.string("equalizer_reset", languageCode: lang), style: .secondary, palette: palette, isEnabled: self.settings.selectedPreset != .flat)
    }

    @objc private func presetTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < self.presetButtons.count else {
            return
        }
        BeyGramMusicSession.shared.selectEqualizerPreset(self.presetButtons[sender.tag].0)
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        BeyGramMusicSession.shared.setEqualizerBand(index: sender.tag, levelMb: Int((sender.value * 100).rounded()), persist: false)
    }

    @objc private func sliderEnded(_ sender: UISlider) {
        BeyGramMusicSession.shared.setEqualizerBand(index: sender.tag, levelMb: Int((sender.value * 100).rounded()), persist: true)
    }

    @objc private func resetTapped() {
        BeyGramMusicSession.shared.resetEqualizer()
    }
}

public func beyGramEqualizerController(context: AccountContext) -> ViewController {
    return BeyGramEqualizerViewControllerImpl(context: context)
}
