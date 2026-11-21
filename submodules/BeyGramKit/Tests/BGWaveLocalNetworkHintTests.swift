import XCTest
@testable import BeyGramKit

final class BGWaveLocalNetworkHintTests: XCTestCase {
    func testHintHasTextInEverySupportedLanguage() {
        for language in BeyGramL10n.supportedLanguages {
            let hint = BGWaveLocalNetworkHint.make(languageCode: language)
            XCTAssertFalse(hint.title.isEmpty, "Empty title for \(language)")
            XCTAssertFalse(hint.message.isEmpty, "Empty message for \(language)")
            XCTAssertFalse(hint.settingsButtonTitle.isEmpty, "Empty settings button for \(language)")
            XCTAssertFalse(hint.dismissButtonTitle.isEmpty, "Empty dismiss button for \(language)")
        }
    }

    func testMessageSaysMayNotAsAFact() {
        // iOS gives no callback for the denial, so the hint must not state it as a fact.
        XCTAssertTrue(BGWaveLocalNetworkHint.make(languageCode: "en").message.contains("may"))
        XCTAssertTrue(BGWaveLocalNetworkHint.make(languageCode: "ru").message.contains("может"))
    }

    func testSettingsURLIsTheAppSettingsScheme() {
        XCTAssertEqual(BGWaveLocalNetworkHint.settingsURLString, "app-settings:")
    }

    func testRussianHintDiffersFromEnglish() {
        XCTAssertNotEqual(BGWaveLocalNetworkHint.make(languageCode: "ru"),
                          BGWaveLocalNetworkHint.make(languageCode: "en"))
    }
}
