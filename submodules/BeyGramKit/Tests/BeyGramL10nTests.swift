import XCTest
@testable import BeyGramKit

final class BeyGramL10nTests: XCTestCase {
    func testAllStringKeysPresentInAllSupportedLanguages() {
        for language in BeyGramL10n.supportedLanguages {
            guard let table = BeyGramLocalizationTables.strings[language] else {
                XCTFail("Missing string table for language: \(language)")
                continue
            }
            for key in BeyGramStringKey.allCases {
                let value = table[key]
                XCTAssertNotNil(value, "Missing translation for key \(key.rawValue) in language \(language)")
                XCTAssertFalse(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                               "Empty translation for key \(key.rawValue) in language \(language)")
            }
        }
    }

    func testAllPluralKeysHaveRequiredCategories() {
        let requiredCategories: [String: [BeyGramPluralCategory]] = [
            "en": [.one, .other],
            "ru": [.one, .few, .many, .other]
        ]

        for (language, categories) in requiredCategories {
            guard let table = BeyGramLocalizationTables.plurals[language] else {
                XCTFail("Missing plural table for language: \(language)")
                continue
            }
            for key in BeyGramPluralKey.allCases {
                guard let forms = table[key] else {
                    XCTFail("Missing plural key \(key.rawValue) for language \(language)")
                    continue
                }
                for category in categories {
                    let template = forms[category]
                    XCTAssertNotNil(template, "Missing plural category \(category.rawValue) for \(key.rawValue) in \(language)")
                    XCTAssertTrue(template?.contains("%d") ?? false, "Plural template for \(key.rawValue) (\(category.rawValue)) in \(language) should contain %d")
                }
            }
        }
    }

    func testFormatPlaceholdersMatchBetweenEnglishAndRussian() {
        guard let enTable = BeyGramLocalizationTables.strings["en"],
              let ruTable = BeyGramLocalizationTables.strings["ru"] else {
            XCTFail("Missing en or ru table")
            return
        }

        let regex = try! NSRegularExpression(pattern: "%[@d]")
        for key in BeyGramStringKey.allCases {
            guard let en = enTable[key], let ru = ruTable[key] else { continue }
            let enMatches = regex.matches(in: en, range: NSRange(en.startIndex..., in: en)).map {
                String(en[Range($0.range, in: en)!])
            }
            let ruMatches = regex.matches(in: ru, range: NSRange(ru.startIndex..., in: ru)).map {
                String(ru[Range($0.range, in: ru)!])
            }
            XCTAssertEqual(enMatches, ruMatches, "Format placeholders mismatch for key \(key.rawValue): en=\(enMatches) ru=\(ruMatches)")
        }
    }

    func testBrandNamesArePreserved() {
        let l10n = BeyGramL10n.shared
        XCTAssertEqual(l10n.string(.bgMixTitle, languageCode: "ru"), "BG Mix")
        XCTAssertEqual(l10n.string(.bgWaveTitle, languageCode: "ru"), "BG Wave")
        XCTAssertTrue(l10n.string(.settingsMihomoTitle, languageCode: "ru").contains("Mihomo"))
        XCTAssertTrue(l10n.string(.musicSourceBGMix, languageCode: "ru").contains("BG Mix"))
        XCTAssertTrue(l10n.string(.musicSourceBGMix, languageCode: "ru").contains("BG Beat"))
    }

    func testRussianPluralizationRules() {
        let l10n = BeyGramL10n.shared
        XCTAssertEqual(l10n.plural(.serversCount, count: 0, languageCode: "ru"), "0 серверов")
        XCTAssertEqual(l10n.plural(.serversCount, count: 1, languageCode: "ru"), "1 сервер")
        XCTAssertEqual(l10n.plural(.serversCount, count: 2, languageCode: "ru"), "2 сервера")
        XCTAssertEqual(l10n.plural(.serversCount, count: 4, languageCode: "ru"), "4 сервера")
        XCTAssertEqual(l10n.plural(.serversCount, count: 5, languageCode: "ru"), "5 серверов")
        XCTAssertEqual(l10n.plural(.serversCount, count: 11, languageCode: "ru"), "11 серверов")
        XCTAssertEqual(l10n.plural(.serversCount, count: 14, languageCode: "ru"), "14 серверов")
        XCTAssertEqual(l10n.plural(.serversCount, count: 21, languageCode: "ru"), "21 сервер")
        XCTAssertEqual(l10n.plural(.serversCount, count: 23, languageCode: "ru"), "23 сервера")
    }

    func testEnglishPluralizationRules() {
        let l10n = BeyGramL10n.shared
        XCTAssertEqual(l10n.plural(.serversCount, count: 0, languageCode: "en"), "0 servers")
        XCTAssertEqual(l10n.plural(.serversCount, count: 1, languageCode: "en"), "1 server")
        XCTAssertEqual(l10n.plural(.serversCount, count: 2, languageCode: "en"), "2 servers")
    }

    func testLanguageNormalizationAndFormatting() {
        XCTAssertEqual(BeyGramL10n.normalizeLanguageCode("ru-RU"), "ru")
        XCTAssertEqual(BeyGramL10n.normalizeLanguageCode("en_US"), "en")
        XCTAssertEqual(BeyGramL10n.normalizeLanguageCode("fr"), "en")
        XCTAssertEqual(BeyGramL10n.normalizeLanguageCode(nil), "en")

        let l10n = BeyGramL10n.shared
        XCTAssertEqual(l10n.formatLatency(42, languageCode: "ru"), "42 мс")
        XCTAssertEqual(l10n.formatLatency(42, languageCode: "en"), "42 ms")
        XCTAssertEqual(l10n.formatLatency(-1, languageCode: "ru"), "Недоступен")
        XCTAssertEqual(l10n.formatDuration(65), "1:05")
        XCTAssertEqual(l10n.formatDuration(3661), "1:01:01")
    }
}
