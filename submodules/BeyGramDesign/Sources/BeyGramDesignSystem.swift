import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramKit

/// Semantic palette derived from the active Telegram `PresentationTheme`, supporting light, dark, and custom themes.
public struct BeyGramThemePalette {
    public let isDark: Bool
    public let background: UIColor
    public let cardBackground: UIColor
    public let elevatedBackground: UIColor
    public let primaryText: UIColor
    public let secondaryText: UIColor
    public let accent: UIColor
    public let accentSoft: UIColor
    public let onAccent: UIColor
    public let destructive: UIColor
    public let destructiveSoft: UIColor
    public let success: UIColor
    public let successSoft: UIColor
    public let warning: UIColor
    public let warningSoft: UIColor
    public let separator: UIColor

    public init(theme: PresentationTheme) {
        self.isDark = theme.overallDarkAppearance
        self.background = theme.list.blocksBackgroundColor
        self.cardBackground = theme.list.itemBlocksBackgroundColor
        self.elevatedBackground = theme.overallDarkAppearance
            ? theme.list.itemBlocksBackgroundColor.withAlphaComponent(0.92)
            : theme.list.plainBackgroundColor
        self.primaryText = theme.list.itemPrimaryTextColor
        self.secondaryText = theme.list.itemSecondaryTextColor
        self.accent = theme.list.itemAccentColor
        self.accentSoft = theme.list.itemAccentColor.withAlphaComponent(theme.overallDarkAppearance ? 0.22 : 0.12)
        self.onAccent = theme.list.itemCheckColors.foregroundColor
        self.destructive = theme.list.itemDestructiveColor
        self.destructiveSoft = theme.list.itemDestructiveColor.withAlphaComponent(theme.overallDarkAppearance ? 0.22 : 0.12)
        let ok = UIColor(red: 0.18, green: 0.72, blue: 0.42, alpha: 1.0)
        self.success = ok
        self.successSoft = ok.withAlphaComponent(theme.overallDarkAppearance ? 0.22 : 0.13)
        let warn = UIColor(red: 0.92, green: 0.62, blue: 0.12, alpha: 1.0)
        self.warning = warn
        self.warningSoft = warn.withAlphaComponent(theme.overallDarkAppearance ? 0.22 : 0.14)
        self.separator = theme.list.itemBlocksSeparatorColor
    }
}

public enum BeyGramTypography {
    public static func font(style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        if weight == .regular {
            return base
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    public static func makeLabel(
        style: UIFont.TextStyle = .body,
        weight: UIFont.Weight = .regular,
        lines: Int = 0
    ) -> UILabel {
        let label = UILabel()
        label.font = font(style: style, weight: weight)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = lines
        return label
    }
}

/// Rounded surface card matching BeyGram's Android card language while adapting to Telegram themes.
open class BeyGramCardView: UIView {
    public let contentStack: UIStackView

    public init(spacing: CGFloat = 10.0, insets: UIEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)) {
        self.contentStack = UIStackView()
        super.init(frame: .zero)
        self.layer.cornerRadius = 16.0
        self.layer.cornerCurve = .continuous
        self.layer.borderWidth = 1.0 / UIScreen.main.scale

        self.contentStack.axis = .vertical
        self.contentStack.spacing = spacing
        self.contentStack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.contentStack)
        NSLayoutConstraint.activate([
            self.contentStack.topAnchor.constraint(equalTo: self.topAnchor, constant: insets.top),
            self.contentStack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: insets.left),
            self.contentStack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -insets.right),
            self.contentStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -insets.bottom)
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func apply(palette: BeyGramThemePalette) {
        self.backgroundColor = palette.cardBackground
        self.layer.borderColor = palette.separator.withAlphaComponent(palette.isDark ? 0.35 : 0.25).cgColor
    }
}

/// Pill badge used for connection states, active presets, BPM, and status summaries.
public final class BeyGramPillBadge: UIView {
    private let label = BeyGramTypography.makeLabel(style: .caption1, weight: .semibold, lines: 1)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.cornerRadius = 11.0
        self.layer.cornerCurve = .continuous
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.label)
        NSLayoutConstraint.activate([
            self.label.topAnchor.constraint(equalTo: self.topAnchor, constant: 4),
            self.label.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -4),
            self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            self.label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(text: String, textColor: UIColor, backgroundColor: UIColor) {
        self.label.text = text
        self.label.textColor = textColor
        self.backgroundColor = backgroundColor
    }
}

/// Primary/secondary/destructive action button with spring press animation and loading indicator.
public final class BeyGramActionButton: UIButton {
    public enum Style {
        case primary
        case secondary
        case destructive
    }

    private var buttonStyle: Style
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var storedTitle: String = ""

