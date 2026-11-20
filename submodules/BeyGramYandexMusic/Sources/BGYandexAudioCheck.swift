import Foundation

/// Decides, from the bytes and the response headers, whether a downloaded body can be a track. It runs before a file is kept,
/// and again before a cached file is played. A 200 answer can still carry an error page, a JSON body or a cut-off file, and
/// none of those may be stored as a track. AVFoundation is the real reader; this check only refuses what cannot be an MP3.
public enum BGYandexAudioCheck {
    /// The most of a file's start that the check reads.
    public static let headerByteCount = 4096

    /// A body smaller than this is an error answer, not a track.
    public static let minimumByteCount: Int64 = 8 * 1024

    /// What the check found. Only `audio` lets a file be kept.
    public enum Verdict: String, Equatable {
        case audio
        /// Shorter than any track: an error answer or an empty file.
        case tooSmall
        /// The server said the body is text, JSON, XML or HTML.
        case nonAudioType
        /// The file does not start with an ID3 tag or an MPEG frame.
        case notMP3
        /// The body is shorter than the length the server announced.
        case cutOff
    }

    /// What a checked file looked like, for a diagnostic. It holds sizes, the first bytes and the media type, and never the
    /// link, the token or the file's path.
    public struct Probe: Equatable, CustomStringConvertible {
        public let verdict: Verdict
        public let byteCount: Int64
        /// The Content-Length the server sent, or -1 when it sent none or the body was encoded.
        public let expectedLength: Int64
        /// The first four bytes as lowercase hex: `49443303` for an ID3 tag, `fffb9064` for an MPEG frame, `3c21444f` for `<!DO`.
        public let leadingBytesHex: String
        /// The media type without parameters, lowercased, or nil when the server sent none.
        public let mediaType: String?

        public var description: String {
            return "verdict=\(verdict.rawValue) bytes=\(byteCount) expected=\(expectedLength) head=\(leadingBytesHex) type=\(mediaType ?? "none")"
        }
    }

    /// Checks a finished download: the media type, the size, the announced length and the start of the file.
    /// `expectedLength` is -1 when the server announced no length, or when the body was encoded and no longer has that length.
    public static func inspect(header: Data, byteCount: Int64, expectedLength: Int64, contentType: String?) -> Probe {
        let mediaType = parseMediaType(contentType)
        let verdict: Verdict
        if let type = mediaType, isNonAudioType(type) {
            verdict = .nonAudioType
        } else if byteCount < minimumByteCount {
            verdict = .tooSmall
        } else if expectedLength >= 0 && expectedLength != byteCount {
            verdict = .cutOff
        } else if looksLikeMP3(header) {
            verdict = .audio
        } else {
            verdict = .notMP3
        }
        return Probe(verdict: verdict,
                     byteCount: byteCount,
                     expectedLength: expectedLength,
                     leadingBytesHex: hexPrefix(header),
                     mediaType: mediaType)
    }

    /// Checks a file already on disk, such as a cached track. The announced length was not kept, so the size and the start decide.
    public static func inspect(fileAt url: URL) -> Probe {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        var header = Data()
        if let handle = try? FileHandle(forReadingFrom: url) {
            header = (try? handle.read(upToCount: headerByteCount)) ?? Data()
            try? handle.close()
        }
        return inspect(header: header, byteCount: byteCount, expectedLength: -1, contentType: nil)
    }

    /// An ID3v2 tag or an MPEG audio frame sync at the very start of the file. A text body starts with neither.
    static func looksLikeMP3(_ header: Data) -> Bool {
        guard header.count >= 3 else {
            return false
        }
        let start = [UInt8](header.prefix(3))
        if start == [0x49, 0x44, 0x33] {
            // "ID3"
            return true
        }
        return start[0] == 0xFF && (start[1] & 0xE0) == 0xE0
    }

    /// A media type that cannot be a track: any text, JSON, XML or HTML.
    static func isNonAudioType(_ type: String) -> Bool {
        return type.hasPrefix("text/") || type.contains("json") || type.contains("xml") || type.contains("html")
    }

    /// The media type without parameters (`text/html; charset=utf-8` gives `text/html`), lowercased, or nil when there is none.
    static func parseMediaType(_ contentType: String?) -> String? {
        guard let raw = contentType else {
            return nil
        }
        let base = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = base.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The first four bytes as lowercase hex.
    static func hexPrefix(_ header: Data) -> String {
        return header.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
