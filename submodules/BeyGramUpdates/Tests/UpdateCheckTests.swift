import XCTest
@testable import BeyGramUpdates

final class UpdateCheckTests: XCTestCase {
    private let sha = String(repeating: "a", count: 64)
    private let url = URL(string: "https://example.invalid/release")!

    private func manifest(versionCode: Int = 7, versionName: String = "0.0.0.7", sha256: String? = nil) -> StableUpdateManifest {
        StableUpdateManifest(schema: 1, versionName: versionName, versionCode: versionCode, apkName: "x.apk", size: 100, sha256: sha256 ?? sha)
    }

    func testNewerManifestIsAvailable() {
        XCTAssertEqual(UpdateCheck.evaluate(manifest: manifest(versionCode: 7), installedVersionCode: 6, releaseURL: url),
                       .available(versionName: "0.0.0.7", releaseURL: url))
    }

    func testSameVersionIsUpToDate() {
        XCTAssertEqual(UpdateCheck.evaluate(manifest: manifest(versionCode: 7), installedVersionCode: 7, releaseURL: url), .upToDate)
    }

    func testInvalidHashFails() {
        XCTAssertEqual(UpdateCheck.evaluate(manifest: manifest(sha256: "ABC"), installedVersionCode: 1, releaseURL: url), .failed)
    }

    func testUppercaseHashIsRejected() {
        let upper = String(repeating: "A", count: 64)
        XCTAssertFalse(manifest(sha256: upper).isValid)
    }

    func testWrongSchemaIsRejected() {
        let bad = StableUpdateManifest(schema: 2, versionName: "1.0", versionCode: 1, apkName: "x", size: 1, sha256: sha)
        XCTAssertFalse(bad.isValid)
    }

    func testVersionNameWithLettersIsRejected() {
        XCTAssertFalse(manifest(versionName: "0.0.0.7-beta").isValid)
    }
}