    public init(style: Style = .primary) {
        self.buttonStyle = style
        super.init(frame: .zero)
        self.layer.cornerRadius = 13.0
        self.layer.cornerCurve = .continuous
        self.titleLabel?.font = BeyGramTypography.font(style: .callout, weight: .semibold)
        self.titleLabel?.adjustsFontForContentSizeCategory = true
        self.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        self.spinner.hidesWhenStopped = true
        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.spinner)
        NSLayoutConstraint.activate([
            self.spinner.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        self.addTarget(self, action: #selector(self.touchDown), for: [.touchDown, .touchDragEnter])
        self.addTarget(self, action: #selector(self.touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(title: String, style: Style? = nil, palette: BeyGramThemePalette, isLoading: Bool = false, isEnabled: Bool = true) {
        if let style {
            self.buttonStyle = style
        }
        self.storedTitle = title
        self.isEnabled = isEnabled && !isLoading
        self.alpha = isEnabled ? 1.0 : 0.52

        switch self.buttonStyle {
        case .primary:
            self.backgroundColor = palette.accent
            self.setTitleColor(palette.onAccent, for: .normal)
            self.spinner.color = palette.onAccent
        case .secondary:
            self.backgroundColor = palette.accentSoft
            self.setTitleColor(palette.accent, for: .normal)
            self.spinner.color = palette.accent
        case .destructive:
            self.backgroundColor = palette.destructiveSoft
            self.setTitleColor(palette.destructive, for: .normal)
            self.spinner.color = palette.destructive
        }

        if isLoading {
            self.setTitle("", for: .normal)
            self.spinner.startAnimating()
        } else {
            self.spinner.stopAnimating()
            self.setTitle(title, for: .normal)
        }
        self.accessibilityLabel = title
    }

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }
    }

    @objc private func touchUp() {
        UIView.animate(withDuration: 0.24, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.allowUserInteraction]) {
            self.transform = .identity
        }
    }
}

