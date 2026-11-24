import Foundation

/// BeyGram strings shared with Android: the keys are Android resource names and the tables are generated from
/// the Android resources by `tools/l10n/android_strings.py` (one source of strings, see `Generated/`).
///
/// Languages: ru (the default), en, de, es, fr. As on Android, an unsupported language falls back to Russian.
/// Strings that come from a server (names, messages, URLs, file names, diagnostics) are never looked up here.
public final class BeyGramAndroidStrings {
    public static let shared = BeyGramAndroidStrings()

    public static let supportedLanguages = ["ru", "en", "de", "es", "fr"]
    public static let fallbackLanguage = "ru"

    private let strings: [String: [String: String]]
    private let plurals: [String: [String: [String: String]]]
    private let lock = NSLock()
    private var overrideLanguage: String?

    init() {
        var strings: [String: [String: String]] = [:]
        for (language, flat) in BeyGramAndroidStringsData.strings {
            var table: [String: String] = [:]
            var index = 0
            while index + 1 < flat.count {
                table[flat[index]] = flat[index + 1]
                index += 2
            }
            strings[language] = table
        }
        var plurals: [String: [String: [String: String]]] = [:]
        for (language, flat) in BeyGramAndroidStringsData.plurals {
            var table: [String: [String: String]] = [:]
            var index = 0
            while index + 1 < flat.count {
                var forms: [String: String] = [:]
                for entry in flat[index + 1].split(separator: "\u{1F}") {
                    if let separator = entry.firstIndex(of: "=") {
                        forms[String(entry[entry.startIndex ..< separator])] = String(entry[entry.index(after: separator)...])
                    }
                }
                table[flat[index]] = forms
                index += 2
            }
            plurals[language] = table
        }
        self.strings = strings
        self.plurals = plurals
    }

    /// The language used when none is passed. nil follows the system. Switching takes effect on the next lookup.
    public func setLanguageCode(_ languageCode: String?) {
        self.lock.lock()
        self.overrideLanguage = languageCode
        self.lock.unlock()
    }

    /// `ru-RU`, `pt_BR`, `DE` become a supported two-letter code, or the fallback.
    public static func normalizeLanguageCode(_ languageCode: String?) -> String {
        guard let languageCode = languageCode else {
            return self.fallbackLanguage
        }
        let base = languageCode.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return self.supportedLanguages.contains(base) ? base : self.fallbackLanguage
    }

    private func effectiveLanguage(_ languageCode: String?) -> String {
        if let languageCode = languageCode {
            return BeyGramAndroidStrings.normalizeLanguageCode(languageCode)
        }
        self.lock.lock()
        let override = self.overrideLanguage
        self.lock.unlock()
        return BeyGramAndroidStrings.normalizeLanguageCode(override ?? Locale.preferredLanguages.first)
    }

    /// The raw template, nil when the key does not exist. A key missing in one language falls back to Russian.
    public func template(_ name: String, languageCode: String? = nil) -> String? {
        let language = self.effectiveLanguage(languageCode)
        return self.strings[language]?[name] ?? self.strings[BeyGramAndroidStrings.fallbackLanguage]?[name]
    }

    /// The string, or the key itself when it does not exist (visible in testing, never a crash).
    public func string(_ name: String, languageCode: String? = nil, _ arguments: CVarArg...) -> String {
        guard let template = self.template(name, languageCode: languageCode) else {
            return name
        }
        return arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }

    /// A plural. `%lld` in the template takes the count, so `quantityString("bgmusic_tracks_count", count: 3)` gives "3 трека".
    public func quantityString(_ name: String, count: Int, languageCode: String? = nil, _ arguments: CVarArg...) -> String {
        let language = self.effectiveLanguage(languageCode)
        let forms = self.plurals[language]?[name] ?? self.plurals[BeyGramAndroidStrings.fallbackLanguage]?[name]
        guard let forms = forms else {
            return name
        }
        let category = BeyGramAndroidStrings.pluralCategory(count: count, language: language)
        guard let template = forms[category] ?? forms["other"] else {
            return name
        }
        let formatArguments: [CVarArg] = arguments.isEmpty ? [count] : arguments
        return String(format: template, arguments: formatArguments)
    }

    /// CLDR categories for the supported languages.
    public static func pluralCategory(count: Int, language: String) -> String {
        let n = abs(count)
        switch language {
        case "ru":
            let mod10 = n % 10
            let mod100 = n % 100
            if mod10 == 1 && mod100 != 11 {
                return "one"
            }
            if (2 ... 4).contains(mod10) && !(12 ... 14).contains(mod100) {
                return "few"
            }
            return "many"
        case "fr":
            return n <= 1 ? "one" : "other"
        default:
            return n == 1 ? "one" : "other"
        }
    }

    // For tests.
    func allKeys(language: String) -> Set<String> {
        return Set((self.strings[language] ?? [:]).keys)
    }

    func allPluralKeys(language: String) -> Set<String> {
        return Set((self.plurals[language] ?? [:]).keys)
    }
}
