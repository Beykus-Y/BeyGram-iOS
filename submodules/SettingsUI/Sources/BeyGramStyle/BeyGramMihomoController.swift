import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
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

private struct BeyGramMihomoScreenState: Equatable {
    var subscriptionText: String
    var revealSubscription: Bool = false
    var lastUpdatedAt: Date?
    var phase: BeyGramMihomoConnectionPhase
    var isUpdatingSubscription: Bool = false
    var isMeasuringDelays: Bool = false
    var serverNames: [String]
    var selectedNode: String?
    var autoSelect: Bool = false
    var delays: [String: Int] = [:]
    var searchQuery: String = ""
    var sortOrder: BeyGramMihomoSortOrder = .original

    var isBusy: Bool {
        switch self.phase {
        case .connecting, .reconnecting:
            return true
        default:
            return self.isUpdatingSubscription || self.isMeasuringDelays
        }
    }

    var isConnected: Bool {
        if case .connected = self.phase {
            return true
        }
        return false
    }
}

private final class BeyGramMihomoScreenArguments {
    let toggleConnection: () -> Void
    let toggleRevealSubscription: () -> Void
    let subscriptionUpdated: (String) -> Void
    let saveSubscription: () -> Void
    let searchUpdated: (String) -> Void
    let openSortPicker: () -> Void
    let selectNode: (String) -> Void
    let measureDelays: () -> Void
    let toggleAutoSelect: (Bool) -> Void

    init(
        toggleConnection: @escaping () -> Void,
        toggleRevealSubscription: @escaping () -> Void,
        subscriptionUpdated: @escaping (String) -> Void,
        saveSubscription: @escaping () -> Void,
        searchUpdated: @escaping (String) -> Void,
        openSortPicker: @escaping () -> Void,
        selectNode: @escaping (String) -> Void,
        measureDelays: @escaping () -> Void,
        toggleAutoSelect: @escaping (Bool) -> Void
    ) {
        self.toggleConnection = toggleConnection
        self.toggleRevealSubscription = toggleRevealSubscription
        self.subscriptionUpdated = subscriptionUpdated
        self.saveSubscription = saveSubscription
        self.searchUpdated = searchUpdated
        self.openSortPicker = openSortPicker
        self.selectNode = selectNode
        self.measureDelays = measureDelays
        self.toggleAutoSelect = toggleAutoSelect
    }
}

private enum BeyGramMihomoSection: Int32 {
    case connection
    case subscription
    case servers
    case details
}

private enum BeyGramMihomoEntryId: Hashable {
    case index(Int32)
    case node(String)
}

private enum BeyGramMihomoEntry: Equatable, ItemListNodeEntry {
    case statusRow(PresentationTheme, String, String)
    case activeServerRow(PresentationTheme, String, String)
    case latencyRow(PresentationTheme, String, String)
    case primaryAction(PresentationTheme, String, Bool, Bool)
    case errorBanner(PresentationTheme, String)

    case subscriptionHeader(PresentationTheme, String)
    case subscriptionMasked(PresentationTheme, String, String)
    case subscriptionField(PresentationTheme, String, String, String)
    case subscriptionToggleReveal(PresentationTheme, String)
    case subscriptionUpdate(PresentationTheme, String, Bool)
    case subscriptionMeta(PresentationTheme, String)

    case serversHeader(PresentationTheme, String)
    case serverSearch(PresentationTheme, String, String)
    case sortPicker(PresentationTheme, String, String)
    case autoSelect(PresentationTheme, String, Bool)
    case measureDelays(PresentationTheme, String, Bool)
    case node(Int, PresentationTheme, String, String?, Bool)
    case emptyServers(PresentationTheme, String)

