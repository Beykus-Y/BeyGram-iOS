import XCTest
@testable import BeyGramKit

final class BeyGramEqualizerTests: XCTestCase {
    func testHeadroomTakesLargestBoostOffEveryBand() {
        XCTAssertEqual(BeyGramEqualizer.withHeadroom([600, 300, 0], minLevelMb: -1500), [0, -300, -600])
    }

    func testHeadroomLeavesLevelsWithoutBoostUntouched() {
        XCTAssertEqual(BeyGramEqualizer.withHeadroom([0, -200, -400], minLevelMb: -1500), [0, -200, -400])
        XCTAssertEqual(BeyGramEqualizer.withHeadroom([], minLevelMb: -1500), [])
    }

    func testHeadroomNeverGoesBelowFloor() {
        XCTAssertEqual(BeyGramEqualizer.withHeadroom([600, -1400], minLevelMb: -1500), [0, -1500])
    }

    func testPresetAtAnchorFrequenciesReturnsAnchorLevels() {
        let levels = BeyGramEqualizer.presetLevelsMb(.bass, frequenciesHz: BeyGramEqualizer.presetAnchorFrequenciesHz)
        XCTAssertEqual(levels, [600, 500, 300, 100, 0, 0, 0, 0, 0, 0])
    }

    func testPresetInterpolatesOnFewerBandsAndFlatIsZero() {
        let bands = [60, 230, 910, 3_600, 14_000]
        XCTAssertEqual(BeyGramEqualizer.presetLevelsMb(.flat, frequenciesHz: bands), [0, 0, 0, 0, 0])
        let rock = BeyGramEqualizer.presetLevelsMb(.rock, frequenciesHz: bands)
        XCTAssertEqual(rock.count, 5)
        XCTAssertGreaterThan(rock[0], 250)
        XCTAssertLessThan(rock[2], 0)
    }

    func testCustomLevelsFollowFrequenciesAndIgnoreInvalidPoints() {
        let levels = BeyGramEqualizer.customLevelsMb(frequenciesHz: [100, 1_000, 10_000], custom: [100: 400, 10_000: -200, 0: 999, 500: 99_999])
        XCTAssertEqual(levels[0], 400)
        XCTAssertEqual(levels[2], -200)
        XCTAssertEqual(BeyGramEqualizer.customLevelsMb(frequenciesHz: [100, 200], custom: [:]), [0, 0])
    }

    func testLevelsAreClampedToBoostCapAndFloor() {
        let settings = BeyGramEqualizerSettings(enabled: true, selectedPreset: .custom, customLevelsMb: [100: 2_000, 1_000: -2_000])
        let levels = BeyGramEqualizer.levels(for: settings, frequenciesHz: [100, 1_000], minLevelMb: -1_500, hardwareMaxLevelMb: 1_500)
        XCTAssertEqual(levels, [600, -1_500])
        let lowCeiling = BeyGramEqualizer.levels(for: settings, frequenciesHz: [100], minLevelMb: -1_500, hardwareMaxLevelMb: 300)
        XCTAssertEqual(lowCeiling, [300])
    }

    func testEncodeDecodeRoundTripAndCorruptInput() {
        let encoded = BeyGramEqualizer.encodeLevels([1_000: 100, 60: -300, 0: 5, 200: 99_999])
        XCTAssertEqual(encoded, "60:-300;1000:100")
        XCTAssertEqual(BeyGramEqualizer.decodeLevels(encoded), [60: -300, 1_000: 100])
        XCTAssertEqual(BeyGramEqualizer.decodeLevels("bad;1:;:2;3:x;;70:50"), [70: 50])
        XCTAssertEqual(BeyGramEqualizer.decodeLevels(nil), [:])
    }

    func testPresetNamesMatchAndroidStorage() {
        XCTAssertEqual(BeyGramEqualizerPreset.allCases.map { $0.rawValue },
                       ["Flat", "Bass", "Vocal", "Pop", "Rock", "Electronic", "Classical", "Jazz", "Custom"])
    }
}
