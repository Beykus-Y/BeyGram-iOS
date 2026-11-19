import Foundation

/// Sends a bug report with `URLSession`. Maps the response to the flow's events, so the caller feeds
/// them to `BugReportFlow.reduce`. The base URL comes from the app's configuration, not from this module.
public final class BugReportClient {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Returns `.uploadAccepted` with the status token on 202, `.uploadFailed` otherwise.
    /// Transport errors count as `.uploadFailed(httpStatus: nil)`, which the flow treats as transient.
    public func upload(body: BugReportBody, nonce: String) async -> BugReportFlowEvent {
        do {
            let request = try BugReportBuilder.makeUploadRequest(baseURL: baseURL, nonce: nonce, body: body)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .uploadFailed(httpStatus: nil)
            }
            guard http.statusCode == 202 else {
                return .uploadFailed(httpStatus: http.statusCode)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["status_token"] as? String, !token.isEmpty else {
                return .uploadFailed(httpStatus: nil)
            }
            return .uploadAccepted(statusToken: token)
        } catch {
            return .uploadFailed(httpStatus: nil)
        }
    }
}