    case detailsHeader(PresentationTheme, String)
    case localAddress(PresentationTheme, String, String)
    case backgroundNote(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .statusRow, .activeServerRow, .latencyRow, .primaryAction, .errorBanner:
            return BeyGramMihomoSection.connection.rawValue
        case .subscriptionHeader, .subscriptionMasked, .subscriptionField, .subscriptionToggleReveal, .subscriptionUpdate, .subscriptionMeta:
            return BeyGramMihomoSection.subscription.rawValue
        case .serversHeader, .serverSearch, .sortPicker, .autoSelect, .measureDelays, .node, .emptyServers:
            return BeyGramMihomoSection.servers.rawValue
        case .detailsHeader, .localAddress, .backgroundNote:
            return BeyGramMihomoSection.details.rawValue
        }
    }

    var stableId: BeyGramMihomoEntryId {
        switch self {
        case .statusRow: return .index(0)
        case .activeServerRow: return .index(1)
        case .latencyRow: return .index(2)
        case .primaryAction: return .index(3)
        case .errorBanner: return .index(4)

        case .subscriptionHeader: return .index(10)
        case .subscriptionMasked: return .index(11)
        case .subscriptionField: return .index(12)
        case .subscriptionToggleReveal: return .index(13)
        case .subscriptionUpdate: return .index(14)
        case .subscriptionMeta: return .index(15)

        case .serversHeader: return .index(20)
        case .serverSearch: return .index(21)
        case .sortPicker: return .index(22)
        case .autoSelect: return .index(23)
        case .measureDelays: return .index(24)
        case .emptyServers: return .index(25)
        case let .node(_, _, name, _, _): return .node(name)

        case .detailsHeader: return .index(100)
        case .localAddress: return .index(101)
        case .backgroundNote: return .index(102)
        }
    }

    private var order: Int {
        switch self {
        case .statusRow: return 0
        case .activeServerRow: return 1
        case .latencyRow: return 2
        case .primaryAction: return 3
        case .errorBanner: return 4

        case .subscriptionHeader: return 10
        case .subscriptionMasked: return 11
        case .subscriptionField: return 12
        case .subscriptionToggleReveal: return 13
        case .subscriptionUpdate: return 14
        case .subscriptionMeta: return 15

        case .serversHeader: return 20
        case .serverSearch: return 21
        case .sortPicker: return 22
        case .autoSelect: return 23
        case .measureDelays: return 24
        case .emptyServers: return 25
        case let .node(index, _, _, _, _): return 100 + index

        case .detailsHeader: return 10000
        case .localAddress: return 10001
        case .backgroundNote: return 10002
        }
    }

    static func == (lhs: BeyGramMihomoEntry, rhs: BeyGramMihomoEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.statusRow(lt, lTitle, lVal), .statusRow(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.activeServerRow(lt, lTitle, lVal), .activeServerRow(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.latencyRow(lt, lTitle, lVal), .latencyRow(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.primaryAction(lt, lTitle, lDestructive, lEnabled), .primaryAction(rt, rTitle, rDestructive, rEnabled)):
            return lt === rt && lTitle == rTitle && lDestructive == rDestructive && lEnabled == rEnabled
        case let (.errorBanner(lt, lText), .errorBanner(rt, rText)):
            return lt === rt && lText == rText
        case let (.subscriptionHeader(lt, lText), .subscriptionHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.subscriptionMasked(lt, lTitle, lVal), .subscriptionMasked(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.subscriptionField(lt, lTitle, lText, lPlaceholder), .subscriptionField(rt, rTitle, rText, rPlaceholder)):
            return lt === rt && lTitle == rTitle && lText == rText && lPlaceholder == rPlaceholder
        case let (.subscriptionToggleReveal(lt, lTitle), .subscriptionToggleReveal(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.subscriptionUpdate(lt, lTitle, lEnabled), .subscriptionUpdate(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.subscriptionMeta(lt, lText), .subscriptionMeta(rt, rText)):
            return lt === rt && lText == rText
        case let (.serversHeader(lt, lText), .serversHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.serverSearch(lt, lTitle, lText), .serverSearch(rt, rTitle, rText)):
            return lt === rt && lTitle == rTitle && lText == rText
        case let (.sortPicker(lt, lTitle, lVal), .sortPicker(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.autoSelect(lt, lTitle, lVal), .autoSelect(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.measureDelays(lt, lTitle, lEnabled), .measureDelays(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.node(lIdx, lt, lName, lSub, lChecked), .node(rIdx, rt, rName, rSub, rChecked)):
            return lIdx == rIdx && lt === rt && lName == rName && lSub == rSub && lChecked == rChecked
        case let (.emptyServers(lt, lText), .emptyServers(rt, rText)):
            return lt === rt && lText == rText
        case let (.detailsHeader(lt, lText), .detailsHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.localAddress(lt, lTitle, lVal), .localAddress(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.backgroundNote(lt, lText), .backgroundNote(rt, rText)):
            return lt === rt && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: BeyGramMihomoEntry, rhs: BeyGramMihomoEntry) -> Bool {
        return lhs.order < rhs.order
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramMihomoScreenArguments
        switch self {
        case let .statusRow(_, title, value),
             let .activeServerRow(_, title, value),
             let .latencyRow(_, title, value),
             let .subscriptionMasked(_, title, value),
             let .localAddress(_, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .primaryAction(_, title, destructive, enabled):
            let kind: ItemListActionKind
            if !enabled {
                kind = .disabled
            } else {
                kind = destructive ? .destructive : .generic
            }
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: kind,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled {
                        arguments.toggleConnection()
                    }
                }
            )
        case let .errorBanner(_, text), let .subscriptionMeta(_, text), let .emptyServers(_, text), let .backgroundNote(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .subscriptionHeader(_, text), let .serversHeader(_, text), let .detailsHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .subscriptionField(_, title, text, placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: text,
                placeholder: placeholder,
                type: .regular(capitalization: false, autocorrection: false),
                clearType: .always,
                sectionId: self.section,
                textUpdated: { newText in
                    arguments.subscriptionUpdated(newText)
                },
                action: {
                    arguments.saveSubscription()
                }
            )
        case let .subscriptionToggleReveal(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: arguments.toggleRevealSubscription
            )
        case let .subscriptionUpdate(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled {
                        arguments.saveSubscription()
                    }
                }
            )
        case let .serverSearch(_, text, placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: "", textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: text,
                placeholder: placeholder,
                type: .regular(capitalization: false, autocorrection: false),
                spacing: 0.0,
                clearType: .always,
                sectionId: self.section,
                textUpdated: { updated in
                    arguments.searchUpdated(updated)
                },
                action: {}
            )
        case let .sortPicker(_, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openSortPicker
            )
        case let .autoSelect(_, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.toggleAutoSelect(newValue)
                }
            )
        case let .measureDelays(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled {
                        arguments.measureDelays()
                    }
                }
            )
        case let .node(_, _, name, subtitle, checked):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: name,
                subtitle: subtitle,
                style: .left,
                checked: checked,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    arguments.selectNode(name)
                }
            )
        }
    }
}

private let lastSubscriptionUpdateKey = "beygram.mihomo.lastSubscriptionUpdate"

private func maskedSubscriptionSummary(_ source: String, languageCode: String?) -> String {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
        return "\(url.scheme ?? "https")://\(host)/•••"
    }
    return BeyGramL10n.shared.string(.mihomoSubscriptionHidden, languageCode: languageCode)
}

private func sortDisplayName(_ sort: BeyGramMihomoSortOrder, languageCode: String?) -> String {
    let l10n = BeyGramL10n.shared
    switch sort {
    case .original: return l10n.string(.mihomoSortDefault, languageCode: languageCode)
    case .name: return l10n.string(.mihomoSortName, languageCode: languageCode)
    case .latency: return l10n.string(.mihomoSortLatency, languageCode: languageCode)
    }
}

private func filteredAndSortedServers(state: BeyGramMihomoScreenState) -> [String] {
    let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let filtered = query.isEmpty
        ? state.serverNames
        : state.serverNames.filter { $0.lowercased().contains(query) }

    switch state.sortOrder {
    case .original:
        return filtered
    case .name:
        return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    case .latency:
        return filtered.sorted { lhs, rhs in
            let lDelay = state.delays[lhs]
            let rDelay = state.delays[rhs]
            switch (lDelay, rDelay) {
            case let (l?, r?):
                if l < 0 && r >= 0 { return false }
                if r < 0 && l >= 0 { return true }
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }
    }
}

private func beyGramMihomoEntries(presentationData: PresentationData, state: BeyGramMihomoScreenState) -> [BeyGramMihomoEntry] {
    let lang = presentationData.strings.primaryComponent.languageCode
    let l10n = BeyGramL10n.shared
    let theme = presentationData.theme
    var entries: [BeyGramMihomoEntry] = []

    // 1. Top Connection Block
    let statusValue: String
    switch state.phase {
    case .connected:
        statusValue = l10n.string(.mihomoStatusConnected, languageCode: lang)
    case .connecting:
        statusValue = l10n.string(.mihomoStatusConnecting, languageCode: lang)
    case .reconnecting:
        statusValue = l10n.string(.mihomoStatusReconnecting, languageCode: lang)
    case .disconnected:
        statusValue = l10n.string(.mihomoStatusDisconnected, languageCode: lang)
    case .error:
        statusValue = l10n.string(.mihomoStatusError, languageCode: lang)
    }
    entries.append(.statusRow(theme, l10n.string(.mihomoTitle, languageCode: lang), statusValue))

    if let activeNode = state.selectedNode, !activeNode.isEmpty {
        entries.append(.activeServerRow(theme, l10n.string(.mihomoActiveServer, languageCode: lang), activeNode))
        if let delay = state.delays[activeNode] {
            entries.append(.latencyRow(theme, l10n.string(.mihomoLatency, languageCode: lang), l10n.formatLatency(delay, languageCode: lang)))
        }
    }

    let actionTitle = state.isConnected
        ? l10n.string(.mihomoDisconnect, languageCode: lang)
        : l10n.string(.mihomoConnect, languageCode: lang)
    entries.append(.primaryAction(theme, actionTitle, state.isConnected, !state.isBusy))

    if case let .error(message) = state.phase, !message.isEmpty {
        entries.append(.errorBanner(theme, message))
    }

    // 2. Subscriptions Section
    entries.append(.subscriptionHeader(theme, l10n.string(.mihomoSectionSubscription, languageCode: lang).uppercased()))
    let hasSavedSubscription = !state.subscriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if hasSavedSubscription && !state.revealSubscription {
        entries.append(.subscriptionMasked(
            theme,
            l10n.string(.mihomoSubscriptionLinkLabel, languageCode: lang),
            maskedSubscriptionSummary(state.subscriptionText, languageCode: lang)
        ))
        entries.append(.subscriptionToggleReveal(theme, l10n.string(.mihomoSubscriptionReveal, languageCode: lang)))
    } else {
        entries.append(.subscriptionField(
            theme,
            l10n.string(.mihomoSubscriptionLinkLabel, languageCode: lang),
            state.subscriptionText,
            l10n.string(.mihomoSubscriptionPlaceholder, languageCode: lang)
        ))
        if hasSavedSubscription {
            entries.append(.subscriptionToggleReveal(theme, l10n.string(.mihomoSubscriptionHide, languageCode: lang)))
        }
    }

    let updateTitle = state.isUpdatingSubscription
        ? l10n.string(.commonLoading, languageCode: lang)
        : l10n.string(.mihomoSubscriptionUpdate, languageCode: lang)
    entries.append(.subscriptionUpdate(theme, updateTitle, !state.isBusy && hasSavedSubscription))

    var metaParts: [String] = []
    if !state.serverNames.isEmpty {
        metaParts.append(l10n.plural(.serversCount, count: state.serverNames.count, languageCode: lang))
    }
    if let lastUpdatedAt = state.lastUpdatedAt {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang == "ru" ? "ru_RU" : "en_US")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        metaParts.append(l10n.format(.mihomoSubscriptionLastUpdated, languageCode: lang, formatter.string(from: lastUpdatedAt)))
    } else if !state.serverNames.isEmpty {
        metaParts.append(l10n.string(.mihomoSubscriptionNeverUpdated, languageCode: lang))
    }
    if !metaParts.isEmpty {
        entries.append(.subscriptionMeta(theme, metaParts.joined(separator: " • ")))
    }

    // 3. Servers Section
    entries.append(.serversHeader(theme, l10n.string(.mihomoSectionServers, languageCode: lang).uppercased()))
    if state.serverNames.isEmpty {
        entries.append(.emptyServers(theme, l10n.string(.mihomoEmptyServers, languageCode: lang)))
    } else {
        if state.serverNames.count >= 6 || !state.searchQuery.isEmpty {
            entries.append(.serverSearch(theme, state.searchQuery, l10n.string(.mihomoSearchPlaceholder, languageCode: lang)))
        }
        entries.append(.sortPicker(theme, l10n.string(.mihomoSortTitle, languageCode: lang), sortDisplayName(state.sortOrder, languageCode: lang)))
        entries.append(.autoSelect(theme, l10n.string(.mihomoAutoSelect, languageCode: lang), state.autoSelect))
        if state.isConnected {
            let measureTitle = state.isMeasuringDelays
                ? l10n.string(.commonLoading, languageCode: lang)
                : l10n.string(.mihomoMeasureDelays, languageCode: lang)
            entries.append(.measureDelays(theme, measureTitle, !state.isBusy))
        }

        let visibleServers = filteredAndSortedServers(state: state)
        for (index, name) in visibleServers.enumerated() {
            let delaySubtitle = state.delays[name].map { l10n.formatLatency($0, languageCode: lang) }
            entries.append(.node(index, theme, name, delaySubtitle, state.selectedNode == name))
        }
    }

    // 4. Connection Details Section
    entries.append(.detailsHeader(theme, l10n.string(.mihomoSectionDetails, languageCode: lang).uppercased()))
    entries.append(.localAddress(
        theme,
        l10n.string(.mihomoLocalAddressTitle, languageCode: lang),
        "\(MihomoProxyController.inletHost):\(MihomoProxyController.inletPort)"
    ))
    entries.append(.backgroundNote(theme, l10n.string(.mihomoBackgroundLimitBody, languageCode: lang)))

    return entries
}

public func beyGramMihomoController(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    presentationData: PresentationData,
    updatedPresentationData: Signal<PresentationData, NoError>
) -> ViewController {
    let runtime = BeyGramMihomoRuntime.shared
    let initial = runtime.controller.currentState
    let savedTimestamp = UserDefaults.standard.object(forKey: lastSubscriptionUpdateKey) as? Date
    let initialState = BeyGramMihomoScreenState(
        subscriptionText: initial.subscriptionSource ?? "",
        lastUpdatedAt: savedTimestamp,
        phase: initial.isRunning ? .connected : .disconnected,
        serverNames: initial.serverNames,
        selectedNode: initial.selectedNode,
        autoSelect: initial.autoSelectEnabled
    )
    let stateValue = Atomic(value: initialState)
    let statePromise = ValuePromise<BeyGramMihomoScreenState>(initialState)
    let mutate: ((inout BeyGramMihomoScreenState) -> Void) -> Void = { change in
        let value = stateValue.modify { current in
            var next = current
            change(&next)
            return next
        }
        statePromise.set(value)
    }

    var presentControllerImpl: ((ViewController, Any?) -> Void)?

    let arguments = BeyGramMihomoScreenArguments(
        toggleConnection: {
            let current = stateValue.with { $0 }
            if current.isBusy {
                return
            }
            if current.isConnected {
                mutate { state in
                    state.phase = .reconnecting
                }
                runtime.disconnect(accountManager: accountManager) { result in
                    mutate { state in
                        switch result {
                        case .success:
                            state.phase = .disconnected
                        case let .failure(error):
                            state.phase = .error(error.localizedDescription)
                        }
                    }
                }
            } else {
                mutate { state in
                    state.phase = .connecting
                }
                runtime.connect(accountManager: accountManager) { result in
                    mutate { state in
                        switch result {
                        case .success:
                            state.phase = .connected
                        case let .failure(error):
                            state.phase = .error(error.localizedDescription)
                        }
                    }
                }
            }
        },
        toggleRevealSubscription: {
            mutate { state in
                state.revealSubscription.toggle()
            }
        },
        subscriptionUpdated: { text in
            mutate { state in
                state.subscriptionText = text
            }
        },
        saveSubscription: {
            let current = stateValue.with { $0 }
            if current.isBusy {
                return
            }
            mutate { state in
                state.isUpdatingSubscription = true
                if case .error = state.phase {
                    state.phase = .disconnected
                }
            }
            runtime.controller.saveSubscription(current.subscriptionText) { result in
                switch result {
                case let .success(names):
                    let now = Date()
                    UserDefaults.standard.set(now, forKey: lastSubscriptionUpdateKey)
                    mutate { state in
                        state.isUpdatingSubscription = false
                        state.serverNames = names
                        state.selectedNode = runtime.controller.currentState.selectedNode
                        state.delays = [:]
                        state.lastUpdatedAt = now
                        state.revealSubscription = false
                    }
                case let .failure(error):
                    mutate { state in
                        state.isUpdatingSubscription = false
                        state.phase = .error(error.localizedDescription)
                    }
                }
            }
        },
        searchUpdated: { query in
            mutate { state in
                state.searchQuery = query
            }
        },
        openSortPicker: {
            let actionSheet = ActionSheetController(presentationData: presentationData)
            let lang = presentationData.strings.primaryComponent.languageCode
            var items: [ActionSheetItem] = []
            for order in BeyGramMihomoSortOrder.allCases {
                items.append(ActionSheetButtonItem(title: sortDisplayName(order, languageCode: lang), color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    mutate { state in
                        state.sortOrder = order
                    }
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(actionSheet, nil)
        },
        selectNode: { name in
            if stateValue.with({ $0 }).isBusy {
                return
            }
            runtime.controller.selectNode(name) { result in
                mutate { state in
                    switch result {
                    case .success:
                        state.selectedNode = name
                    case let .failure(error):
                        state.phase = .error(error.localizedDescription)
                    }
                }
            }
        },
        measureDelays: {
            if stateValue.with({ $0 }).isBusy {
                return
            }
            mutate { state in
                state.isMeasuringDelays = true
            }
            runtime.controller.measureDelays { result in
                mutate { state in
                    state.isMeasuringDelays = false
                    switch result {
                    case let .success(delays):
                        state.delays = delays
                    case let .failure(error):
                        state.phase = .error(error.localizedDescription)
                    }
                }
            }
        },
        toggleAutoSelect: { enable in
            mutate { state in
                state.autoSelect = enable
            }
            runtime.setAutoSelect(enable)
        }
    )

    let signal = combineLatest(updatedPresentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(BeyGramL10n.shared.string(.mihomoTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: beyGramMihomoEntries(presentationData: presentationData, state: state),
            style: .blocks,
            ensureVisibleItemTag: nil
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(
        presentationData: ItemListPresentationData(presentationData),
        updatedPresentationData: updatedPresentationData |> map(ItemListPresentationData.init(_:)),
        state: signal,
        tabBarItem: nil
    )
    presentControllerImpl = { [weak controller] next, context in
        controller?.present(next, in: .window(.root), with: context)
    }
    return controller
}
