import XCTest
@testable import BeyGramYandexMusic

final class BGYandexTests: XCTestCase {
    private let credentials = BGYandexCredentials(clientId: "id", clientSecret: "secret")

    // MARK: Availability, consent and pacing

    func testSourceStaysHiddenWithoutCredentials() {
        let empty = BGYandexCredentials(clientId: "", clientSecret: "")
        XCTAssertFalse(BGYandexAvailability.isAvailable(flagEnabled: true, credentials: empty, consentAccepted: true))
    }

    func testSourceStaysHiddenWithoutFlagOrConsent() {
        XCTAssertFalse(BGYandexAvailability.isAvailable(flagEnabled: false, credentials: credentials, consentAccepted: true))
        XCTAssertFalse(BGYandexAvailability.isAvailable(flagEnabled: true, credentials: credentials, consentAccepted: false))
        XCTAssertTrue(BGYandexAvailability.isAvailable(flagEnabled: true, credentials: credentials, consentAccepted: true))
    }

    func testConsentIsOffByDefaultAndCanBeAccepted() {
        let suite = UserDefaults(suiteName: "bgyandex.tests.\(UUID().uuidString)")!
        let consent = BGYandexConsent(defaults: suite)
        XCTAssertFalse(consent.isAccepted)
        consent.accept()
        XCTAssertTrue(consent.isAccepted)
        consent.revoke()
        XCTAssertFalse(consent.isAccepted)
    }

    func testPacingKeepsQuarterSecondGap() {
        var gate = BGYandexRequestGate()
        XCTAssertEqual(gate.reserve(now: 10), 0, accuracy: 0.0001)
        XCTAssertEqual(gate.reserve(now: 10), 0.25, accuracy: 0.0001)
        XCTAssertEqual(gate.reserve(now: 10), 0.5, accuracy: 0.0001)
    }

    func testRateLimitPausesWholeQueue() {
        var gate = BGYandexRequestGate()
        gate.reportRateLimited(retryAfterHeader: "7", now: 100)
        XCTAssertEqual(gate.reserve(now: 101), 6, accuracy: 0.0001)
    }

    func testRateLimitWithoutHeaderUsesDefault() {
        var gate = BGYandexRequestGate()
        gate.reportRateLimited(retryAfterHeader: nil, now: 0)
        XCTAssertEqual(gate.reserve(now: 0), BGYandexConfig.defaultRetryAfter, accuracy: 0.0001)
    }

    func testPauseRemainingCountsDownTheRateLimit() {
        var gate = BGYandexRequestGate()
        gate.reportRateLimited(retryAfterHeader: "10", now: 0)
        XCTAssertEqual(gate.pauseRemaining(now: 4), 6, accuracy: 0.0001)
        XCTAssertEqual(gate.pauseRemaining(now: 20), 0, accuracy: 0.0001)
    }

    func testSerialQueueRunsOneOperationAtATime() {
        let queue = BGYandexSerialQueue()
        var order: [Int] = []
        var finishers: [() -> Void] = []
        queue.run { done in
            order.append(1)
            finishers.append(done)
        }
        queue.run { done in
            order.append(2)
            finishers.append(done)
        }
        XCTAssertEqual(order, [1])
        finishers.removeFirst()()
        XCTAssertEqual(order, [1, 2])
        finishers.removeFirst()()
        XCTAssertEqual(order, [1, 2])
    }

    // MARK: Device sign-in and tokens

