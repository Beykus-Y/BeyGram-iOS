import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramDiagnostics
import BeyGramKit

private let reportServerURL = URL(string: "https://beygram.beykus.fun")!

private final class ReportState {
    var description = ""
    var nonce = ""
    var flow: BugReportFlowState = .idle
    var isSending = false
}

private final class ReportArguments {
    let setDescription: (String) -> Void
    let setNonce: (String) -> Void
    let send: () -> Void

    init(setDescription: @escaping (String) -> Void, setNonce: @escaping (String) -> Void, send: @escaping () -> Void) {
        self.setDescription = setDescription
        self.setNonce = setNonce
        self.send = send
    }
}

private enum ReportSection: Int32 {
    case instructions
    case form
    case preview
    case status
}

private enum ReportEntry: ItemListNodeEntry, Equatable {
    case instructions(PresentationTheme, String)
    case description(PresentationTheme, String, String)
    case nonce(PresentationTheme, String, String)
    case send(PresentationTheme, String, Bool)
    case previewHeader(PresentationTheme, String)
    case previewBody(PresentationTheme, String)
    case status(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .instructions: return ReportSection.instructions.rawValue
        case .description, .nonce, .send: return ReportSection.form.rawValue
        case .previewHeader, .previewBody: return ReportSection.preview.rawValue
        case .status: return ReportSection.status.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .instructions: return 0
        case .description: return 1
        case .nonce: return 2
        case .send: return 3
        case .previewHeader: return 4
        case .previewBody: return 5
        case .status: return 6
        }
    }

    static func == (lhs: ReportEntry, rhs: ReportEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.instructions(lt, lText), .instructions(rt, rText)):
            return lt === rt && lText == rText
        case let (.description(lt, lText, lPlaceholder), .description(rt, rText, rPlaceholder)):
            return lt === rt && lText == rText && lPlaceholder == rPlaceholder
        case let (.nonce(lt, lText, lPlaceholder), .nonce(rt, rText, rPlaceholder)):
            return lt === rt && lText == rText && lPlaceholder == rPlaceholder
        case let (.send(lt, lTitle, lEnabled), .send(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.previewHeader(lt, lText), .previewHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.previewBody(lt, lText), .previewBody(rt, rText)):
            return lt === rt && lText == rText
        case let (.status(lt, lText), .status(rt, rText)):
            return lt === rt && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: ReportEntry, rhs: ReportEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ReportArguments
        switch self {
        case let .instructions(_, text), let .previewBody(_, text), let .status(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .previewHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .description(_, text, placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: "", textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: text,
                placeholder: placeholder,
                type: .regular(capitalization: true, autocorrection: true),
                spacing: 0.0,
                clearType: .always,
                enabled: true,
                sectionId: self.section,
                textUpdated: arguments.setDescription,
                action: {}
            )
        case let .nonce(_, text, placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: "", textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: text,
                placeholder: placeholder,
                type: .regular(capitalization: false, autocorrection: false),
                spacing: 0.0,
                clearType: .always,
                enabled: true,
                sectionId: self.section,
                textUpdated: arguments.setNonce,
                action: {}
            )
        case let .send(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.send() }
                }
            )
        }
    }
}

private func localizedStatusText(for flow: BugReportFlowState, languageCode: String?) -> String? {
    let l10n = BeyGramL10n.shared
    let isRu = BeyGramL10n.normalizeLanguageCode(languageCode) == "ru"
    switch flow {
    case .idle:
        return nil
    case .awaitingNonce:
        return l10n.string(.diagnosticsStageAwaitingNonce, languageCode: languageCode)
    case .uploading:
        return l10n.string(.diagnosticsStageUploading, languageCode: languageCode)
    case .delivered:
        return l10n.string(.diagnosticsStageDelivered, languageCode: languageCode)
    case let .failed(_, reason):
        switch reason {
        case .nonceRejected:
            return isRu ? "Код неверный или истёк. Запросите новый у бота." : "The code is wrong or expired. Ask the bot for a new one."
        case .notAllowedOrLimited:
            return isRu ? "Отправка отчётов временно недоступна или достигнут лимит." : "This account cannot send reports right now, or the limit was reached."
        case .conflict:
            return isRu ? "Этот код уже использован. Запросите новый у бота." : "This code was already used. Ask the bot for a new one."
        case .tooLarge:
            return isRu ? "Отчёт слишком большой." : "The report is too large."
        case .invalidBody:
            return isRu ? "Сервер отклонил отчёт." : "The server rejected the report."
        case .transient:
            return isRu ? "Ошибка сети. Попробуйте ещё раз." : "Network error. Try again."
        }
    }
}

/// Diagnostics and bug report screen with structured form, data preview, and privacy redaction notice.
public func reportController(context: AccountContext, appVersion: String) -> ViewController {
    let state = ReportState()
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let bump: () -> Void = {
        counter += 1
        revision.set(counter)
    }
    let client = BugReportClient(baseURL: reportServerURL)

    let arguments = ReportArguments(
        setDescription: { text in
            state.description = text
            bump()
        },
        setNonce: { text in
            state.nonce = text
            bump()
        },
        send: {
            let description = state.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let nonce = state.nonce.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !state.isSending, !description.isEmpty, !nonce.isEmpty else {
                return
            }
            let reportId: String
            switch state.flow {
            case let .awaitingNonce(id), let .failed(id, _):
                reportId = id
            case .idle, .delivered, .uploading:
                guard case let .awaitingNonce(id) = BugReportFlow.reduce(.idle, .start) else {
                    return
                }
                reportId = id
            }
            state.flow = .awaitingNonce(reportId: reportId)
            state.flow = BugReportFlow.reduce(state.flow, .nonceReceived(nonce))
            guard case let .uploading(id, sentNonce) = state.flow else {
                bump()
                return
            }
            state.isSending = true
            bump()
            Task { @MainActor in
                do {
                    let (body, _) = try BugReportSnapshot.makeBody(reportId: id, description: description, meta: BugReportDeviceInfo.current())
                    let event = await client.upload(body: body, nonce: sentNonce)
                    state.flow = BugReportFlow.reduce(state.flow, event)
                } catch {
                    state.flow = .failed(reportId: id, reason: .invalidBody)
                }
                state.isSending = false
                bump()
            }
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let theme = presentationData.theme
        let canSend = !state.isSending
            && !state.nonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        var entries: [ReportEntry] = [
            .instructions(theme, l10n.string(.diagnosticsInstructions, languageCode: lang)),
            .description(theme, state.description, l10n.string(.diagnosticsDescriptionPlaceholder, languageCode: lang)),
            .nonce(theme, state.nonce, l10n.string(.diagnosticsNoncePlaceholder, languageCode: lang)),
            .send(theme, state.isSending ? l10n.string(.diagnosticsStageUploading, languageCode: lang) : l10n.string(.diagnosticsSendButton, languageCode: lang), canSend),
            .previewHeader(theme, l10n.string(.diagnosticsPreviewTitle, languageCode: lang).uppercased()),
            .previewBody(theme, l10n.string(.diagnosticsPreviewBody, languageCode: lang))
        ]
        if let status = localizedStatusText(for: state.flow, languageCode: lang) {
            entries.append(.status(theme, status))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(l10n.string(.diagnosticsTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
