import Foundation

/// BeyGram bug report client model (contract: BeyGram-Diagnostics-Server README, `POST /api/v1/bug-reports`).
///
/// Pure logic: builds the `/report` command, the report body within the server's limits, and the
/// upload request. Sending, the `/report` chat flow and the UI live in the app layer.
public enum BugReportEventKind: String, Codable, CaseIterable {
    case connection, network, vpn, tdlib, update, error, performance, ui, notification, other
}

public enum BugReportSeverity: String, Codable, CaseIterable {
    case debug, info, warning, error, critical
}

public struct BugReportEvent: Codable, Equatable {
    public var kind: BugReportEventKind
    public var severity: BugReportSeverity
    public var code: String
    public var message: String
    public var attrs: [String: String]
    /// Position in the process event log (`seq` on the wire). Nil for an event that did not come from the log.
    public var seq: Int64?
    /// Seconds since 1970 with a fraction (`at` on the wire). Nil for an event that did not come from the log.
    public var at: Double?

    public init(
        kind: BugReportEventKind,
        severity: BugReportSeverity,
        code: String,
        message: String = "",
        attrs: [String: String] = [:],
        seq: Int64? = nil,
        at: Double? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.code = code
        self.message = message
        self.attrs = attrs
        self.seq = seq
        self.at = at
    }
}

/// Fixed, non-secret client metadata. Only these fields are sent.
public struct BugReportClientMeta: Codable, Equatable {
    public var appVersion: String?
    public var appVersionCode: Int?
    public var platform: String?
    public var osVersion: String?
    public var deviceModel: String?
    public var locale: String?
    public var vpnActive: Bool?
    public var proxyEnabled: Bool?
    public var tdlibVersion: String?
    public var eventCountTotal: Int?
    /// True when the event log has dropped events since launch, or this report had to drop some to fit.
    public var bufferOverflowed: Bool?

    public init(
        appVersion: String? = nil, appVersionCode: Int? = nil, platform: String? = nil, osVersion: String? = nil,
        deviceModel: String? = nil, locale: String? = nil, vpnActive: Bool? = nil, proxyEnabled: Bool? = nil,
        tdlibVersion: String? = nil, eventCountTotal: Int? = nil, bufferOverflowed: Bool? = nil
    ) {
        self.appVersion = appVersion
        self.appVersionCode = appVersionCode
        self.platform = platform
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.locale = locale
        self.vpnActive = vpnActive
        self.proxyEnabled = proxyEnabled
        self.tdlibVersion = tdlibVersion
        self.eventCountTotal = eventCountTotal
        self.bufferOverflowed = bufferOverflowed
    }

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case appVersionCode = "app_version_code"
        case platform
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case locale
        case vpnActive = "vpn_active"
        case proxyEnabled = "proxy_enabled"
        case tdlibVersion = "tdlib_version"
        case eventCountTotal = "event_count_total"
        case bufferOverflowed = "buffer_overflowed"
    }
}

public struct BugReportBody: Codable, Equatable {
    public static let maxBodyBytes = 256 * 1024
    /// The client's own budget for the encoded body, under the server limit (Android parity: 240 KiB).
    public static let clientBudgetBytes = 240 * 1024
    public static let maxDescriptionCharacters = 2000
    public static let maxSummaryCharacters = 8000
    public static let maxEvents = 2000
    public static let maxEventMessageCharacters = 500
    /// Attributes kept per event, in key order (Android parity: 24).
    public static let maxEventAttributes = 24
    public static let maxAttrValueCharacters = 200
    public static let maxAttrKeyCharacters = 64
    public static let maxCodeCharacters = 200

    public var schemaVersion: Int = 1
    public var reportId: String
    public var description: String
    public var summary: String?
    public var clientMeta: BugReportClientMeta
    public var events: [BugReportEvent]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case reportId = "report_id"
        case description
        case summary
        case clientMeta = "client_meta"
        case events
    }

    /// The bytes that the size check measures and the upload sends. Keys are sorted, so one body always encodes the same way.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

