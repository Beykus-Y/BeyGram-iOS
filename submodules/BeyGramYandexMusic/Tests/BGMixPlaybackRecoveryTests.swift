import XCTest
@testable import BeyGramYandexMusic

final class BGMixPlaybackRecoveryTests: XCTestCase {
    func testRepeatAllWithOneItemRestartsSameRow() {
        XCTAssertTrue(BGMixPlaybackRecovery.shouldRestartItem(advanceFrom: AnyHashable("ym:123"),
                                                               currentItem: AnyHashable("ym:123"),
                                                               isLoading: false,
                                                               playedToEnd: false))
    }

    func testDifferentRowDoesNotRestartTheItemWeLeft() {
        XCTAssertFalse(BGMixPlaybackRecovery.shouldRestartItem(advanceFrom: AnyHashable("ym:123"),
                                                                currentItem: AnyHashable("ym:456"),
                                                                isLoading: false,
                                                                playedToEnd: false))
    }

    func testLoadingOrFinishedPlaylistDoesNotRestart() {
        XCTAssertFalse(BGMixPlaybackRecovery.shouldRestartItem(advanceFrom: AnyHashable("ym:123"),
                                                                currentItem: AnyHashable("ym:123"),
                                                                isLoading: true,
                                                                playedToEnd: false))
        XCTAssertFalse(BGMixPlaybackRecovery.shouldRestartItem(advanceFrom: AnyHashable("ym:123"),
                                                                currentItem: AnyHashable("ym:123"),
                                                                isLoading: false,
                                                                playedToEnd: true))
    }

    func testFiveFailuresPauseThenAPlayingTrackResetsTheStreak() {
        var streak = BGMixFailureStreak()
        XCTAssertEqual(streak.recordFailure(), 1)
        XCTAssertEqual(streak.recordFailure(), 2)
        XCTAssertEqual(streak.recordFailure(), 3)
        XCTAssertEqual(streak.recordFailure(), 4)
        XCTAssertEqual(streak.recordFailure(), BGMixFailureStreak.limit)

        streak.reset()

        XCTAssertEqual(streak.recordFailure(), 1)
    }
}
