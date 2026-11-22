import XCTest
@testable import BeyGramYandexMusic

/// A radio that answers at once, from scripted batches, and records the feedback the queue sends.
private final class ScriptedRadio: BGYandexWaveSource {
    var firstResult: Result<[BGYandexTrack], BGYandexError> = .success([])
    var moreResults: [Result<[BGYandexTrack], BGYandexError>] = []
    private(set) var moreCalls = 0
    private(set) var sent: [BGYandexWaveEvent] = []

    func first(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        completion(firstResult)
    }

    func more(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        moreCalls += 1
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

    /// Only the track id `known` belongs to this radio.
    func likeFeedback(trackId: String, liked: Bool) -> BGYandexWaveEvent? {
        guard trackId == "known" else {
            return nil
        }
        return BGYandexWaveEvent(type: liked ? .like : .unlike, timestampMs: 0, trackId: trackId)
    }

    func sendFeedback(_ event: BGYandexWaveEvent, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        sent.append(event)
        completion(.success(()))
    }
}

/// The clock and the record of prepared tracks, shared with the queue's closures.
private final class Probe {
    var now = Date(timeIntervalSince1970: 0)
    var prepared: [String] = []
}

final class BGYandexWaveQueueTests: XCTestCase {
    private var radio: ScriptedRadio!
    private var probe: Probe!
    private var queue: BGYandexWaveQueue!

    override func setUp() {
        super.setUp()
        radio = ScriptedRadio()
        probe = Probe()
        let probe = self.probe!
        queue = BGYandexWaveQueue(source: radio,
                                  prepare: { track in probe.prepared.append(track.trackId) },
                                  now: { probe.now })
    }

    private func tracks(_ ids: [String]) -> [BGYandexTrack] {
        return ids.map { id in
            BGYandexTrack(trackId: id, title: "Song \(id)", artists: ["Artist"], albumId: nil, albumTitle: nil, durationMs: 1000)
        }
    }

    func testStartPreparesTheFirstTrackAndDoesNotRefillWhileAhead() {
        radio.firstResult = .success(tracks(["1", "2", "3", "4", "5"]))
        var first: BGYandexTrack?
        queue.start { result in
            if case let .success(track) = result {
                first = track
            }
        }
        XCTAssertEqual(first?.trackId, "1")
        XCTAssertEqual(probe.prepared, ["1"])
        XCTAssertEqual(radio.moreCalls, 0)
        XCTAssertEqual(queue.upcomingTracks.count, 5)
    }

    func testTakeNextReturnsInOrderAndRefillsWhenShort() {
        radio.firstResult = .success(tracks(["1", "2", "3", "4"]))
        radio.moreResults = [.success(tracks(["5", "6"]))]
        queue.start { _ in }
        XCTAssertEqual(radio.moreCalls, 0)
        XCTAssertEqual(queue.takeNext()?.trackId, "1")
        XCTAssertEqual(radio.moreCalls, 1)
        XCTAssertEqual(queue.upcomingTracks.map { $0.trackId }, ["2", "3", "4", "5", "6"])
    }

    func testFailedRefillWaitsForTheRetryDelay() {
        radio.firstResult = .success(tracks(["1", "2"]))
        radio.moreResults = [.failure(.network), .success(tracks(["3"]))]
        queue.start { _ in }
        XCTAssertEqual(radio.moreCalls, 1)
        _ = queue.takeNext()
        XCTAssertEqual(radio.moreCalls, 1, "the pause holds the refill")
        probe.now = probe.now.addingTimeInterval(BGYandexWaveQueue.retryDelay + 1)
        _ = queue.takeNext()
        XCTAssertEqual(radio.moreCalls, 2)
        XCTAssertTrue(queue.upcomingTracks.contains { $0.trackId == "3" })
    }

    func testEachTrackIsPreparedOnce() {
        radio.firstResult = .success(tracks(["1", "2", "3", "4", "5"]))
        queue.start { _ in }
        _ = queue.takeNext()
        _ = queue.takeNext()
        XCTAssertEqual(probe.prepared, ["1", "2", "3"])
    }

    func testListeningIsReportedAsRadioEvents() {
        queue.trackStarted(rowKey: "ym:1")
        queue.trackFinished(rowKey: "ym:1", playedSeconds: 200)
        queue.trackSkipped(rowKey: "ym:2", playedSeconds: 12)
        XCTAssertEqual(radio.sent.map { $0.type }, [.trackStarted, .trackFinished, .skip])
        XCTAssertEqual(radio.sent[1].playedSeconds, 200)
        XCTAssertEqual(radio.sent[2].playedSeconds, 12)
    }

    func testLikesGoOnlyForTracksOfThisRadio() {
        queue.setLiked(trackId: "unknown", liked: true)
        XCTAssertTrue(radio.sent.isEmpty)
        queue.setLiked(trackId: "known", liked: true)
        XCTAssertEqual(radio.sent.map { $0.type }, [.like])
    }

    func testStopEmptiesTheQueueAndAsksForNothingMore() {
        radio.firstResult = .success(tracks(["1", "2"]))
        queue.start { _ in }
        let callsBeforeStop = radio.moreCalls
        queue.stop()
        XCTAssertNil(queue.takeNext())
        XCTAssertTrue(queue.upcomingTracks.isEmpty)
        XCTAssertEqual(radio.moreCalls, callsBeforeStop)
    }
}
