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
        } else if looksLikeSupportedAudio(header) {
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

    /// An ID3v2 tag or an MPEG/AAC ADTS frame sync at the start of the file.
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

    /// Recognises audio formats AVFoundation can decode: MP3/ADTS, MP4/M4A (`ftyp`), FLAC (`fLaC`), WAV (`RIFF..WAVE`), AIFF (`FORM..AIFF/AIFC`).
    static func looksLikeSupportedAudio(_ header: Data) -> Bool {
        if looksLikeMP3(header) {
            return true
        }
        let bytes = [UInt8](header.prefix(12))
        if bytes.count >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            // ISO BMFF / M4A / MP4 ("ftyp")
            return true
        }
        if bytes.count >= 4 && bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43 {
            // "fLaC"
            return true
        }
        if bytes.count >= 12
            && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45 {
            // "RIFF....WAVE"
            return true
        }
        if bytes.count >= 12
            && bytes[0] == 0x46 && bytes[1] == 0x4F && bytes[2] == 0x52 && bytes[3] == 0x4D
            && bytes[8] == 0x41 && bytes[9] == 0x49 && bytes[10] == 0x46 && (bytes[11] == 0x46 || bytes[11] == 0x43) {
            // "FORM....AIFF" / "AIFC"
            return true
        }
        return false
    }

    /// Picks a file extension matching the audio header so AVAudioFile gets the right container hint.
    public static func fileExtension(for header: Data, contentType: String? = nil, fallbackCodec: String? = nil) -> String {
        let bytes = [UInt8](header.prefix(12))
        if bytes.count >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return "m4a"
        }
        if bytes.count >= 4 && bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43 {
            return "flac"
        }
        if bytes.count >= 12
            && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45 {
            return "wav"
        }
        if bytes.count >= 12
            && bytes[0] == 0x46 && bytes[1] == 0x4F && bytes[2] == 0x52 && bytes[3] == 0x4D
            && bytes[8] == 0x41 && bytes[9] == 0x49 && bytes[10] == 0x46 && (bytes[11] == 0x46 || bytes[11] == 0x43) {
            return "aiff"
        }
        if let type = parseMediaType(contentType) {
            if type.contains("mp4") || type.contains("m4a") || type.contains("aac") {
                return "m4a"
            }
            if type.contains("flac") {
                return "flac"
            }
            if type.contains("wav") {
                return "wav"
            }
        }
        if let codec = fallbackCodec?.lowercased() {
            if codec.contains("aac") || codec.contains("mp4") || codec.contains("m4a") || codec.contains("alac") {
                return "m4a"
            }
            if codec.contains("flac") {
                return "flac"
            }
            if codec.contains("wav") {
                return "wav"
            }
        }
        return "mp3"
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