public enum BugReportError: Error, Equatable {
    case emptyDescription
    case bodyTooLarge
    case invalidNonce
}

public enum BugReportBuilder {
    /// Builds a body that respects every client limit and reports whether anything was dropped.
    ///
    /// Pass the events as they are: each one is redacted here, once (see `BugReportPrivacy`). Text is cut to the schema
    /// limits, events are kept newest first (the last events in the array are the newest), and the encoded size must fit
    /// `BugReportBody.clientBudgetBytes`, dropping the oldest events until it does.
    public static func makeBody(
        reportId: String,
        description: String,
        summary: String?,
        meta: BugReportClientMeta,
        events: [BugReportEvent]
    ) throws -> (body: BugReportBody, droppedEvents: Int) {
        let trimmedDescription = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(BugReportBody.maxDescriptionCharacters))
        guard !trimmedDescription.isEmpty else {
            throw BugReportError.emptyDescription
        }
        let clampedSummary = summary.map { String($0.prefix(BugReportBody.maxSummaryCharacters)) }
        var kept = events.suffix(BugReportBody.maxEvents).map(sanitize)
        var meta = meta
        if meta.eventCountTotal == nil {
            meta.eventCountTotal = events.count
        }

        var dropped = events.count - kept.count
        while true {
            let body = BugReportBody(
                reportId: reportId,
                description: trimmedDescription,
                summary: clampedSummary,
                clientMeta: meta,
                events: kept
            )
            if try body.encodedJSON().count <= BugReportBody.clientBudgetBytes {
                return (body, dropped)
            }
            if kept.isEmpty {
                throw BugReportError.bodyTooLarge
            }
            // Drop the oldest quarter (at least one event) and measure again, as the Android client does.
            let step = max(1, kept.count / 4)
            kept.removeFirst(step)
            dropped += step
        }
    }

    /// Redacts one event and applies the schema limits. Redaction runs before each cut, so a secret never
    /// reaches the cut as a fragment that the patterns cannot match.
    static func sanitize(_ event: BugReportEvent) -> BugReportEvent {
        var attrs: [String: String] = [:]
        for (key, value) in event.attrs.sorted(by: { $0.key < $1.key }).prefix(BugReportBody.maxEventAttributes) {
            let cleanKey = BugReportPrivacy.sanitize(key, maxLength: BugReportBody.maxAttrKeyCharacters)
            guard !cleanKey.isEmpty else {
                continue
            }
            attrs[cleanKey] = BugReportPrivacy.sanitize(value, maxLength: BugReportBody.maxAttrValueCharacters)
        }
        return BugReportEvent(
            kind: event.kind,
            severity: event.severity,
            code: BugReportPrivacy.sanitize(event.code, maxLength: BugReportBody.maxCodeCharacters),
            message: BugReportPrivacy.sanitize(event.message, maxLength: BugReportBody.maxEventMessageCharacters),
            attrs: attrs,
            seq: event.seq,
            at: event.at
        )
    }

    /// `/report <nonce>` as typed in the report bot chat. Returns the nonce or nil.
    public static func parseReportCommand(_ text: String) -> String? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count == 2, parts[0] == "/report" else {
            return nil
        }
        let nonce = String(parts[1])
        return isValidNonce(nonce) ? nonce : nil
    }

    /// Nonce: 32 random bytes encoded as URL-safe base64 without padding (43 characters).
    public static func isValidNonce(_ nonce: String) -> Bool {
        guard nonce.count == 43 else {
            return false
        }
        return nonce.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public static func makeUploadRequest(baseURL: URL, nonce: String, body: BugReportBody) throws -> URLRequest {
        guard isValidNonce(nonce) else {
            throw BugReportError.invalidNonce
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/bug-reports"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(nonce)", forHTTPHeaderField: "Authorization")
        request.httpBody = try body.encodedJSON()
        return request
    }
}
