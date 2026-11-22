import BeyGramRE2
import Foundation

/// A trigger pattern compiled with RE2, the engine behind the Android client's regex triggers.
///
/// Compile the pattern when a rule is created or changed, and reuse the handle for every message. RE2 runs in time
/// linear in the text, so a pattern cannot stall message handling the way a backtracking engine can.
///
/// Not used by `TriggerWordMatcher` yet: the regex mode and its UI come in a later change.
public final class TriggerRegex {
    private let handle: UnsafeMutableRawPointer

    /// Returns nil when RE2 rejects the pattern, for example lookaround or a backreference.
    public init?(pattern: String, ignoreCase: Bool) {
        let length = pattern.utf8.count
        guard let handle = pattern.withCString({ bgre2_compile($0, length, ignoreCase ? 0 : 1) }) else {
            return nil
        }
        self.handle = handle
    }

    deinit {
        bgre2_free(handle)
    }

    /// Unanchored search, as `java.util.regex.Matcher.find` does. The text is normalised first.
    public func matches(_ text: String) -> Bool {
        let normalized = TriggerRegex.normalizeText(text)
        let length = normalized.utf8.count
        return normalized.withCString { bgre2_partial_match(handle, $0, length) != 0 }
    }

    /// NFKC, then invisible format characters (Unicode category Cf) removed. Case and spacing stay as written:
    /// the flag does the case folding, and `\s` must see the original whitespace.
    static func normalizeText(_ input: String) -> String {
        let composed = input.precomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for scalar in composed.unicodeScalars {
            if scalar.properties.generalCategory == .format {
                continue
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }
}

/// Why a regex trigger cannot be saved. The cases match the Android `TriggerProblem` values.
public enum TriggerRegexProblem: Equatable {
    case empty
    case tooLong
    case badRegex
    case regexMatchesEmpty
}

public enum TriggerRegexValidator {
    /// The longest pattern, in UTF-16 units, as on Android.
    public static let maxPatternLength = 120

    /// Returns nil when the pattern can be saved. Checks run in the Android order: empty, too long, rejected by RE2,
    /// then a pattern that matches the empty text or a single space, which would fire on almost every message.
    public static func validate(_ pattern: String, ignoreCase: Bool) -> TriggerRegexProblem? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }
        if trimmed.utf16.count > maxPatternLength {
            return .tooLong
        }
        guard let regex = TriggerRegex(pattern: trimmed, ignoreCase: ignoreCase) else {
            return .badRegex
        }
        if regex.matches("") || regex.matches(" ") {
            return .regexMatchesEmpty
        }
        return nil
    }
}
