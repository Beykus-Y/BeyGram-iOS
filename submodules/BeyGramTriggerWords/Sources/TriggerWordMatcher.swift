import Foundation

/// Trigger-word rules for BeyGram (port of the Android `trigger_words` matcher).
///
/// This file is pure logic: no TDLib, no UI, no storage. The app layer feeds it the
/// text of incoming messages and the stored rules.
///
/// Supported modes: whole word (default) and anywhere in text. Regular expressions are
/// intentionally not implemented yet: the Android spec requires RE2 (linear time), and
/// `NSRegularExpression` is backtracking, so it cannot give that guarantee.
public enum TriggerWordMode: String, Codable, Equatable {
    case wholeWord
    case anywhere
}

public struct TriggerWordRule: Codable, Equatable, Identifiable {
    public static let maxRules = 50
    public static let maxPatternLength = 120

    public var id: UUID
    public var pattern: String
    public var mode: TriggerWordMode
    public var ignoreCase: Bool
    public var ignoreDiacritics: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        pattern: String,
        mode: TriggerWordMode = .wholeWord,
        ignoreCase: Bool = true,
        ignoreDiacritics: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.pattern = pattern
        self.mode = mode
        self.ignoreCase = ignoreCase
        self.ignoreDiacritics = ignoreDiacritics
        self.isEnabled = isEnabled
    }
}

public enum TriggerWordValidationError: Error, Equatable {
    case emptyPattern
    case patternTooLong
    case tooManyRules
}

public enum TriggerWordMatcher {
    /// Returns an error when the rule cannot be saved. `existingCount` is the number of rules
    /// already stored, not counting the rule being validated.
    public static func validate(_ rule: TriggerWordRule, existingCount: Int) -> TriggerWordValidationError? {
        if existingCount >= TriggerWordRule.maxRules {
            return .tooManyRules
        }
        if rule.pattern.count > TriggerWordRule.maxPatternLength {
            return .patternTooLong
        }
        if normalize(rule.pattern, ignoreCase: rule.ignoreCase, ignoreDiacritics: rule.ignoreDiacritics).isEmpty {
            return .emptyPattern
        }
        return nil
    }

    /// Returns the enabled rules that match `text`. The text must be an incoming message's
    /// text or caption. Outgoing and secret-chat messages must be filtered out by the caller.
    public static func matchingRules(in rules: [TriggerWordRule], text: String) -> [TriggerWordRule] {
        rules.filter { rule in
            rule.isEnabled && matches(rule, text: text)
        }
    }

    public static func matches(_ rule: TriggerWordRule, text: String) -> Bool {
        let haystack = normalize(text, ignoreCase: rule.ignoreCase, ignoreDiacritics: rule.ignoreDiacritics)
        let needle = normalize(rule.pattern, ignoreCase: rule.ignoreCase, ignoreDiacritics: rule.ignoreDiacritics)
        guard !needle.isEmpty, needle.count <= haystack.count else {
            return false
        }
        switch rule.mode {
        case .anywhere:
            return firstOccurrence(of: needle, in: haystack, from: 0, wholeWord: false) != nil
        case .wholeWord:
            return firstOccurrence(of: needle, in: haystack, from: 0, wholeWord: true) != nil
        }
    }

    // MARK: - Normalization

    /// NFKC, invisible format characters removed, whitespace runs collapsed to one space,
    /// then optional case folding and optional diacritic removal.
    public static func normalize(_ input: String, ignoreCase: Bool, ignoreDiacritics: Bool) -> [Unicode.Scalar] {
        var text = input.precomposedStringWithCompatibilityMapping
        if ignoreCase {
            text = text.folding(options: [.caseInsensitive], locale: nil)
        }
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(text.unicodeScalars.count)
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .format {
                continue
            }
            if scalar.properties.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(scalar)
        }
        if ignoreDiacritics {
            result = stripMarks(result)
        }
        return result
    }

    /// Removes nonspacing marks after canonical decomposition, so `é` becomes `e`.
    /// Letters that differ only by a mark (for example `й` and `и`) become equal too,
    /// which is why this option is off by default.
    private static func stripMarks(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        let decomposed = String(String.UnicodeScalarView(scalars)).decomposedStringWithCanonicalMapping
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(decomposed.unicodeScalars.count)
        for scalar in decomposed.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            result.append(scalar)
        }
        return result
    }

    // MARK: - Searching

    /// Word characters: letters, digits, underscore, and combining marks.
    static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .connectorPunctuation,
             .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    /// Finds `needle` in `haystack` starting at `from`. With `wholeWord`, an edge of the needle
    /// is checked only when that edge is a word character, so `#release` matches `#release!`.
    static func firstOccurrence(
        of needle: [Unicode.Scalar],
        in haystack: [Unicode.Scalar],
        from start: Int,
        wholeWord: Bool
    ) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else {
            return nil
        }
        let lastStart = haystack.count - needle.count
        var index = start
        while index <= lastStart {
            if haystack[index] == needle[0] && equalRange(haystack, index, needle) {
                if !wholeWord || edgesAreBoundaries(haystack, index, needle) {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    private static func equalRange(_ haystack: [Unicode.Scalar], _ index: Int, _ needle: [Unicode.Scalar]) -> Bool {
        for offset in 0 ..< needle.count where haystack[index + offset] != needle[offset] {
            return false
        }
        return true
    }

    private static func edgesAreBoundaries(_ haystack: [Unicode.Scalar], _ index: Int, _ needle: [Unicode.Scalar]) -> Bool {
        if isWordCharacter(needle[0]), index > 0, isWordCharacter(haystack[index - 1]) {
            return false
        }
        let end = index + needle.count
        if isWordCharacter(needle[needle.count - 1]), end < haystack.count, isWordCharacter(haystack[end]) {
            return false
        }
        return true
    }
}
