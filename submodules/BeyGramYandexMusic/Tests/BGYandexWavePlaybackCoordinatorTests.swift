import XCTest
@testable import BeyGramYandexMusic

private final class FakeWaveRadio: BGYandexWaveSource {
    var firstResult: Result<[BGYandexTrack], BGYandexError> = .success([])
    var moreResults: [Result<[BGYandexTrack], BGYandexError>] = []
    private(set) var sent: [BGYandexWaveEvent] = []

    func first(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        completion(firstResult)
    }

    func more(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        completion(moreResults.isEmpty ? .success([]) : moreResults.removeFirst())
    }

    func feedbackEvent(for listen: BGYandexListenEvent) -> BGYandexWaveEvent? {
        switch listen {
        case let .started(rowKey):
            return BGYandexWaveEvent(type: .trackStarted, timestampMs: 0, trackId: rowKey)
        case let .finished(rowKey, playedSeconds):
            return BGYandexWaveEvent(type: .trackFinished, timestampMs: 0, trackId: rowKey, playedSeconds: playedSeconds)
        case let .skipped(rowKey, playedSeconds):
            return BGYandexWaveEvent(type: .skip, timestampMs: 0, trackId: rowKey, playedSeconds: playedSeconds)
        }
    }

    func likeFeedback(trackId: String, liked: Bool) -> BGYandexWaveEvent? {
        return BGYandexWaveEvent(type: liked ? .like : .unlike, timestampMs: 0, trackId: trackId)
    }

    func sendFeedback(_ event: BGYandexWaveEvent, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        sent.append(event)
        completion(.success(()))
    }
}

private final class FakeWavePlayer: BGYandexWavePlayerAdapter {
    struct PlayCall: Equatable {
        let trackId: String
        let replaceQueue: Bool
        let assignedItemId: UInt64
    }

    private var nextId: UInt64 = 100
    var failingTrackIds: Set<String> = []
    var failureError: BGYandexPlaybackError = .unavailable
    var acceptCrossfadeSkip = true

    private(set) var calls: [PlayCall] = []
    private(set) var skipCrossfadeCount = 0
    private(set) var togglePlayPauseCount = 0

    func playWaveTrack(
        _ track: BGYandexTrack,
        replaceQueue: Bool,
        completion: @escaping (Result<UInt64, BGYandexPlaybackError>) -> Void
    ) {
        if failingTrackIds.contains(track.trackId) {
            completion(.failure(failureError))
            return
        }
        nextId += 1
        let itemId = nextId
        calls.append(PlayCall(trackId: track.trackId, replaceQueue: replaceQueue, assignedItemId: itemId))
        completion(.success(itemId))
    }

    func skipToPreparedNextWaveTrack() -> Bool {
        skipCrossfadeCount += 1
        return acceptCrossfadeSkip
    }

    func toggleWavePlayPause() {
        togglePlayPauseCount += 1
    }
}

final class BGYandexWavePlaybackCoordinatorTests: XCTestCase {
    private func makeTracks(_ ids: [String]) -> [BGYandexTrack] {
        return ids.map { id in
            BGYandexTrack(trackId: id, title: "Track \(id)", artists: ["Artist"], albumId: nil, albumTitle: nil, durationMs: 180_000)
        }
    }

    /// Regression test for Issue #123: start -> A -> enqueue B -> end A -> play B -> enqueue C.
    /// Verifies A is NEVER duplicated in the player queue.
    func testSequenceAToBToCNoDuplicateFirstTrack() {
        let radio = FakeWaveRadio()
        radio.firstResult = .success(makeTracks(["A", "B", "C", "D"]))
        let player = FakeWavePlayer()
        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: { BGYandexWaveQueue(source: radio, prepare: { _ in }) },
            player: player
        )

        coordinator.startOrTogglePlay()

