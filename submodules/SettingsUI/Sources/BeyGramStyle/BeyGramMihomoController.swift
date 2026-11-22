import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import BeyGramDesign
import BeyGramKit
import BeyGramProxy

private enum BeyGramMihomoConnectionPhase: Equatable {
    case disconnected
    case connecting
    case reconnecting
    case connected
    case error(String)
}

private enum BeyGramMihomoSortOrder: Int32, CaseIterable {
    case original = 0
    case name = 1
    case latency = 2
}

private let lastSubscriptionUpdateKey = "beygram.mihomo.lastSubscriptionUpdate"

private final class BeyGramMihomoViewControllerImpl: ViewController, UITextFieldDelegate {
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private var presentationData: PresentationData
    private var presentationDisposable: Disposable?
    private var latencyToken: Int?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    // Hero Card
    private let heroCard = BeyGramCardView(spacing: 12)
    private let heroIcon = UIImageView()
    private let heroTitleLabel = BeyGramTypography.makeLabel(style: .headline, weight: .semibold, lines: 1)
    private let statusBadge = BeyGramPillBadge()
    private let activeServerLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .medium, lines: 2)
    private let activeLatencyBadge = BeyGramPillBadge()
    private let errorBannerLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .medium, lines: 0)
    private let primaryActionButton = BeyGramActionButton(style: .primary)

    // Subscription Card
    private let subHeaderLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let subCard = BeyGramCardView(spacing: 10)
    private let subField = UITextField()
    private let subRevealButton = UIButton(type: .system)
    private let subSaveButton = BeyGramActionButton(style: .secondary)
    private let subRefreshButton = BeyGramActionButton(style: .secondary)
    private let subMetaLabel = BeyGramTypography.makeLabel(style: .caption1, weight: .regular, lines: 0)

    // Servers Card
    private let serversHeaderLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let serversCard = BeyGramCardView(spacing: 10)
    private let autoSelectRow = BeyGramRowView()
    private let searchField = UITextField()
    private let sortStack = UIStackView()
    private var sortButtons: [(BeyGramMihomoSortOrder, UIButton)] = []
    private let measureButton = BeyGramActionButton(style: .secondary)
    private let serversListStack = UIStackView()

    // Info Card
    private let infoLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)

    // State
    private var phase: BeyGramMihomoConnectionPhase
    private var subscriptionText: String
    private var revealSubscription: Bool = false
    private var lastUpdatedAt: Date?
    private var isUpdatingSubscription: Bool = false
    private var isMeasuringDelays: Bool = false
    private var latencyCompleted: Int = 0
    private var latencyTotal: Int = 0
    private var serverNames: [String]
    private var selectedNode: String?
    private var autoSelect: Bool
    private var delays: [String: Int] = [:]
    private var searchQuery: String = ""
    private var sortOrder: BeyGramMihomoSortOrder = .original

    private var isBusy: Bool {
        switch self.phase {
        case .connecting, .reconnecting:
            return true
        default:
            return self.isUpdatingSubscription
        }
    }

    private var isConnected: Bool {
        if case .connected = self.phase {
            return true
        }
        return false
    }

    init(
        accountManager: AccountManager<TelegramAccountManagerTypes>,
        presentationData: PresentationData,
        updatedPresentationData: Signal<PresentationData, NoError>
    ) {
        self.accountManager = accountManager
        self.presentationData = presentationData
        let initial = BeyGramMihomoRuntime.shared.controller.currentState
        self.phase = initial.isRunning ? .connected : .disconnected
        self.subscriptionText = initial.subscriptionSource ?? ""
        self.lastUpdatedAt = UserDefaults.standard.object(forKey: lastSubscriptionUpdateKey) as? Date
        self.serverNames = initial.serverNames
        self.selectedNode = initial.selectedNode
        self.autoSelect = initial.autoSelectEnabled

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))
        self.navigationPresentation = .modalInLargeLayout

        self.presentationDisposable = (updatedPresentationData
        |> deliverOnMainQueue).start(next: { [weak self] nextData in
            guard let self else { return }
            self.presentationData = nextData
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: nextData), transition: .immediate)
            self.render()
        })

        self.latencyToken = BeyGramMihomoRuntime.shared.controller.addLatencyObserver { [weak self] check in
            DispatchQueue.main.async {
                guard let self else { return }
                if check.phase == .running {
                    self.isMeasuringDelays = true
                    self.latencyCompleted = check.completed
                    self.latencyTotal = check.total
                    for (name, delay) in check.delays {
                        self.delays[name] = delay
                    }
                    self.render()
                } else if check.phase == .finished {
                    self.isMeasuringDelays = false
                    self.latencyCompleted = check.completed
                    self.latencyTotal = check.total
                    for (name, delay) in check.delays where self.delays[name] == nil {
                        self.delays[name] = delay
                    }
                    self.render()
                }
            }
        }
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDisposable?.dispose()
        if let latencyToken {
            BeyGramMihomoRuntime.shared.controller.removeLatencyObserver(latencyToken)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.render()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: layout.intrinsicInsets.bottom + 16, right: 0)
        self.scrollView.scrollIndicatorInsets = self.scrollView.contentInset
    }

    override var keyCommands: [UIKeyCommand]? {
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

    private func setupUI() {
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.keyboardDismissMode = .interactive
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.displayNode.view.addSubview(self.scrollView)

        self.stackView.axis = .vertical
        self.stackView.spacing = 14
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

        // Hero Card
        self.heroIcon.contentMode = .scaleAspectFit
        self.heroIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.heroIcon.widthAnchor.constraint(equalToConstant: 26),
            self.heroIcon.heightAnchor.constraint(equalToConstant: 26)
        ])
        let heroTop = UIStackView(arrangedSubviews: [self.heroIcon, self.heroTitleLabel, UIView(), self.statusBadge])
        heroTop.axis = .horizontal
        heroTop.alignment = .center
        heroTop.spacing = 10
        self.heroCard.contentStack.addArrangedSubview(heroTop)

        let activeRow = UIStackView(arrangedSubviews: [self.activeServerLabel, UIView(), self.activeLatencyBadge])
        activeRow.axis = .horizontal
        activeRow.alignment = .center
        activeRow.spacing = 8
        self.heroCard.contentStack.addArrangedSubview(activeRow)
        self.heroCard.contentStack.addArrangedSubview(self.errorBannerLabel)
        self.primaryActionButton.addTarget(self, action: #selector(self.toggleConnectionTapped), for: .touchUpInside)
        self.heroCard.contentStack.addArrangedSubview(self.primaryActionButton)
        self.stackView.addArrangedSubview(self.heroCard)

        // Subscription Card
        self.stackView.addArrangedSubview(self.subHeaderLabel)
        self.subField.borderStyle = .roundedRect
        self.subField.autocorrectionType = .no
        self.subField.autocapitalizationType = .none
        self.subField.keyboardType = .URL
        self.subField.returnKeyType = .done
        self.subField.font = BeyGramTypography.font(style: .subheadline)
        self.subField.adjustsFontForContentSizeCategory = true
        self.subField.delegate = self
        self.subField.addTarget(self, action: #selector(self.subFieldChanged), for: .editingChanged)

        self.subRevealButton.titleLabel?.font = BeyGramTypography.font(style: .footnote, weight: .semibold)
        self.subRevealButton.setContentHuggingPriority(.required, for: .horizontal)
        self.subRevealButton.addTarget(self, action: #selector(self.toggleRevealTapped), for: .touchUpInside)

        let subInputRow = UIStackView(arrangedSubviews: [self.subField, self.subRevealButton])
        subInputRow.axis = .horizontal
        subInputRow.spacing = 8
        self.subCard.contentStack.addArrangedSubview(subInputRow)

        self.subSaveButton.addTarget(self, action: #selector(self.saveSubscriptionTapped), for: .touchUpInside)
        self.subRefreshButton.addTarget(self, action: #selector(self.refreshSubscriptionTapped), for: .touchUpInside)
        let subButtonsRow = UIStackView(arrangedSubviews: [self.subSaveButton, self.subRefreshButton])
        subButtonsRow.axis = .horizontal
        subButtonsRow.spacing = 8
        subButtonsRow.distribution = .fillEqually
        self.subCard.contentStack.addArrangedSubview(subButtonsRow)
        self.subCard.contentStack.addArrangedSubview(self.subMetaLabel)
        self.stackView.addArrangedSubview(self.subCard)

        // Servers Card
        self.stackView.addArrangedSubview(self.serversHeaderLabel)
        self.serversCard.contentStack.addArrangedSubview(self.autoSelectRow)

        self.searchField.borderStyle = .roundedRect
        self.searchField.autocorrectionType = .no
        self.searchField.autocapitalizationType = .none
        self.searchField.clearButtonMode = .whileEditing
        self.searchField.font = BeyGramTypography.font(style: .subheadline)
        self.searchField.adjustsFontForContentSizeCategory = true
        self.searchField.delegate = self
        self.searchField.addTarget(self, action: #selector(self.searchChanged), for: .editingChanged)
        self.serversCard.contentStack.addArrangedSubview(self.searchField)

        self.sortStack.axis = .horizontal
        self.sortStack.spacing = 8
        self.sortStack.distribution = .fillEqually
        for order in BeyGramMihomoSortOrder.allCases {
            let btn = UIButton(type: .system)
            btn.layer.cornerRadius = 10
            btn.layer.cornerCurve = .continuous
            btn.titleLabel?.font = BeyGramTypography.font(style: .caption1, weight: .semibold)
            btn.titleLabel?.adjustsFontForContentSizeCategory = true
            btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
            btn.tag = Int(order.rawValue)
            btn.addTarget(self, action: #selector(self.sortTapped(_:)), for: .touchUpInside)
            self.sortButtons.append((order, btn))
            self.sortStack.addArrangedSubview(btn)
        }
        self.serversCard.contentStack.addArrangedSubview(self.sortStack)

        self.measureButton.addTarget(self, action: #selector(self.measureDelaysTapped), for: .touchUpInside)
        self.serversCard.contentStack.addArrangedSubview(self.measureButton)

        self.serversListStack.axis = .vertical
        self.serversListStack.spacing = 0
        self.serversCard.contentStack.addArrangedSubview(self.serversListStack)
        self.stackView.addArrangedSubview(self.serversCard)

        self.stackView.addArrangedSubview(self.infoLabel)
    }

    private func render() {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let isRu = lang.lowercased().hasPrefix("ru")
        let l10n = BeyGramL10n.shared
        let palette = BeyGramThemePalette(theme: self.presentationData.theme)

        self.displayNode.backgroundColor = palette.background
        self.title = l10n.string(.mihomoTitle, languageCode: lang)

        // Hero Card
        self.heroCard.apply(palette: palette)
        let statusText: String
        let statusColor: UIColor
        let statusBg: UIColor
        let iconName: String
        switch self.phase {
        case .disconnected:
            statusText = l10n.string(.mihomoStatusDisconnected, languageCode: lang)
            statusColor = palette.secondaryText
            statusBg = palette.separator.withAlphaComponent(0.2)
            iconName = "shield"
        case .connecting:
            statusText = l10n.string(.mihomoStatusConnecting, languageCode: lang)
            statusColor = palette.warning
            statusBg = palette.warningSoft
            iconName = "shield.lefthalf.filled"
        case .reconnecting:
            statusText = l10n.string(.mihomoStatusReconnecting, languageCode: lang)
            statusColor = palette.warning
            statusBg = palette.warningSoft
            iconName = "arrow.triangle.2.circlepath.circle"
        case .connected:
            statusText = l10n.string(.mihomoStatusConnected, languageCode: lang)
            statusColor = palette.success
            statusBg = palette.successSoft
            iconName = "checkmark.shield.fill"
        case .error:
            statusText = l10n.string(.mihomoStatusError, languageCode: lang)
            statusColor = palette.destructive
            statusBg = palette.destructiveSoft
            iconName = "exclamationmark.shield.fill"
        }
        self.heroIcon.image = UIImage(systemName: iconName)
        self.heroIcon.tintColor = statusColor
        self.heroTitleLabel.text = "Mihomo"
        self.heroTitleLabel.textColor = palette.primaryText
        self.statusBadge.configure(text: statusText, textColor: statusColor, backgroundColor: statusBg)

        let nodeText = self.selectedNode ?? (isRu ? "Сервер не выбран" : "No server selected")
        self.activeServerLabel.text = "\(l10n.string(.mihomoActiveServer, languageCode: lang)): \(nodeText)"
        self.activeServerLabel.textColor = palette.secondaryText

        if let selected = self.selectedNode, let delay = self.delays[selected] {
            self.activeLatencyBadge.isHidden = false
            let (latText, latColor, latBg) = self.latencyStyle(delay: delay, palette: palette, isRu: isRu)
            self.activeLatencyBadge.configure(text: latText, textColor: latColor, backgroundColor: latBg)
        } else {
            self.activeLatencyBadge.isHidden = true
        }

        if case let .error(message) = self.phase {
            self.errorBannerLabel.isHidden = false
            self.errorBannerLabel.text = message
            self.errorBannerLabel.textColor = palette.destructive
        } else {
            self.errorBannerLabel.isHidden = true
        }

        let buttonTitle = self.isConnected ? l10n.string(.mihomoDisconnect, languageCode: lang) : l10n.string(.mihomoConnect, languageCode: lang)
        self.primaryActionButton.configure(
            title: buttonTitle,
            style: self.isConnected ? .destructive : .primary,
            palette: palette,
            isLoading: self.isBusy,
            isEnabled: !self.isBusy
        )

        // Subscription Card
        self.subHeaderLabel.text = l10n.string(.mihomoSectionSubscription, languageCode: lang).uppercased()
        self.subHeaderLabel.textColor = palette.secondaryText
        self.subCard.apply(palette: palette)

        self.subField.placeholder = l10n.string(.mihomoSubscriptionPlaceholder, languageCode: lang)
        self.subField.textColor = palette.primaryText
        self.subField.backgroundColor = palette.elevatedBackground
        self.subField.isSecureTextEntry = !self.revealSubscription
        if self.subField.text != self.subscriptionText && !self.subField.isFirstResponder {
            self.subField.text = self.subscriptionText
        }
        self.subRevealButton.setTitle(self.revealSubscription ? (isRu ? "Скрыть" : "Hide") : (isRu ? "Показать" : "Show"), for: .normal)
        self.subRevealButton.tintColor = palette.accent

        let canSaveSub = !self.isBusy && !self.subscriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.subSaveButton.configure(
            title: isRu ? "Сохранить" : "Save",
            style: .secondary,
            palette: palette,
            isLoading: self.isUpdatingSubscription,
            isEnabled: canSaveSub
        )
        self.subRefreshButton.configure(
            title: isRu ? "Обновить" : "Refresh",
            style: .secondary,
            palette: palette,
            isLoading: false,
            isEnabled: canSaveSub
        )

        if let lastUpdatedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let rel = formatter.localizedString(for: lastUpdatedAt, relativeTo: Date())
            self.subMetaLabel.isHidden = false
            self.subMetaLabel.text = (isRu ? "Обновлено: " : "Updated: ") + rel
            self.subMetaLabel.textColor = palette.secondaryText
        } else {
            self.subMetaLabel.isHidden = true
        }

        // Servers Card
        self.serversHeaderLabel.text = "\(l10n.string(.mihomoSectionServers, languageCode: lang).uppercased()) (\(self.serverNames.count))"
        self.serversHeaderLabel.textColor = palette.secondaryText
        self.serversCard.apply(palette: palette)

        self.autoSelectRow.configure(
            iconName: "bolt.horizontal.circle",
            iconTint: palette.accent,
            title: isRu ? "Автовыбор лучшего сервера" : "Auto-select fastest server",
            subtitle: isRu ? "Автоматически переключается при смене сети" : "Switches automatically on network change",
            switchValue: self.autoSelect,
            isEnabled: !self.isBusy,
            showSeparator: false,
            palette: palette,
            onSwitch: { [weak self] val in
                guard let self else { return }
                self.autoSelect = val
                BeyGramMihomoRuntime.shared.setAutoSelect(val)
                self.render()
            }
        )

        self.searchField.placeholder = l10n.string(.commonSearch, languageCode: lang)
        self.searchField.textColor = palette.primaryText
        self.searchField.backgroundColor = palette.elevatedBackground

        for (order, btn) in self.sortButtons {
            let title: String
            switch order {
            case .original: title = isRu ? "По умолчанию" : "Default"
            case .name: title = isRu ? "По имени" : "Name"
            case .latency: title = isRu ? "По пингу" : "Latency"
            }
            let selected = self.sortOrder == order
            btn.setTitle(title, for: .normal)
            btn.backgroundColor = selected ? palette.accent : palette.accentSoft
            btn.setTitleColor(selected ? palette.onAccent : palette.accent, for: .normal)
        }

        let measureTitle: String
        if self.isMeasuringDelays && self.latencyTotal > 0 {
            measureTitle = isRu
                ? "Проверка задержек (\(self.latencyCompleted)/\(self.latencyTotal))…"
                : "Testing delays (\(self.latencyCompleted)/\(self.latencyTotal))…"
        } else {
            measureTitle = isRu ? "Проверить задержки" : "Measure Delays"
        }
        self.measureButton.configure(
            title: measureTitle,
            style: .secondary,
            palette: palette,
            isLoading: false,
            isEnabled: !self.isBusy && !self.isMeasuringDelays && !self.serverNames.isEmpty
        )

        // Rebuild visible server rows
        for subview in self.serversListStack.arrangedSubviews {
            self.serversListStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let query = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var filtered = self.serverNames.filter { query.isEmpty || $0.lowercased().contains(query) }
        switch self.sortOrder {
        case .original:
            break
        case .name:
            filtered.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .latency:
            filtered.sort { lhs, rhs in
                let ld = self.delays[lhs] ?? Int.max
                let rd = self.delays[rhs] ?? Int.max
                if ld != rd { return ld < rd }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }

        if filtered.isEmpty {
            let empty = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)
            empty.text = self.serverNames.isEmpty
                ? (isRu ? "Добавьте подписку, чтобы загрузить серверы." : "Add a subscription URL to load servers.")
                : (isRu ? "Ничего не найдено." : "No matching servers.")
            empty.textColor = palette.secondaryText
            empty.textAlignment = .center
            empty.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
            self.serversListStack.addArrangedSubview(empty)
        } else {
            for (index, name) in filtered.enumerated() {
                let row = BeyGramRowView()
                let isSelected = name == self.selectedNode
                let delayText: String?
                let delayColor: UIColor?
                if let d = self.delays[name] {
                    let styled = self.latencyStyle(delay: d, palette: palette, isRu: isRu)
                    delayText = styled.0
                    delayColor = styled.1
                } else {
                    delayText = nil
                    delayColor = nil
                }
                row.configure(
                    iconName: isSelected ? "checkmark.circle.fill" : "globe",
                    iconTint: isSelected ? palette.success : palette.secondaryText,
                    title: name,
                    subtitle: nil,
                    value: delayText,
                    valueColor: delayColor,
                    showsChevron: false,
                    switchValue: nil,
                    isEnabled: !self.isBusy,
                    showSeparator: index < filtered.count - 1,
                    palette: palette,
                    onTap: { [weak self] in
                        self?.selectServer(name)
                    }
                )
                self.serversListStack.addArrangedSubview(row)
            }
        }

        self.infoLabel.text = l10n.string(.mihomoBackgroundLimitBody, languageCode: lang)
        self.infoLabel.textColor = palette.secondaryText
    }

    private func latencyStyle(delay: Int, palette: BeyGramThemePalette, isRu: Bool) -> (String, UIColor, UIColor) {
        if delay <= 0 {
            return (isRu ? "Недоступен" : "Timeout", palette.destructive, palette.destructiveSoft)
        } else if delay < 150 {
            return ("\(delay) ms", palette.success, palette.successSoft)
        } else if delay < 350 {
            return ("\(delay) ms", palette.warning, palette.warningSoft)
        } else {
            return ("\(delay) ms", palette.destructive, palette.destructiveSoft)
        }
    }

    private func selectServer(_ name: String) {
        guard !self.isBusy else { return }
        BeyGramMihomoRuntime.shared.controller.selectNode(name) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.selectedNode = name
                case let .failure(error):
                    self.phase = .error(error.localizedDescription)
                }
                self.render()
            }
        }
    }

    @objc private func toggleConnectionTapped() {
        guard !self.isBusy else { return }
        if self.isConnected {
            self.phase = .reconnecting
            self.render()
            BeyGramMihomoRuntime.shared.disconnect(accountManager: self.accountManager) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.phase = .disconnected
                    case let .failure(error):
                        self.phase = .error(error.localizedDescription)
                    }
                    self.render()
                }
            }
        } else {
            self.phase = .connecting
            self.render()
            BeyGramMihomoRuntime.shared.connect(accountManager: self.accountManager) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.phase = .connected
                    case let .failure(error):
                        self.phase = .error(error.localizedDescription)
                    }
                    self.render()
                }
            }
        }
    }

    @objc private func subFieldChanged() {
        self.subscriptionText = self.subField.text ?? ""
        self.render()
    }

    @objc private func toggleRevealTapped() {
        self.revealSubscription.toggle()
        self.render()
    }

    @objc private func saveSubscriptionTapped() {
        guard !self.isBusy else { return }
        self.isUpdatingSubscription = true
        if case .error = self.phase { self.phase = .disconnected }
        self.render()
        BeyGramMihomoRuntime.shared.controller.saveSubscription(self.subscriptionText) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdatingSubscription = false
                switch result {
                case let .success(names):
                    let now = Date()
                    UserDefaults.standard.set(now, forKey: lastSubscriptionUpdateKey)
                    self.serverNames = names
                    self.selectedNode = BeyGramMihomoRuntime.shared.controller.currentState.selectedNode
                    self.delays = [:]
                    self.lastUpdatedAt = now
                    self.revealSubscription = false
                case let .failure(error):
                    self.phase = .error(error.localizedDescription)
                }
                self.render()
            }
        }
    }

    @objc private func refreshSubscriptionTapped() {
        guard !self.isBusy else { return }
        self.isUpdatingSubscription = true
        if case .error = self.phase { self.phase = .disconnected }
        self.render()
        BeyGramMihomoRuntime.shared.controller.refreshSubscription { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdatingSubscription = false
                switch result {
                case let .success(names):
                    let now = Date()
                    UserDefaults.standard.set(now, forKey: lastSubscriptionUpdateKey)
                    self.serverNames = names
                    self.selectedNode = BeyGramMihomoRuntime.shared.controller.currentState.selectedNode
                    self.delays = [:]
                    self.lastUpdatedAt = now
                case let .failure(error):
                    self.phase = .error(error.localizedDescription)
                }
                self.render()
            }
        }
    }

    @objc private func searchChanged() {
        self.searchQuery = self.searchField.text ?? ""
        self.render()
    }

    @objc private func sortTapped(_ sender: UIButton) {
        if let order = BeyGramMihomoSortOrder(rawValue: Int32(sender.tag)) {
            self.sortOrder = order
            self.render()
        }
    }

    @objc private func measureDelaysTapped() {
        guard !self.isBusy && !self.isMeasuringDelays else { return }
        self.isMeasuringDelays = true
        self.render()
        BeyGramMihomoRuntime.shared.controller.measureDelays { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMeasuringDelays = false
                switch result {
                case let .success(delays):
                    self.delays = delays
                case let .failure(error):
                    self.phase = .error(error.localizedDescription)
                }
                self.render()
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

public func beyGramMihomoController(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    presentationData: PresentationData,
    updatedPresentationData: Signal<PresentationData, NoError>
) -> ViewController {
    return BeyGramMihomoViewControllerImpl(
        accountManager: accountManager,
        presentationData: presentationData,
        updatedPresentationData: updatedPresentationData
    )
}
