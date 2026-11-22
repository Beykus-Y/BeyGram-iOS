import Foundation

/// One time-synced line of lyrics.
public struct BGYandexLyricLine: Equatable {
    public let timeMs: Int64
    public let text: String

    public init(timeMs: Int64, text: String) {
        self.timeMs = timeMs
        self.text = text
    }
}

/// Lyrics of a track: time-synced lines, or plain text when there are no time tags.
public struct BGYandexLyrics: Equatable {
    /// Time-synced lines, empty when the track has only plain text.
    public let lines: [BGYandexLyricLine]
    /// Plain text, used when `lines` is empty.
    public let plainText: String?
    /// Rights holder of the text, shown under the lyrics as the service requires.
    public let copyrightHolder: String?

    public init(lines: [BGYandexLyricLine], plainText: String?, copyrightHolder: String?) {
        self.lines = lines
        self.plainText = plainText
        self.copyrightHolder = copyrightHolder
    }

    public var isSynced: Bool {
        return !lines.isEmpty
    }
}

/// Reads LRC text (port of `YandexSigning.parseLrc` and the plain-text rule of `YandexApi.kt`).
public enum BGYandexLRC {
    /// `[mm:ss]`, `[mm:ss.x]`, `[mm:ss.xx]`, `[mm:ss.xxx]` (a colon also works as the separator).
    private static let tagPattern = "\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"

    public static func lyrics(from text: String, copyrightHolder: String?) -> BGYandexLyrics {
        let lines = parse(text)
        return BGYandexLyrics(lines: lines, plainText: lines.isEmpty ? plainText(text) : nil, copyrightHolder: copyrightHolder)
    }

    /// Lines with their time tags, sorted by time (equal times keep the file's order). A line may carry several tags.
    /// Metadata tags such as `[ar:...]` are skipped, and so are lines without text.
    public static func parse(_ text: String) -> [BGYandexLyricLine] {
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else {
            return []
        }
        var collected: [(index: Int, line: BGYandexLyricLine)] = []
        for raw in text.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else {
                continue
            }
            let contentStart = last.range.location + last.range.length
            let content = ns.substring(from: contentStart).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                continue
            }
            for match in matches {
                let minutes = Int64(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Int64(ns.substring(with: match.range(at: 2))) ?? 0
                let time = minutes * 60_000 + seconds * 1_000 + fractionMs(match, in: ns)
                collected.append((index: collected.count, line: BGYandexLyricLine(timeMs: time, text: content)))
            }
        }
        let sorted = collected.sorted { (lhs, rhs) -> Bool in
            if lhs.line.timeMs != rhs.line.timeMs {
                return lhs.line.timeMs < rhs.line.timeMs
            }
            return lhs.index < rhs.index
        }
        return sorted.map { $0.line }
    }

    /// The fraction of a second in milliseconds: `5` is 500, `05` is 50, `500` is 500 (padded on the right, three digits at most).
    private static func fractionMs(_ match: NSTextCheckingResult, in ns: NSString) -> Int64 {
        let range = match.range(at: 3)
        if range.location == NSNotFound || range.length == 0 {
            return 0
        }
        let digits = ns.substring(with: range)
        let padded = digits + String(repeating: "0", count: max(0, 3 - digits.count))
        return Int64(String(padded.prefix(3))) ?? 0
    }

    /// The text without time tags, lines trimmed, blank lines and metadata lines dropped. Nil when nothing is left.
    public static func plainText(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }
        let joined = lines.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}
