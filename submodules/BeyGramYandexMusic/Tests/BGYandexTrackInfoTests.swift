import XCTest
@testable import BeyGramYandexMusic

final class BGYandexTrackInfoTests: XCTestCase {
    private func track(title: String = "Song",
                       artists: [String] = ["Artist"],
                       albumId: String? = "456",
                       durationMs: Int64 = 215_000,
                       coverUrl: String? = nil) -> BGYandexTrack {
        return BGYandexTrack(trackId: "123", title: title, artists: artists, albumId: albumId, albumTitle: "Album",
                             durationMs: durationMs, coverUrl: coverUrl)
    }

    func testRowKeyKeepsTheAlbum() {
        XCTAssertEqual(BGYandexTrackInfo(track: track()).rowKey, "ym:123:456")
    }

    func testRowKeyWithoutAlbumIsTheTrackAlone() {
        XCTAssertEqual(BGYandexTrackInfo(track: track(albumId: nil)).rowKey, "ym:123")
    }

    func testBlankTitleIsNilNeverTheIdOrAFileName() {
        XCTAssertNil(BGYandexTrackInfo(track: track(title: "   ")).title)
    }

    func testTitleIsTrimmed() {
        XCTAssertEqual(BGYandexTrackInfo(track: track(title: "  Song  ")).title, "Song")
    }

    func testBlankArtistsAreDropped() {
        XCTAssertEqual(BGYandexTrackInfo(track: track(artists: ["A", " ", "B"])).artists, ["A", "B"])
    }

    func testDurationIsInSecondsAndAbsentWhenZero() {
        XCTAssertEqual(BGYandexTrackInfo(track: track(durationMs: 215_000)).durationSeconds, 215)
        XCTAssertNil(BGYandexTrackInfo(track: track(durationMs: 0)).durationSeconds)
    }

    func testCoverIsAURLWhenYandexSentOne() {
        XCTAssertEqual(BGYandexTrackInfo(track: track(coverUrl: "https://example.test/cover.jpg")).coverURL,
                       URL(string: "https://example.test/cover.jpg"))
        XCTAssertNil(BGYandexTrackInfo(track: track(coverUrl: nil)).coverURL)
    }

    func testTitleIsNeverTheTrackId() {
        let info = BGYandexTrackInfo(track: track(title: "Song"))
        XCTAssertEqual(info.trackId, "123")
        XCTAssertNotEqual(info.title, info.trackId)
    }
}
