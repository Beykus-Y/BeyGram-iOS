import Foundation

/// Text cleaning from section 7 of the .bgmusic v1 spec. The same rules run on write and on read,
/// so a written file reads back unchanged. Cleaning is idempotent.
public enum BGMusicText {
    private enum Token {
        case text(Unicode.Scalar)
        case lineBreak
    }

    private static func isLineBreak(_ value: UInt32) -> Bool {
        switch value {
        case 0x0A, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }

    /// Controls removed outright (CR, LF, VT, FF, NEL and TAB are handled before this check),
    /// bidi overrides and isolates, and invisible marks that can hide or reorder words.
    private static func isRemoved(_ value: UInt32) -> Bool {
        switch value {
        case 0x00...0x08, 0x0E...0x1F, 0x7F...0x9F:
            return true
        case 0x202A...0x202E, 0x2066...0x2069:
            return true
        case 0x061C, 0x200B, 0x200E, 0x200F, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// Cleans a single-line field (playlist, track, artist, album, author name).
    public static func singleLine(_ input: String, maxLength: Int) -> String {
        return clean(input, multiline: false, maxLength: maxLength)
    }

    /// Cleans a multi-line description. Runs of line breaks shrink to at most two LF.
    public static func multiline(_ input: String, maxLength: Int) -> String {
        return clean(input, multiline: true, maxLength: maxLength)
    }

    static func clean(_ input: String, multiline: Bool, maxLength: Int) -> String {
        let scalars = Array(input.unicodeScalars)
        var tokens: [Token] = []
        tokens.reserveCapacity(scalars.count)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let value = scalar.value
            if value == 0x0D {
                // CR and CRLF are one break.
                if index + 1 < scalars.count, scalars[index + 1].value == 0x0A {
                    index += 1
                }
                tokens.append(.lineBreak)
            } else if isLineBreak(value) {
                tokens.append(.lineBreak)
            } else if value == 0x09 {
                tokens.append(.text(" "))
            } else if isRemoved(value) {
                // Removed before the run count, so `a LF U+0007 LF LF b` gives `a LF LF b`.
            } else {
                tokens.append(.text(scalar))
            }
            index += 1
        }

        var out = String.UnicodeScalarView()
        var breakRun = 0
        func flushBreaks() {
            if breakRun == 0 {
                return
            }
            if multiline {
                for _ in 0..<min(breakRun, 2) {
                    out.append("\n")
                }
            } else {
                out.append(" ")
            }
            breakRun = 0
        }
        for token in tokens {
            switch token {
            case .lineBreak:
                breakRun += 1
            case let .text(scalar):
                flushBreaks()
                out.append(scalar)
            }
        }
        // A trailing break run is dropped by the trim below, so nothing else is flushed here.

        var result = String(out).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.unicodeScalars.count > maxLength {
            let truncated = String(String.UnicodeScalarView(result.unicodeScalars.prefix(maxLength)))
            result = truncated.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
