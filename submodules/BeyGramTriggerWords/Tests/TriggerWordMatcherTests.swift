import XCTest
@testable import BeyGramTriggerWords

final class TriggerWordMatcherTests: XCTestCase {
    private func rule(_ pattern: String, mode: TriggerWordMode = .wholeWord, ignoreCase: Bool = true, ignoreDiacritics: Bool = false) -> TriggerWordRule {
        TriggerWordRule(pattern: pattern, mode: mode, ignoreCase: ignoreCase, ignoreDiacritics: ignoreDiacritics)
    }

    func testWholeWordMatchesStandaloneWordInRussianText() {
        XCTAssertTrue(TriggerWordMatcher.matches(rule("тест"), text: "это тест сообщения"))
    }

    func testWholeWordRejectsSubstring() {
        XCTAssertFalse(TriggerWordMatcher.matches(rule("test"), text: "tests are running"))
    }

    func testAnywhereMatchesSubstring() {
        XCTAssertTrue(TriggerWordMatcher.matches(rule("test", mode: .anywhere), text: "tests are running"))
    }

    func testHashtagMatchesBeforePunctuation() {
        XCTAssertTrue(TriggerWordMatcher.matches(rule("#release"), text: "готово #release!"))
    }

    func testHashtagMatchesAfterWordCharacterBecauseHashIsNotAWordEdge() {
        // The leading edge `#` is not a word character, so no boundary is required before it.
        XCTAssertTrue(TriggerWordMatcher.matches(rule("#release"), text: "xx#release"))
    }

    func testCaseInsensitiveByDefault() {
        XCTAssertTrue(TriggerWordMatcher.matches(rule("STRASSE", mode: .anywhere), text: "in der straße"))
    }

    func testCaseSensitiveWhenDisabled() {
        XCTAssertFalse(TriggerWordMatcher.matches(rule("Hello", ignoreCase: false), text: "hello world"))
    }

    func testDiacriticsOffByDefault() {
        XCTAssertFalse(TriggerWordMatcher.matches(rule("cafe"), text: "café"))
    }

    func testDiacriticsIgnoredWhenEnabled() {
        XCTAssertTrue(TriggerWordMatcher.matches(rule("cafe", ignoreDiacritics: true), text: "café"))
    }

    func testFullWidthLettersMatchAfterNFKC() {
        XCTAssertTrue(TriggerWordMatcher.matches(rule("hello", mode: .anywhere), text: "ｈｅｌｌｏ"))
    }

    func testZeroWidthCharactersAreIgnored() {
        XCTAssertTrue(TriggerWordMatcher.matches(rule("hello", mode: .anywhere), text: "hel\u{200B}lo"))
    }

    func testPhraseMatchesAcrossLineBreakAndNonBreakingSpace() {
        XCTAssertTrue(TriggerWordMatcher.matches(rule("big deal", mode: .anywhere), text: "big\u{00A0}\ndeal"))
    }

    func testDisabledRuleIsNotReturned() {
        var disabled = rule("привет")
        disabled.isEnabled = false
        XCTAssertTrue(TriggerWordMatcher.matchingRules(in: [disabled], text: "привет").isEmpty)
    }

    func testValidationRejectsEmptyPattern() {
        XCTAssertEqual(TriggerWordMatcher.validate(rule("   "), existingCount: 0), .emptyPattern)
    }

    func testValidationRejectsLongPattern() {
        let long = String(repeating: "a", count: TriggerWordRule.maxPatternLength + 1)
        XCTAssertEqual(TriggerWordMatcher.validate(rule(long), existingCount: 0), .patternTooLong)
    }

    func testValidationRejectsTooManyRules() {
        XCTAssertEqual(TriggerWordMatcher.validate(rule("ok"), existingCount: TriggerWordRule.maxRules), .tooManyRules)
    }

    func testValidationAcceptsNormalRule() {
        XCTAssertNil(TriggerWordMatcher.validate(rule("ok"), existingCount: 0))
    }
}
