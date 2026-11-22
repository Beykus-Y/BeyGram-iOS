import Foundation
import XCTest
@testable import BeyGramTriggerWords

/// Runs the shared regex parity fixtures. The Android repository holds a byte-identical copy and runs the same cases.
final class TriggerRegexTests: XCTestCase {
    private struct Fixtures: Decodable {
        struct Validation: Decodable {
            let pattern: String
            let ignoreCase: Bool
            let expect: String
            let source: String
        }

        struct Match: Decodable {
            let pattern: String
            let ignoreCase: Bool
            let text: String
            let repeatCount: Int
            let suffix: String
            let fires: Bool
            let source: String

            enum CodingKeys: String, CodingKey {
                case pattern
                case ignoreCase
                case text
                case repeatCount = "repeat"
                case suffix
                case fires
                case source
            }
        }

        let schema: Int
        let validate: [Validation]
        let matches: [Match]
    }

    private func loadFixtures() throws -> Fixtures {
        let relativePath = "submodules/BeyGramTriggerWords/Tests/Fixtures/regex_parity.json"
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let runfiles = environment["TEST_SRCDIR"] {
            if let workspace = environment["TEST_WORKSPACE"] {
                candidates.append(runfiles + "/" + workspace + "/" + relativePath)
            }
            candidates.append(runfiles + "/_main/" + relativePath)
        }
        candidates.append(relativePath)
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw NSError(
                domain: "TriggerRegexTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "regex_parity.json not found; tried \(candidates)"]
            )
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(Fixtures.self, from: data)
    }

    func testFixtureSchemaIsOne() throws {
        XCTAssertEqual(try loadFixtures().schema, 1)
    }

    func testValidationFollowsSharedFixtures() throws {
        for item in try loadFixtures().validate {
            let expected: TriggerRegexProblem?
            switch item.expect {
            case "OK":
                expected = nil
            case "BAD_REGEX":
                expected = .badRegex
            case "REGEX_MATCHES_EMPTY":
                expected = .regexMatchesEmpty
            default:
                XCTFail("unknown expectation \(item.expect) (\(item.source))")
                continue
            }
            XCTAssertEqual(
                TriggerRegexValidator.validate(item.pattern, ignoreCase: item.ignoreCase),
                expected,
                "\(item.pattern) (\(item.source))"
            )
        }
    }

    func testMatchesFollowSharedFixtures() throws {
        for item in try loadFixtures().matches {
            guard let regex = TriggerRegex(pattern: item.pattern, ignoreCase: item.ignoreCase) else {
                XCTFail("RE2 rejected \(item.pattern) (\(item.source))")
                continue
            }
            let text = String(repeating: item.text, count: item.repeatCount) + item.suffix
            XCTAssertEqual(regex.matches(text), item.fires, "\(item.pattern) (\(item.source))")
        }
    }

    func testInvisibleFormatCharactersAreIgnoredInText() throws {
        let regex = try XCTUnwrap(TriggerRegex(pattern: "deadline", ignoreCase: true))
        XCTAssertTrue(regex.matches("dead\u{200B}line"))
    }

    func testCaseFollowsTheFlagNotTheText() throws {
        let folded = try XCTUnwrap(TriggerRegex(pattern: "Deadline", ignoreCase: true))
        let exact = try XCTUnwrap(TriggerRegex(pattern: "Deadline", ignoreCase: false))
        XCTAssertTrue(folded.matches("DEADLINE"))
        XCTAssertFalse(exact.matches("DEADLINE"))
    }

    func testValidatorOrderMatchesAndroid() {
        XCTAssertEqual(TriggerRegexValidator.validate("   ", ignoreCase: true), TriggerRegexProblem.empty)
        XCTAssertEqual(
            TriggerRegexValidator.validate(String(repeating: "a", count: 121), ignoreCase: true),
            TriggerRegexProblem.tooLong
        )
        XCTAssertNil(TriggerRegexValidator.validate(String(repeating: "a", count: 120), ignoreCase: true))
        XCTAssertEqual(TriggerRegexValidator.validate("(", ignoreCase: true), TriggerRegexProblem.badRegex)
    }
}
