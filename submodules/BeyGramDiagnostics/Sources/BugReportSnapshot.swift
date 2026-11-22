import Foundation

/// Builds the report's events and summary from the process event log (port of Android `ReportSnapshot`).
///
/// `BugReportBuilder.makeBody` redacts the events it is given, and `summary(for:)` redacts its own copy of them.
/// Every raw field is therefore redacted once in each output. Nothing is redacted a second time: the redaction is
/// not idempotent (see `BugReportPrivacy.redact`), so a second pass would corrupt the markers.
public enum BugReportSnapshot {
    /// How many of the newest events the summary lists (Android parity).
    public static let summaryEventLimit = 120

    /// The log's events, oldest first, with their sequence numbers and times. Not redacted: `BugReportBuilder` does that.
    public static func events(from log: BugReportEventLog = .shared) -> [BugReportEvent] {
        log.snapshot().map { entry in
            BugReportEvent(
                kind: entry.kind,
                severity: entry.severity,
                code: entry.code,
                message: entry.message,
                attrs: entry.attrs,
                seq: entry.seq,
                at: entry.at
            )
        }
    }

    /// A short text for a person reading the report: the newest events, one line each. Nil when there are none.
    public static func summary(for events: [BugReportEvent]) -> String? {
        guard !events.isEmpty else {
            return nil
        }
        let lines = events.suffix(summaryEventLimit).map { event in
            line(for: BugReportBuilder.sanitize(event))
        }
        let text = BugReportPrivacy.stripControls(lines.joined(separator: "\n"))
        return BugReportPrivacy.truncate(text, maxLength: BugReportBody.maxSummaryCharacters)
    }

    /// The report body for the process log: its events (the newest are kept when the budget is tight), the summary,
    /// and the client meta with the total recorded and the overflow flag. `description` is sent as typed.
    public static func makeBody(
        reportId: String,
        description: String,
        meta: BugReportClientMeta,
        log: BugReportEventLog = .shared
    ) throws -> (body: BugReportBody, droppedEvents: Int) {
        let logEvents = events(from: log)
        var meta = meta
        meta.eventCountTotal = Int(clamping: log.totalRecorded)
        meta.bufferOverflowed = log.hasOverflowed
        let built = try BugReportBuilder.makeBody(
            reportId: reportId,
            description: description,
            summary: summary(for: logEvents),
            meta: meta,
            events: logEvents
        )
        var body = built.body
        if built.droppedEvents > 0 {
            body.clientMeta.bufferOverflowed = true
        }
        return (body, built.droppedEvents)
    }

    /// One summary line. The event must already be redacted.
    private static func line(for event: BugReportEvent) -> String {
        var text = "- "
        text += event.at.map { formatMoment($0) } ?? "--:--:--"
        text += " " + event.kind.rawValue
        if !event.code.isEmpty {
            text += "/" + event.code
        }
        text += " "
        if event.severity != .info {
            text += "(" + event.severity.rawValue + ") "
        }
        text += event.message
        if !event.attrs.isEmpty {
            let pairs = event.attrs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            text += " [" + pairs.joined(separator: ", ") + "]"
        }
        return text
    }

    /// UTC time of day, as the Android summary prints it.
    private static func formatMoment(_ seconds: Double) -> String {
        let whole = Int(seconds)
        let hours = (whole % 86400) / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        return [hours, minutes, secs].map { twoDigits($0) }.joined(separator: ":")
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
