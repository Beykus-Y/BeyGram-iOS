import Foundation

/// Client state machine for sending a bug report (contract: BeyGram-Diagnostics-Server README).
///
/// Flow: the user starts a report, the app creates a report id and asks the user to send
/// `/report` to the report bot. The bot answers with a nonce, which the user pastes back. The app
/// uploads with that nonce as the Bearer token. Pure reducer: the app runs the effects.
public enum BugReportFlowState: Equatable {
    case idle
    case awaitingNonce(reportId: String)
    case uploading(reportId: String, nonce: String)
    case delivered(reportId: String, statusToken: String)
    case failed(reportId: String, reason: BugReportFailure)
}

public enum BugReportFailure: Equatable {
    /// 401: the nonce is wrong or expired. The user has to ask the bot for a new one.
    case nonceRejected
    /// 403: the account is not allowed to send reports, or the limit was reached.
    case notAllowedOrLimited
    /// 409: the nonce was already bound to another report.
    case conflict
    /// 413: the body is too large. Retrying the same body will not help.
    case tooLarge
    /// 422: the server rejected the body schema.
    case invalidBody
    /// Network failure or any other status. Retrying may help.
    case transient
}

public enum BugReportFlowEvent: Equatable {
    case start
    case nonceReceived(String)
    case uploadAccepted(statusToken: String)
    case uploadFailed(httpStatus: Int?)
    case cancel
}

public enum BugReportFlow {
    public static func reduce(_ state: BugReportFlowState, _ event: BugReportFlowEvent, makeReportId: () -> String = { UUID().uuidString }) -> BugReportFlowState {
        switch (state, event) {
        case (.idle, .start), (.failed, .start), (.delivered, .start):
            return .awaitingNonce(reportId: makeReportId())
        case (.awaitingNonce(let reportId), .nonceReceived(let nonce)):
            guard BugReportBuilder.isValidNonce(nonce) else {
                return .failed(reportId: reportId, reason: .nonceRejected)
            }
            return .uploading(reportId: reportId, nonce: nonce)
        case (.uploading(let reportId, _), .uploadAccepted(let token)):
            return .delivered(reportId: reportId, statusToken: token)
        case (.uploading(let reportId, _), .uploadFailed(let status)):
            return .failed(reportId: reportId, reason: failure(forHTTPStatus: status))
        case (.awaitingNonce, .cancel), (.uploading, .cancel), (.failed, .cancel):
            return .idle
        default:
            return state
        }
    }

    public static func failure(forHTTPStatus status: Int?) -> BugReportFailure {
        switch status {
        case 401: return .nonceRejected
        case 403: return .notAllowedOrLimited
        case 409: return .conflict
        case 413: return .tooLarge
        case 422: return .invalidBody
        default: return .transient
        }
    }

    /// Only transient failures and an expired nonce are worth retrying; the report id stays the same
    /// because the server is idempotent for the same report id.
    public static func canRetry(_ failure: BugReportFailure) -> Bool {
        failure == .transient || failure == .nonceRejected
    }
}