        // A played with replaceQueue=true (itemId=101), B pre-enqueued with replaceQueue=false (itemId=102).
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "B"])
        XCTAssertEqual(player.calls.map { $0.replaceQueue }, [true, false])
        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "A")
        XCTAssertEqual(coordinator.state.upcomingCount, 2, "C and D remain upcoming")
        XCTAssertEqual(radio.sent.map { "\($0.type.rawValue):\($0.trackId ?? "")" }, ["trackStarted:ym:A"])

        // Simulate A playing at 120s / 180s.
        coordinator.handlePlaybackUpdate(currentItemId: 101, currentItemFailed: false, currentItemPlayed: false, nextItemReady: true, position: 120, duration: 180)
        XCTAssertEqual(player.calls.count, 2, "no spurious enqueue while A plays")

        // Simulate BG Mix auto-advancing from A (101) to B (102).
        coordinator.handlePlaybackUpdate(currentItemId: 102, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)

        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "B")
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "B", "C"])
        XCTAssertEqual(player.calls.map { $0.replaceQueue }, [true, false, false])
        XCTAssertEqual(radio.sent.map { "\($0.type.rawValue):\($0.trackId ?? "")" }, [
            "trackStarted:ym:A",
            "trackFinished:ym:A",
            "trackStarted:ym:B",
        ])

        // Simulate BG Mix auto-advancing from B (102) to C (103).
        coordinator.handlePlaybackUpdate(currentItemId: 103, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)

        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "C")
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "B", "C", "D"])
    }

    /// Regression test: consecutive tracks with identical yandexTrackId still advance because matching uses queue item ID.
    func testAdvanceWorksWithDuplicateYandexTrackIds() {
        let radio = FakeWaveRadio()
        radio.firstResult = .success(makeTracks(["SAME", "SAME", "NEXT"]))
        let player = FakeWavePlayer()
        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: { BGYandexWaveQueue(source: radio, prepare: { _ in }) },
            player: player
        )

        coordinator.startOrTogglePlay()
        XCTAssertEqual(player.calls.map { $0.assignedItemId }, [101, 102])

        // Transition 101 -> 102 (same yandexTrackId "SAME", different queue item ID).
        coordinator.handlePlaybackUpdate(currentItemId: 102, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)
        XCTAssertEqual(player.calls.map { $0.trackId }, ["SAME", "SAME", "NEXT"])
    }

    /// Regression test: skipping when B is prepared uses BG Mix crossfade and does NOT double-report trackFinished.
    func testSkipWithPreparedNextUsesCrossfadeWithoutDoubleFeedback() {
        let radio = FakeWaveRadio()
        radio.firstResult = .success(makeTracks(["A", "B", "C"]))
        let player = FakeWavePlayer()
        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: { BGYandexWaveQueue(source: radio, prepare: { _ in }) },
            player: player
        )

        coordinator.startOrTogglePlay()
        coordinator.handlePlaybackUpdate(currentItemId: 101, currentItemFailed: false, currentItemPlayed: false, nextItemReady: true, position: 15, duration: 180)

        coordinator.skip()
        XCTAssertEqual(player.skipCrossfadeCount, 1)

        // Player completes crossfade to 102.
        coordinator.handlePlaybackUpdate(currentItemId: 102, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)

        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "B")
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "B", "C"])
        XCTAssertEqual(radio.sent.map { "\($0.type.rawValue):\($0.trackId ?? "")" }, [
            "trackStarted:ym:A",
            "skip:ym:A",
            "trackStarted:ym:B",
        ])
    }

    /// Regression test: if B fails to download during pre-enqueue, coordinator skips B and enqueues C.
    func testDownloadFailureOnPreEnqueueSkipsToNextTrack() {
        let radio = FakeWaveRadio()
        radio.firstResult = .success(makeTracks(["A", "B", "C"]))
        let player = FakeWavePlayer()
        player.failingTrackIds = ["B"]
        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: { BGYandexWaveQueue(source: radio, prepare: { _ in }) },
            player: player
        )

        coordinator.startOrTogglePlay()
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "C"])
        XCTAssertNil(coordinator.state.error)
    }

    /// Regression test: if current track ends with currentItemId == nil (nothing pre-enqueued), coordinator still plays next track.
    func testCurrentBecomesNilRecoversWithNextTrack() {
        let radio = FakeWaveRadio()
        radio.firstResult = .success(makeTracks(["A"]))
        radio.moreResults = [.success(makeTracks(["B"]))]
        let player = FakeWavePlayer()
        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: { BGYandexWaveQueue(source: radio, prepare: { _ in }) },
            player: player
        )

        coordinator.startOrTogglePlay()
        // Both A and B were loaded because refill ran on start; simulate A ending directly to nil.
        coordinator.handlePlaybackUpdate(currentItemId: nil, currentItemFailed: false, currentItemPlayed: true, nextItemReady: false, position: 180, duration: 180)

        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "B")
        XCTAssertEqual(player.calls.last?.trackId, "B")
        XCTAssertEqual(player.calls.last?.replaceQueue, true)
    }
}
