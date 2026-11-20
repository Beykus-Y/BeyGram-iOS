import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramDiagnostics

/// Report server for BeyGram. Set to the deployed Diagnostics server; this is the only place it is configured.
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
    case status
}

private enum ReportEntry: ItemListNodeEntry, Equatable {
    case instructions(String)
    case description(String)
    case nonce(String)
    case send(Bool)
    case status(String)

    var section: ItemListSectionId {
        switch self {
        case .instructions: return ReportSection.instructions.rawValue
        case .description, .nonce, .send: return ReportSection.form.rawValue
        case .status: return ReportSection.status.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .instructions: return 0
        case .description: return 1
        case .nonce: return 2
        case .send: return 3
        case .status: return 4
        }
    }

    static func < (lhs: ReportEntry, rhs: ReportEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ReportArguments
        switch self {
        case let .instructions(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .description(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "", textColor: .black), text: text, placeholder: "What went wrong", type: .regular(capitalization: true, autocorrection: true), spacing: 0.0, clearType: .always, enabled: true, sectionId: self.section, textUpdated: { updated in
                arguments.setDescription(updated)
            }, action: {})
        case let .nonce(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "", textColor: .black), text: text, placeholder: "Code from the report bot", type: .regular(capitalization: false, autocorrection: false), spacing: 0.0, clearType: .always, enabled: true, sectionId: self.section, textUpdated: { updated in
                arguments.setNonce(updated)
            }, action: {})
        case let .send(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Send report", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.send()
            })
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func statusText(for flow: BugReportFlowState) -> String? {
    switch flow {
    case .idle:
        return nil
    case .awaitingNonce:
        return "Send /report to the BeyGram report bot, then paste the code here."
    case .uploading:
        return "Sending…"
    case .delivered:
        return "Sent. Thank you."
    case let .failed(_, reason):
        switch reason {
        case .nonceRejected: return "The code is wrong or expired. Ask the bot for a new one."
        case .notAllowedOrLimited: return "This account cannot send reports right now, or the limit was reached."
        case .conflict: return "This code was already used. Ask the bot for a new one."
        case .tooLarge: return "The report is too large."
        case .invalidBody: return "The server rejected the report."
        case .transient: return "Network error. Try again."
        }
    }
}

/// Report screen. Sending uses the nonce from the report bot as the Bearer token; the flow reducer decides
/// the state, and the upload client maps the HTTP response to its events.
public func reportController(context: AccountContext, appVersion: String) -> ViewController {
    let state = ReportState()
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let bump: () -> Void = {
        counter += 1
        revision.set(counter)
    }
    let client = BugReportClient(baseURL: reportServerURL)

    let arguments = ReportArguments(setDescription: { text in
        state.description = text
    }, setNonce: { text in
        state.nonce = text
    }, send: {
        let description = state.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonce = state.nonce.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !state.isSending, !description.isEmpty, !nonce.isEmpty else {
            return
        }
        // A new report gets a new id. A retry after a failure keeps the id, since the server treats it as idempotent.
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
                let (body, _) = try BugReportBuilder.makeBody(reportId: id, description: description, summary: nil, meta: BugReportClientMeta(appVersion: appVersion), events: [])
                let event = await client.upload(body: body, nonce: sentNonce)
                state.flow = BugReportFlow.reduce(state.flow, event)
            } catch {
                state.flow = .failed(reportId: id, reason: .invalidBody)
            }
            state.isSending = false
            bump()
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
        |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Report a problem"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
            var entries: [ReportEntry] = [
                .instructions("Describe the problem, then send /report to the BeyGram report bot and paste the code it sends back. Reports may contain the text you typed here."),
                .description(state.description),
                .nonce(state.nonce),
                .send(!state.isSending && !state.nonce.isEmpty && !state.description.isEmpty)
            ]
            if let status = statusText(for: state.flow) {
                entries.append(.status(status))
            }
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
            return (controllerState, (listState, arguments))
        }

    return ItemListController(context: context, state: signal)
}
