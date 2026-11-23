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

    /// Regression test for Issue #123 & #128:
    /// start -> A queued -> A confirmed on master deck -> B pre-enqueued -> B confirmed on master deck -> C pre-enqueued.
    func testSequenceAToBToCNoDuplicateFirstTrack() {
        let radio = FakeWaveRadio()
        radio.firstResult = .success(makeTracks(["A", "B", "C", "D"]))
        let player = FakeWavePlayer()
        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: { BGYandexWaveQueue(source: radio, prepare: { _ in }) },
            player: player
        )

        coordinator.startOrTogglePlay()

        // Only A is submitted until master deck confirms A is audible.
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A"])
        XCTAssertEqual(player.calls.map { $0.replaceQueue }, [true])

        // Master deck confirms A (101) is loaded/playing -> B (102) is pre-enqueued.
        coordinator.handlePlaybackUpdate(currentItemId: 101, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "B"])
        XCTAssertEqual(player.calls.map { $0.replaceQueue }, [true, false])
        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "A")
        XCTAssertEqual(coordinator.state.upcomingCount, 2, "C and D remain upcoming")
        XCTAssertEqual(radio.sent.map { "\($0.type.rawValue):\($0.trackId ?? "")" }, ["trackStarted:ym:A"])

        // Simulate A playing at 120s / 180s.
        coordinator.handlePlaybackUpdate(currentItemId: 101, currentItemFailed: false, currentItemPlayed: false, nextItemReady: true, position: 120, duration: 180)
        XCTAssertEqual(player.calls.count, 2, "no spurious enqueue while A plays")

        // Simulate BG Mix auto-advancing master deck from A (101) to B (102).
        coordinator.handlePlaybackUpdate(currentItemId: 102, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)

        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "B")
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "B", "C"])
        XCTAssertEqual(player.calls.map { $0.replaceQueue }, [true, false, false])
        XCTAssertEqual(radio.sent.map { "\($0.type.rawValue):\($0.trackId ?? "")" }, [
            "trackStarted:ym:A",
            "trackFinished:ym:A",
            "trackStarted:ym:B",
        ])

        // Simulate BG Mix auto-advancing master deck from B (102) to C (103).
        coordinator.handlePlaybackUpdate(currentItemId: 103, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)

        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "C")
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "B", "C", "D"])
    }

    /// Regression test for Issue #128: transient nil snapshots while replacing deck MUST NOT cause runaway advancing,
    /// and displayed track MUST remain A until B is confirmed on the master deck.
    func testTransientNilSnapshotsDoNotAdvanceAndUIFollowsAudibleMasterDeck() {
        let radio = FakeWaveRadio()
        radio.firstResult = .success(makeTracks(["A", "B", "C", "D"]))
        let player = FakeWavePlayer()
        player.acceptCrossfadeSkip = false // Forces fallback to replaceQueue=true on skip
        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: { BGYandexWaveQueue(source: radio, prepare: { _ in }) },
            player: player
        )

        coordinator.startOrTogglePlay()
        coordinator.handlePlaybackUpdate(currentItemId: 101, currentItemFailed: false, currentItemPlayed: false, nextItemReady: true, position: 10, duration: 180)
        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "A")

        // Skip A -> crossfade rejected -> atomic replace queues B (itemId=103).
        coordinator.skip()
        XCTAssertEqual(player.calls.last?.trackId, "B")
        XCTAssertEqual(player.calls.last?.replaceQueue, true)
        // Before master deck confirms 103, UI still reflects last confirmed audible track A (not jumping ahead to C/D!).
        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "A")

        // Repeated transient nil snapshots while deck B is preparing must NOT advance to C or D!
        for _ in 0..<5 {
            coordinator.handlePlaybackUpdate(currentItemId: nil, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, isStopped: true, position: 0, duration: 0)
        }
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "B", "B"])
        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "A")

        // Master deck finally confirms B (103) -> UI updates to B and pre-enqueues C.
        coordinator.handlePlaybackUpdate(currentItemId: 103, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)
        XCTAssertEqual(coordinator.state.currentTrack?.trackId, "B")
        XCTAssertEqual(player.calls.last?.trackId, "C")
        XCTAssertEqual(player.calls.last?.replaceQueue, false)
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
        coordinator.handlePlaybackUpdate(currentItemId: 101, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)
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
        coordinator.handlePlaybackUpdate(currentItemId: 101, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 0, duration: 180)
        XCTAssertEqual(player.calls.map { $0.trackId }, ["A", "C"])
        XCTAssertNil(coordinator.state.error)
    }

    /// Regression test: if current track ends with player stopped and nothing pre-enqueued, coordinator recovers with next track.
    func testCurrentEndedWhileStoppedRecoversWithNextTrack() {
        let radio = FakeWaveRadio()
        radio.firstResult = .success(makeTracks(["A"]))
        radio.moreResults = [.success(makeTracks(["B"]))]
        let player = FakeWavePlayer()
        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: { BGYandexWaveQueue(source: radio, prepare: { _ in }) },
            player: player
        )

        coordinator.startOrTogglePlay()
        coordinator.handlePlaybackUpdate(currentItemId: 101, currentItemFailed: false, currentItemPlayed: false, nextItemReady: false, position: 10, duration: 180)
        // Simulate A reaching .played and player stopping.
        coordinator.handlePlaybackUpdate(currentItemId: nil, currentItemFailed: false, currentItemPlayed: true, nextItemReady: false, isStopped: true, position: 180, duration: 180)

        XCTAssertEqual(player.calls.last?.trackId, "B")
        XCTAssertEqual(player.calls.last?.replaceQueue, true)
    }
}