/// Interactive row inside a `BeyGramCardView` supporting icon, title, subtitle, value/badge, switch, or chevron.
public final class BeyGramRowView: UIControl {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = BeyGramTypography.makeLabel(style: .body, weight: .medium, lines: 0)
    private let subtitleLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)
    private let valueLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 1)
    private let chevronView = UIImageView()
    private let toggleSwitch = UISwitch()
    private let separator = UIView()
    private var tapHandler: (() -> Void)?
    private var switchHandler: ((Bool) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)

        self.iconContainer.layer.cornerRadius = 9.0
        self.iconContainer.layer.cornerCurve = .continuous
        self.iconContainer.translatesAutoresizingMaskIntoConstraints = false
        self.iconView.contentMode = .scaleAspectFit
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.iconContainer.addSubview(self.iconView)

        let textStack = UIStackView(arrangedSubviews: [self.titleLabel, self.subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2.0
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        self.valueLabel.textAlignment = .right
        self.valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        self.chevronView.image = UIImage(systemName: "chevron.right")
        self.chevronView.contentMode = .scaleAspectFit
        self.chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.chevronView.setContentHuggingPriority(.required, for: .horizontal)

        self.toggleSwitch.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.toggleSwitch.setContentHuggingPriority(.required, for: .horizontal)
        self.toggleSwitch.addTarget(self, action: #selector(self.switchChanged), for: .valueChanged)

        let mainStack = UIStackView(arrangedSubviews: [self.iconContainer, textStack, self.valueLabel, self.toggleSwitch, self.chevronView])
        mainStack.axis = .horizontal
        mainStack.alignment = .center
        mainStack.spacing = 12.0
        mainStack.isUserInteractionEnabled = true
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(mainStack)

        self.separator.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.separator)

        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            self.iconContainer.widthAnchor.constraint(equalToConstant: 32),
            self.iconContainer.heightAnchor.constraint(equalToConstant: 32),
            self.iconView.centerXAnchor.constraint(equalTo: self.iconContainer.centerXAnchor),
            self.iconView.centerYAnchor.constraint(equalTo: self.iconContainer.centerYAnchor),
            self.iconView.widthAnchor.constraint(equalToConstant: 18),
            self.iconView.heightAnchor.constraint(equalToConstant: 18),
            self.chevronView.widthAnchor.constraint(equalToConstant: 12),
            self.chevronView.heightAnchor.constraint(equalToConstant: 14),
            mainStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 10),
            mainStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -10),
            mainStack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            self.separator.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            self.separator.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.separator.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.addTarget(self, action: #selector(self.handleTap), for: .touchUpInside)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard self.isUserInteractionEnabled, !self.isHidden, self.alpha >= 0.01, self.point(inside: point, with: event) else {
            return nil
        }
        if !self.toggleSwitch.isHidden && self.toggleSwitch.isEnabled {
            let switchPoint = self.convert(point, to: self.toggleSwitch)
            if let hit = self.toggleSwitch.hitTest(switchPoint, with: event) {
                return hit
            }
        }
        return self
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(
        iconName: String? = nil,
        iconTint: UIColor? = nil,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        valueColor: UIColor? = nil,
        showsChevron: Bool = false,
        switchValue: Bool? = nil,
        isEnabled: Bool = true,
        showSeparator: Bool = false,
        palette: BeyGramThemePalette,
        onTap: (() -> Void)? = nil,
        onSwitch: ((Bool) -> Void)? = nil
    ) {
        self.tapHandler = onTap
        self.switchHandler = onSwitch

        if let iconName {
            self.iconContainer.isHidden = false
            let tint = iconTint ?? palette.accent
            self.iconView.image = UIImage(systemName: iconName)
            self.iconView.tintColor = tint
            self.iconContainer.backgroundColor = tint.withAlphaComponent(palette.isDark ? 0.22 : 0.12)
        } else {
            self.iconContainer.isHidden = true
        }

        self.titleLabel.text = title
        self.titleLabel.textColor = isEnabled ? palette.primaryText : palette.secondaryText
        if let subtitle, !subtitle.isEmpty {
            self.subtitleLabel.isHidden = false
            self.subtitleLabel.text = subtitle
            self.subtitleLabel.textColor = palette.secondaryText
        } else {
            self.subtitleLabel.isHidden = true
        }

        if let value, !value.isEmpty {
            self.valueLabel.isHidden = false
            self.valueLabel.text = value
            self.valueLabel.textColor = valueColor ?? palette.secondaryText
        } else {
            self.valueLabel.isHidden = true
        }

        self.chevronView.isHidden = !showsChevron
        self.chevronView.tintColor = palette.secondaryText.withAlphaComponent(0.6)

        if let switchValue {
            self.toggleSwitch.isHidden = false
            self.toggleSwitch.isOn = switchValue
            self.toggleSwitch.isEnabled = isEnabled
            self.toggleSwitch.onTintColor = palette.accent
        } else {
            self.toggleSwitch.isHidden = true
        }

        self.separator.isHidden = !showSeparator
        self.separator.backgroundColor = palette.separator.withAlphaComponent(0.3)
        self.isUserInteractionEnabled = isEnabled && (onTap != nil || onSwitch != nil)
        self.isAccessibilityElement = true
        self.accessibilityLabel = [title, subtitle, value].compactMap { $0 }.joined(separator: ", ")
        if let switchValue {
            self.accessibilityValue = switchValue ? "1" : "0"
            self.accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
        } else {
            self.accessibilityValue = nil
            self.accessibilityTraits = onTap != nil ? (isEnabled ? .button : [.button, .notEnabled]) : .staticText
        }
    }

    @objc private func handleTap() {
        if !self.toggleSwitch.isHidden, self.toggleSwitch.isEnabled, self.tapHandler == nil, let switchHandler = self.switchHandler {
            let next = !self.toggleSwitch.isOn
            self.toggleSwitch.setOn(next, animated: true)
            self.accessibilityValue = next ? "1" : "0"
            switchHandler(next)
            return
        }
        self.tapHandler?()
    }

    @objc private func switchChanged() {
        self.accessibilityValue = self.toggleSwitch.isOn ? "1" : "0"
        self.switchHandler?(self.toggleSwitch.isOn)
    }
}

/// Base ViewController for redesigned BeyGram screens with theme observation, scrollable card stack, and keyboard navigation.
open class BeyGramScrollViewController: ViewController {
    public let context: AccountContext
    public let scrollView = UIScrollView()
    public let stackView = UIStackView()
    private var presentationDisposable: Disposable?
    public private(set) var presentationData: PresentationData

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.navigationPresentation = .modalInLargeLayout
    }

    @available(*, unavailable)
    public required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDisposable?.dispose()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.keyboardDismissMode = .interactive
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.displayNode.view.addSubview(self.scrollView)

        self.stackView.axis = .vertical
        self.stackView.spacing = 14.0
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.displayNode.view.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.displayNode.view.bottomAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.displayNode.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.displayNode.view.trailingAnchor),

            self.stackView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 16),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.trailingAnchor, constant: -16)
        ])

        self.presentationDisposable = (self.context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else { return }
            self.presentationData = presentationData
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
            self.applyPresentationData(presentationData)
        })
        self.applyPresentationData(self.presentationData)
    }

    open override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: layout.intrinsicInsets.bottom + 16, right: 0)
        self.scrollView.scrollIndicatorInsets = self.scrollView.contentInset
    }

    open override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(self.handleEscapeKey))
        ]
    }

    @objc private func handleEscapeKey() {
        if let nav = self.navigationController as? NavigationController {
            _ = nav.popViewController(animated: true)
        } else {
            self.dismiss()
        }
    }

    open func applyPresentationData(_ presentationData: PresentationData) {
        let palette = BeyGramThemePalette(theme: presentationData.theme)
        self.displayNode.backgroundColor = palette.background
    }
}
