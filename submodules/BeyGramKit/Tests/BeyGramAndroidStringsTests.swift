import XCTest
@testable import BeyGramKit

final class BeyGramAndroidStringsTests: XCTestCase {
    private let l10n = BeyGramAndroidStrings.shared

    func testEveryLanguageHasEveryRussianKey() {
        let russian = l10n.allKeys(language: "ru")
        XCTAssertFalse(russian.isEmpty)
        for language in BeyGramAndroidStrings.supportedLanguages {
            XCTAssertEqual(l10n.allKeys(language: language), russian, "keys differ in \(language)")
            XCTAssertEqual(l10n.allPluralKeys(language: language), l10n.allPluralKeys(language: "ru"), "plural keys differ in \(language)")
        }
    }

    func testNoEmptyValuesAndPlaceholdersMatchRussian() {
        let pattern = try! NSRegularExpression(pattern: "%(\\d+\\$)?[-#+ 0,(]*\\d*(\\.\\d+)?(@|lld|f)")
        func placeholders(_ text: String) -> [String] {
            let range = NSRange(text.startIndex..., in: text)
            return pattern.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for key in l10n.allKeys(language: "ru") {
            let russian = l10n.template(key, languageCode: "ru")!
            for language in BeyGramAndroidStrings.supportedLanguages {
                let value = l10n.template(key, languageCode: language)!
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) empty in \(language)")
                XCTAssertEqual(placeholders(value), placeholders(russian), "\(key) placeholders differ in \(language)")
            }
        }
    }

    func testFallbackAndNormalization() {
        XCTAssertEqual(BeyGramAndroidStrings.normalizeLanguageCode("de-DE"), "de")
        XCTAssertEqual(BeyGramAndroidStrings.normalizeLanguageCode("pt_BR"), "ru")
        XCTAssertEqual(BeyGramAndroidStrings.normalizeLanguageCode(nil), "ru")
        XCTAssertEqual(l10n.string("no_such_key_for_test", languageCode: "en"), "no_such_key_for_test")
        XCTAssertEqual(l10n.template("bgmusic_author_line", languageCode: "xx"), l10n.template("bgmusic_author_line", languageCode: "ru"))
    }

    func testFormatAndPlurals() {
        XCTAssertEqual(l10n.string("bgmusic_author_line", languageCode: "ru", "Ава"), "Автор: Ава")
        XCTAssertEqual(l10n.quantityString("bgmusic_tracks_count", count: 1, languageCode: "ru"), "1 трек")
        XCTAssertEqual(l10n.quantityString("bgmusic_tracks_count", count: 3, languageCode: "ru"), "3 трека")
        XCTAssertEqual(l10n.quantityString("bgmusic_tracks_count", count: 11, languageCode: "ru"), "11 треков")
        XCTAssertEqual(l10n.quantityString("bgmusic_tracks_count", count: 2, languageCode: "en"), "2 tracks")
        XCTAssertEqual(l10n.quantityString("bgmusic_tracks_count", count: 1, languageCode: "en"), "1 track")
    }

    func testPlayerAndEqualizerKeysExist() {
        for key in ["player_sleep_timer", "player_sleep_in_minutes", "player_sleep_until_track_end", "player_sleep_extend",
                    "player_sleep_cancel_plain", "player_pane_title", "player_queue", "equalizer_title", "equalizer_enabled_title",
                    "equalizer_reset", "equalizer_preset_flat", "equalizer_preset_custom"] {
            XCTAssertNotNil(l10n.template(key, languageCode: "en"), key)
        }
        XCTAssertEqual(l10n.string("player_sleep_in_minutes", languageCode: "en", 15), "Stop in 15 min")
    }

    func testSwitchingLanguageNeedsNoRestart() {
        l10n.setLanguageCode("en")
        let english = l10n.string("bgmusic_author_line", "X")
        l10n.setLanguageCode("ru")
        XCTAssertNotEqual(english, l10n.string("bgmusic_author_line", "X"))
        l10n.setLanguageCode(nil)
    }
}
