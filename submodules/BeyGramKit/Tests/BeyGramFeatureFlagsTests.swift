import XCTest
@testable import BeyGramKit

private final class MemoryFlagStorage: BeyGramFlagStorage {
    var values: [String: Bool] = [:]
    func bool(forKey key: String) -> Bool? { values[key] }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
}

final class BeyGramFeatureFlagsTests: XCTestCase {
    func testEveryFeatureIsOffByDefault() {
        let flags = BeyGramFeatureFlags(storage: MemoryFlagStorage())
        for feature in BeyGramFeature.allCases {
            XCTAssertFalse(flags.isEnabled(feature), "\(feature) must be off by default")
        }
    }

    func testSwitchingOneFeatureDoesNotAffectOthers() {
        let flags = BeyGramFeatureFlags(storage: MemoryFlagStorage())
        flags.setEnabled(.chatExport, true)
        XCTAssertTrue(flags.isEnabled(.chatExport))
        XCTAssertFalse(flags.isEnabled(.triggerWords))
    }
}
