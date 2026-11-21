import Foundation
import UIKit
import UserNotifications
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramKit
import BeyGramTriggerWords

private final class TriggerWordsViewControllerImpl: BeyGramScrollViewController, UITextFieldDelegate {
    private let store = TriggerWordsStore.shared
    private var draftPattern = ""
    private var draftMode: TriggerWordMode = .wholeWord
    private var statusMessage: String?

    private let featureCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let featureRow = BeyGramRowView()

    private let scopeHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let scopeCard = BeyGramCardView(spacing: 8)
    private let scopeControl = UISegmentedControl(items: ["Muted", "All"])

    private let addHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let addCard = BeyGramCardView(spacing: 10)
    private let patternField = UITextField()
    private let modeControl = UISegmentedControl(items: ["Whole Word", "Substring"])
    private let addButton = BeyGramActionButton(style: .primary)
    private let statusLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .medium, lines: 0)

    private let rulesHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let rulesCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))

    private let feedHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let feedCard = BeyGramCardView(spacing: 8)
    private let feedStack = UIStackView()
    private let clearFeedButton = BeyGramActionButton(style: .destructive)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.render()
    }

    private func setupUI() {
        self.featureCard.contentStack.addArrangedSubview(self.featureRow)
        self.stackView.addArrangedSubview(self.featureCard)

        self.stackView.addArrangedSubview(self.scopeHeader)
        self.scopeControl.addTarget(self, action: #selector(self.scopeChanged), for: .valueChanged)
        self.scopeCard.contentStack.addArrangedSubview(self.scopeControl)
        self.stackView.addArrangedSubview(self.scopeCard)

        self.stackView.addArrangedSubview(self.addHeader)
        self.patternField.borderStyle = .roundedRect
        self.patternField.autocorrectionType = .no
        self.patternField.autocapitalizationType = .none
        self.patternField.font = BeyGramTypography.font(style: .body)
        self.patternField.adjustsFontForContentSizeCategory = true
        self.patternField.delegate = self
        self.patternField.addTarget(self, action: #selector(self.patternChanged), for: .editingChanged)

        self.modeControl.selectedSegmentIndex = 0
        self.modeControl.addTarget(self, action: #selector(self.modeChanged), for: .valueChanged)
        self.addButton.addTarget(self, action: #selector(self.addTapped), for: .touchUpInside)

        self.addCard.contentStack.addArrangedSubview(self.patternField)
        self.addCard.contentStack.addArrangedSubview(self.modeControl)
        self.addCard.contentStack.addArrangedSubview(self.addButton)
        self.addCard.contentStack.addArrangedSubview(self.statusLabel)
        self.stackView.addArrangedSubview(self.addCard)

        self.stackView.addArrangedSubview(self.rulesHeader)
        self.stackView.addArrangedSubview(self.rulesCard)

        self.stackView.addArrangedSubview(self.feedHeader)
        self.feedStack.axis = .vertical
        self.feedStack.spacing = 0
        self.feedCard.contentStack.addArrangedSubview(self.feedStack)
        self.clearFeedButton.addTarget(self, action: #selector(self.clearFeedTapped), for: .touchUpInside)
        self.feedCard.contentStack.addArrangedSubview(self.clearFeedButton)
        self.stackView.addArrangedSubview(self.feedCard)
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

        self.title = l10n.string(.triggerTitle, languageCode: lang)

        let enabled = BeyGramSettings.shared.isEnabled(.triggerWords)
        self.featureCard.apply(palette: palette)
        self.featureRow.configure(
            iconName: "text.magnifyingglass",
            iconTint: enabled ? palette.success : palette.accent,
            title: l10n.string(.triggerEnable, languageCode: lang),
            subtitle: isRu ? "Локальное сопоставление слов и фраз" : "Local matching of words and phrases",
            switchValue: enabled,
            showSeparator: false,
            palette: palette,
            onSwitch: { [weak self] val in
                BeyGramSettings.shared.setEnabled(val, for: .triggerWords)
                if val {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                }
                self?.render()
            }
        )

        self.scopeHeader.text = l10n.string(.triggerSectionScope, languageCode: lang).uppercased()
        self.scopeHeader.textColor = palette.secondaryText
        self.scopeCard.apply(palette: palette)
        self.scopeControl.setTitle(l10n.string(.triggerScopeMuted, languageCode: lang), forSegmentAt: 0)
        self.scopeControl.setTitle(l10n.string(.triggerScopeAll, languageCode: lang), forSegmentAt: 1)
        self.scopeControl.selectedSegmentIndex = self.store.state.scope == .onlyMutedChats ? 0 : 1

        self.addHeader.text = l10n.string(.triggerSectionAdd, languageCode: lang).uppercased()
        self.addHeader.textColor = palette.secondaryText
        self.addCard.apply(palette: palette)
        self.patternField.placeholder = l10n.string(.triggerInputPlaceholder, languageCode: lang)
        self.patternField.backgroundColor = palette.elevatedBackground
        self.patternField.textColor = palette.primaryText
        self.modeControl.setTitle(l10n.string(.triggerModeWholeWord, languageCode: lang), forSegmentAt: 0)
        self.modeControl.setTitle(l10n.string(.triggerModeAnywhere, languageCode: lang), forSegmentAt: 1)
        self.modeControl.selectedSegmentIndex = self.draftMode == .wholeWord ? 0 : 1

        let canAdd = !self.draftPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.addButton.configure(title: l10n.string(.triggerAddAction, languageCode: lang), style: .primary, palette: palette, isEnabled: canAdd)
        if let statusMessage = self.statusMessage {
            self.statusLabel.isHidden = false
            self.statusLabel.text = statusMessage
            self.statusLabel.textColor = palette.destructive
        } else {
            self.statusLabel.isHidden = true
        }

        // Rules
        let rules = self.store.state.rules
        self.rulesHeader.text = "\(l10n.string(.triggerSectionRules, languageCode: lang).uppercased()) (\(rules.count))"
        self.rulesHeader.textColor = palette.secondaryText
        self.rulesCard.apply(palette: palette)
        for subview in self.rulesCard.contentStack.arrangedSubviews {
            self.rulesCard.contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        if rules.isEmpty {
            let row = BeyGramRowView()
            row.configure(title: l10n.string(.triggerNoRules, languageCode: lang), showSeparator: false, palette: palette)
            self.rulesCard.contentStack.addArrangedSubview(row)
        } else {
            for (idx, rule) in rules.enumerated() {
                let row = BeyGramRowView()
                let modeTitle = rule.mode == .wholeWord ? l10n.string(.triggerModeWholeWord, languageCode: lang) : l10n.string(.triggerModeAnywhere, languageCode: lang)
                row.configure(
                    iconName: "tag",
                    iconTint: rule.isEnabled ? palette.accent : palette.secondaryText,
                    title: rule.pattern,
                    subtitle: modeTitle,
                    switchValue: rule.isEnabled,
                    showSeparator: idx < rules.count - 1,
                    palette: palette,
                    onTap: { [weak self] in
                        self?.confirmDeleteRule(rule)
                    },
                    onSwitch: { [weak self] val in
                        guard let self else { return }
                        var updated = rule
                        updated.isEnabled = val
                        _ = self.store.upsertRule(updated)
                        self.render()
                    }
                )
                self.rulesCard.contentStack.addArrangedSubview(row)
            }
        }

        // Mentions Feed
        let mentions = self.store.state.mentions
        self.feedHeader.text = l10n.string(.triggerSectionFeed, languageCode: lang).uppercased()
        self.feedHeader.textColor = palette.secondaryText
        self.feedCard.apply(palette: palette)
        for subview in self.feedStack.arrangedSubviews {
            self.feedStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        if mentions.isEmpty {
            let empty = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)
            empty.text = l10n.string(.triggerFeedEmpty, languageCode: lang)
            empty.textColor = palette.secondaryText
            self.feedStack.addArrangedSubview(empty)
            self.clearFeedButton.isHidden = true
        } else {
            for (idx, item) in mentions.prefix(30).enumerated() {
                let row = BeyGramRowView()
                let title = (item.senderName?.isEmpty == false ? item.senderName : nil) ?? "Chat \(item.chatId)"
                let snippet = item.text ?? ""
                row.configure(
                    iconName: "bell.fill",
                    iconTint: palette.accent,
                    title: title,
                    subtitle: snippet.isEmpty ? item.matchedPattern : "\(item.matchedPattern): \(snippet)",
                    showSeparator: idx < min(mentions.count, 30) - 1,
                    palette: palette
                )
                self.feedStack.addArrangedSubview(row)
            }
            self.clearFeedButton.isHidden = false
            self.clearFeedButton.configure(title: l10n.string(.triggerClearFeed, languageCode: lang), style: .destructive, palette: palette)
        }
    }

    private func confirmDeleteRule(_ rule: TriggerWordRule) {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let sheet = ActionSheetController(presentationData: self.presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: rule.pattern),
                ActionSheetButtonItem(title: l10n.string(.commonDelete, languageCode: lang), color: .destructive, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.store.removeRule(id: rule.id)
                    self?.render()
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        self.present(sheet, in: .window(.root))
    }

    @objc private func scopeChanged() {
        self.store.setScope(self.scopeControl.selectedSegmentIndex == 0 ? .onlyMutedChats : .allChats)
        self.render()
    }

    @objc private func patternChanged() {
        self.draftPattern = self.patternField.text ?? ""
        self.statusMessage = nil
        self.render()
    }

    @objc private func modeChanged() {
        self.draftMode = self.modeControl.selectedSegmentIndex == 0 ? .wholeWord : .anywhere
        self.render()
    }

    @objc private func addTapped() {
        self.patternField.resignFirstResponder()
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let rule = TriggerWordRule(pattern: self.draftPattern, mode: self.draftMode)
        if let err = self.store.upsertRule(rule) {
            switch err {
            case .emptyPattern:
                self.statusMessage = l10n.string(.triggerEmptyPatternStatus, languageCode: lang)
            case .duplicatePattern:
                self.statusMessage = l10n.string(.triggerDuplicateStatus, languageCode: lang)
            case .patternTooLong, .tooManyRules:
                self.statusMessage = l10n.string(.commonError, languageCode: lang)
            }
        } else {
            self.draftPattern = ""
            self.patternField.text = ""
            self.statusMessage = nil
        }
        self.render()
    }

    @objc private func clearFeedTapped() {
        self.store.clearFeed()
        self.render()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.addTapped()
        return true
    }
}

public func triggerWordsSettingsController(context: AccountContext) -> ViewController {
    return TriggerWordsViewControllerImpl(context: context)
}