    func testFormBodyEncodesReservedCharacters() {
        let body = BGYandexDeviceFlow.formBody([("code", "a+b c&=")])
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "code=a%2Bb%20c%26%3D")
    }

    func testFormBodyKeepsCommaEncoded() {
        // Track lists are sent as `track-ids=1,2`; the comma is encoded, as Android's URLEncoder does.
        let body = BGYandexDeviceFlow.formBody([("track-ids", "1,2")])
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "track-ids=1%2C2")
    }

    func testPollOutcomes() {
        let pending = Data("{\"error\":\"authorization_pending\"}".utf8)
        let slow = Data("{\"error\":\"slow_down\"}".utf8)
        let expired = Data("{\"error\":\"expired_token\"}".utf8)
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: 400, body: pending), .pending)
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: 400, body: slow), .slowDown)
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: 400, body: expired), .failed(.sessionExpired))
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: nil, body: nil), .failed(.network))
    }

    func testTokenResponseIsParsed() {
        let body = Data("{\"access_token\":\"t\",\"refresh_token\":\"r\",\"expires_in\":3600}".utf8)
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: 200, body: body),
                       .tokens(BGYandexTokens(accessToken: "t", refreshToken: "r", expiresIn: 3600)))
    }

    func testRefreshAnswerWithoutRefreshTokenParsesAsNil() {
        // The session keeps its old refresh token when the answer has none (see BGYandexService.finishRefresh).
        let body = Data("{\"access_token\":\"new\",\"expires_in\":60}".utf8)
        XCTAssertEqual(BGYandexOAuth.parseRefresh(body), BGYandexOAuth.Refreshed(accessToken: "new", refreshToken: nil, expiresIn: 60))
    }

    func testDeviceCodeIsParsedWithDefaults() {
        let body = Data("{\"device_code\":\"dc\",\"user_code\":\"UC\",\"verification_url\":\"https://ya.ru/device\"}".utf8)
        XCTAssertEqual(BGYandexDeviceFlow.parseDeviceCode(body),
                       BGYandexDeviceCode(deviceCode: "dc", userCode: "UC", verificationUrl: "https://ya.ru/device", expiresIn: 300, interval: 5))
    }

    // MARK: Links, accounts and errors

    func testDownloadInfoIsParsedAndSigned() {
        let xml = "<?xml version=\"1.0\"?><download-info><host>s1.example</host><path>/get/track.mp3</path><ts>123</ts><s>abc</s></download-info>"
        let info = BGYandexAPI.parseDownloadInfo(xml)
        XCTAssertEqual(info, BGYandexAPI.DownloadInfo(host: "s1.example", path: "/get/track.mp3", ts: "123", s: "abc"))
        guard let parsed = info else {
            XCTFail("download info was not parsed")
            return
        }
        XCTAssertEqual(BGYandexAPI.directLink(parsed)?.absoluteString,
                       "https://s1.example/get-mp3/397e3ab8dde222691699f60954c292a3/123/get/track.mp3")
    }

    func testDoctypeIsRefused() {
        XCTAssertNil(BGYandexAPI.parseDownloadInfo("<!DOCTYPE x [<!ENTITY e \"y\">]><download-info><host>h</host><path>/p</path><ts>1</ts><s>s</s></download-info>"))
    }

    func testAccountParsesUidAndPlus() {
        let root: [String: Any] = ["result": ["account": ["uid": 42, "login": "user"], "plus": ["has_plus": true]]]
        XCTAssertEqual(BGYandexAPI.parseAccount(root), BGYandexAccount(uid: "42", displayName: "user", hasPlus: true))
    }

    func testFileNameIsSafe() {
        XCTAssertEqual(BGYandexTrackResolver.fileName(trackId: "../12/3"), "ym-123.mp3")
    }

    func testErrorMappingForStatuses() {
        XCTAssertEqual(BGYandexClient.error(for: nil), .network)
        XCTAssertEqual(BGYandexClient.error(for: BGYandexHTTPResponse(statusCode: 401, body: Data(), retryAfterHeader: nil)), .sessionExpired)
        XCTAssertEqual(BGYandexClient.error(for: BGYandexHTTPResponse(statusCode: 404, body: Data(), retryAfterHeader: nil)), .notFound)
        XCTAssertEqual(BGYandexClient.error(for: BGYandexHTTPResponse(statusCode: 429, body: Data(), retryAfterHeader: nil)), .rateLimited)
        XCTAssertEqual(BGYandexClient.error(for: BGYandexHTTPResponse(statusCode: 403, body: Data(), retryAfterHeader: nil)), .unavailable)
        XCTAssertEqual(BGYandexClient.error(for: BGYandexHTTPResponse(statusCode: 503, body: Data(), retryAfterHeader: nil)), .unavailable)
    }

    func testTemporaryFailuresAreNotVerdicts() {
        XCTAssertTrue(BGYandexError.rateLimited.isTemporary)
        XCTAssertTrue(BGYandexError.subscriptionRequired.isTemporary)
        XCTAssertTrue(BGYandexError.notSignedIn.isTemporary)
        XCTAssertFalse(BGYandexError.notFound.isTemporary)
        XCTAssertFalse(BGYandexError.serviceChanged.isTemporary)
    }

    // MARK: Tracks, playlists and lyrics

    func testRowKeyKeepsAlbumWhenKnown() {
        let withAlbum = BGYandexTrack(trackId: "1", title: "t", artists: [], albumId: "9", albumTitle: nil, durationMs: 0)
        let withoutAlbum = BGYandexTrack(trackId: "1", title: "t", artists: [], albumId: nil, albumTitle: nil, durationMs: 0)
        XCTAssertEqual(withAlbum.rowKey, "ym:1:9")
        XCTAssertEqual(withoutAlbum.rowKey, "ym:1")
        XCTAssertEqual(BGYandexWaveSession.queueId(for: withAlbum), "1:9")
        XCTAssertEqual(BGYandexWaveSession.queueId(for: withoutAlbum), "1")
    }

    func testTrackParsesCoverAvailabilityAndArtistIds() {
        let object: [String: Any] = [
            "id": 77,
            "title": "Song",
            "durationMs": 180_000,
            "coverUri": "avatars.yandex.net/get/1/%%",
            "available": false,
            "artists": [["id": 5, "name": "Artist"], ["name": "NoId"]],
            "albums": [["id": 9, "title": "Album"]],
        ]
        let track = BGYandexAPI.parseTrack(object)
        XCTAssertEqual(track?.trackId, "77")
        XCTAssertEqual(track?.coverUrl, "https://avatars.yandex.net/get/1/200x200")
        XCTAssertEqual(track?.isAvailable, false)
        XCTAssertEqual(track?.artists, ["Artist", "NoId"])
        XCTAssertEqual(track?.artistRefs, [BGYandexArtistRef(id: "5", name: "Artist")])
        XCTAssertEqual(track?.albumId, "9")
        XCTAssertEqual(track?.albumTitle, "Album")
    }

    func testPlaylistOwnershipAndUuid() {
        let item: [String: Any] = [
            "kind": 1000,
            "title": "Mix",
            "trackCount": 3,
            "owner": ["uid": 42, "login": "me"],
            "playlistUuid": "ABC-1",
        ]
        let playlist = BGYandexAPI.parsePlaylist(item, uid: "42")
        XCTAssertEqual(playlist?.kind, "1000")
        XCTAssertEqual(playlist?.isOwn, true)
        XCTAssertEqual(playlist?.ownerName, "me")
        XCTAssertEqual(playlist?.matchesUuid("abc-1"), true)
        // The wanted uuid is compared trimmed and lower-cased, like the stored one.
        XCTAssertEqual(playlist?.matchesUuid(" ABC-1 "), true)
        XCTAssertEqual(playlist?.matchesUuid("abc-2"), false)
        XCTAssertEqual(BGYandexAPI.parsePlaylist(item, uid: "7")?.isOwn, false)
    }

    func testLyricsParseTimeTagsAndSort() {
        let text = "[ar:Artist]\n[00:12.5]second\n[00:01.00][00:05]first\n[00:20]\n"
        XCTAssertEqual(BGYandexLRC.parse(text), [
            BGYandexLyricLine(timeMs: 1_000, text: "first"),
            BGYandexLyricLine(timeMs: 5_000, text: "first"),
            BGYandexLyricLine(timeMs: 12_500, text: "second"),
        ])
    }

    func testPlainTextIsUsedOnlyWithoutTimedLines() {
        XCTAssertEqual(BGYandexLRC.plainText("[ar:x]\n hello \n\nworld"), "hello\nworld")
        XCTAssertNil(BGYandexLRC.lyrics(from: "[00:01]a", copyrightHolder: nil).plainText)
        XCTAssertEqual(BGYandexLRC.lyrics(from: "hello\nworld", copyrightHolder: "Holder").plainText, "hello\nworld")
    }

    // MARK: Radio and listening

    func testRadioSeedsPutDiversityAfterBase() {
        XCTAssertEqual(BGYandexWaveSeed.seeds(base: BGYandexWaveSeed.myWave, diversity: .discover),
                       ["user:onyourwave", "settingDiversity:discover"])
        XCTAssertEqual(BGYandexWaveSeed.seeds(base: BGYandexWaveSeed.myWave, diversity: .popular),
                       ["user:onyourwave", "settingDiversity:popular"])
        XCTAssertEqual(BGYandexWaveSeed.seeds(base: "track:1", diversity: .standard), ["track:1"])
    }

    func testRadioEventJSONCarriesTypeAndTrack() {
        let event = BGYandexWaveEvent(type: .skip, timestampMs: 0, trackId: "1:9", playedSeconds: 12.5)
        let json = event.json()
        XCTAssertEqual(json["type"] as? String, "skip")
        XCTAssertEqual(json["trackId"] as? String, "1:9")
        XCTAssertEqual(json["totalPlayedSeconds"] as? Double, 12.5)
        XCTAssertEqual(json["timestamp"] as? String, "1970-01-01T00:00:00.000Z")
    }

    private func snapshot(_ key: String?, position: Int64 = 0, duration: Int64 = 0, playing: Bool = true,
                          ended: Bool = false, active: Bool = true) -> BGYandexListenSnapshot {
        return BGYandexListenSnapshot(radioActive: active, rowKey: key, playing: playing, positionMs: position, durationMs: duration, ended: ended)
    }

    func testListenTrackerCountsFinishedAndSkipped() {
        var tracker = BGYandexListenTracker { $0.hasPrefix("ym:") }
        XCTAssertEqual(tracker.onState(snapshot("ym:1", position: 0, duration: 200_000)), [.started(rowKey: "ym:1")])
        XCTAssertEqual(tracker.onState(snapshot("ym:1", position: 199_000, duration: 200_000)), [])
        // The first track reaches its end; the second starts.
        XCTAssertEqual(tracker.onState(snapshot("ym:2", position: 0, duration: 180_000)), [
            .finished(rowKey: "ym:1", playedSeconds: 200),
            .started(rowKey: "ym:2"),
        ])
        // The second is left after 10 seconds: skipped. The radio stops being the queue: closed.
        XCTAssertEqual(tracker.onState(snapshot("ym:2", position: 10_000, duration: 180_000)), [])
        XCTAssertEqual(tracker.onState(snapshot(nil, active: false)), [.skipped(rowKey: "ym:2", playedSeconds: 10)])
        XCTAssertTrue(tracker.closed)
        XCTAssertEqual(tracker.onState(snapshot("ym:2", position: 20_000, duration: 180_000)), [])
    }

    // MARK: Yandex Music links

    func testAlbumAndTrackLinksOpenNatively() {
        XCTAssertEqual(BGYandexLink.target(from: "https://music.yandex.ru/album/12345"), .album(albumId: "12345"))
        XCTAssertEqual(BGYandexLink.target(from: "https://music.yandex.ru/album/12345/track/67890"),
                       .track(trackId: "67890", albumId: "12345"))
        XCTAssertEqual(BGYandexLink.target(from: "music.yandex.ru/track/67890?utm_source=share#x"),
                       .track(trackId: "67890", albumId: nil))
    }

    func testLinkHostsAndSchemeAreCheckedLikeAndroid() {
        XCTAssertEqual(BGYandexLink.target(from: "  https://WWW.Music.Yandex.KZ/track/1  "), .track(trackId: "1", albumId: nil))
        XCTAssertEqual(BGYandexLink.target(from: "http://music.yandex.uz/album/2"), .album(albumId: "2"))
        XCTAssertNil(BGYandexLink.target(from: "ftp://music.yandex.ru/track/1"))
        XCTAssertNil(BGYandexLink.target(from: "https://example.com/track/1"))
        XCTAssertNil(BGYandexLink.target(from: "https://user@music.yandex.ru/track/1"))
    }

    func testPlaylistUuidKeepsItsPrefixAndLowercasesTheRest() {
        XCTAssertEqual(BGYandexLink.target(from: "https://music.yandex.ru/playlists/LK.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
                       .playlist(uuid: "lk.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        XCTAssertEqual(BGYandexLink.target(from: "https://music.yandex.ru/playlists/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee#share"),
                       .playlist(uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        XCTAssertNil(BGYandexLink.target(from: "https://music.yandex.ru/playlists/lk.lk.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }

    func testUnsupportedAddressesStayInTheBrowser() {
        XCTAssertNil(BGYandexLink.target(from: ""))
        XCTAssertNil(BGYandexLink.target(from: "https://music.yandex.ru/artist/123"))
        XCTAssertNil(BGYandexLink.target(from: "https://music.yandex.ru/users/someone/playlists/3"))
        XCTAssertNil(BGYandexLink.target(from: "https://music.yandex.ru/track/abc"))
        XCTAssertNil(BGYandexLink.target(from: "https://music.yandex.ru/track/123456789012345678901"))
        XCTAssertNil(BGYandexLink.target(from: "https://music.yandex.ru/album/1/track/"))
    }

    // MARK: Yandex playback

    func testRowKeyGivesTrackIdOnlyForYandexRows() {
        XCTAssertEqual(BGYandexPlayback.trackId(rowKey: "ym:12345"), "12345")
        XCTAssertEqual(BGYandexPlayback.trackId(rowKey: "ym:12345:678"), "12345")
        XCTAssertNil(BGYandexPlayback.trackId(rowKey: "tg:12345"))
        XCTAssertNil(BGYandexPlayback.trackId(rowKey: "ym:abc"))
        XCTAssertNil(BGYandexPlayback.trackId(rowKey: "ym:12345:x"))
        XCTAssertNil(BGYandexPlayback.trackId(rowKey: "ym:1:2:3"))
        XCTAssertNil(BGYandexPlayback.trackId(rowKey: "ym:"))
    }

    func testServiceErrorsMapToPlayerErrors() {
        XCTAssertEqual(BGYandexPlayback.error(for: .sessionExpired), .notSignedIn)
        XCTAssertEqual(BGYandexPlayback.error(for: .subscriptionRequired), .subscriptionRequired)
        XCTAssertEqual(BGYandexPlayback.error(for: .rateLimited), .rateLimited)
        XCTAssertEqual(BGYandexPlayback.error(for: .network), .network)
        XCTAssertEqual(BGYandexPlayback.error(for: .notFound), .unavailable)
        XCTAssertEqual(BGYandexPlayback.error(for: .unknown), .unavailable)
    }
}
