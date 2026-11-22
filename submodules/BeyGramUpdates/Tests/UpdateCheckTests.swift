import XCTest
@testable import BeyGramUpdates

final class UpdateCheckTests: XCTestCase {
    private let sha = String(repeating: "a", count: 64)
    private let url = URL(string: "https://github.com/Beykus-Y/BeyGram-iOS/releases/tag/v0.0.2")!

    private func manifest(
        schema: Int = 1,
        platform: String = "ios",
        channel: String = "dev",
        versionName: String = "0.0.2",
        buildNumber: Int = 1005,
        ipaName: String = "BeyGram-DEV.ipa",
        commitSha: String? = "deadbeef",
        changelog: String? = "Fixes",
        sha256: String? = nil
    ) -> IOSUpdateManifest {
        IOSUpdateManifest(
            schema: schema,
            platform: platform,
            channel: channel,
            versionName: versionName,
            buildNumber: buildNumber,
            ipaName: ipaName,
            commitSha: commitSha,
            changelog: changelog,
            size: 1024,
            sha256: sha256 ?? sha
        )
    }

    func testRepositoryPointsToBeyGramIOS() {
        XCTAssertTrue(UpdateCheck.releasesAPI.absoluteString.contains("Beykus-Y/BeyGram-iOS"))
        XCTAssertFalse(UpdateCheck.releasesAPI.absoluteString.contains("/BeyGram/releases"))
    }

    func testNoReleasesReturnsNoReleases() throws {
        let emptyJSON = Data("[]".utf8)
        let selected = try UpdateCheck.selectCompatibleRelease(fromReleasesJSON: emptyJSON, channel: .dev)
        XCTAssertNil(selected)
    }

    func testOutdatedVersionAndBuildReturnsAvailable() {
        let m = manifest(versionName: "0.0.2", buildNumber: 1006)
        let result = UpdateCheck.evaluate(
            manifest: m,
            installedVersionName: "0.0.1",
            installedBuildNumber: 1004,
            installedChannel: .dev,
            availableAssetNames: ["BeyGram-DEV.ipa", "BeyGram-ios-dev-update.json"],
            releaseURL: url
        )
        XCTAssertEqual(result, .available(UpdateAvailableInfo(
            versionName: "0.0.2",
            buildNumber: 1006,
            channel: .dev,
            commitSha: "deadbeef",
            changelog: "Fixes",
            releaseURL: url
        )))
    }

    func testSameVersionNewerBuildReturnsAvailable() {
        let m = manifest(versionName: "0.0.1", buildNumber: 1005)
        let result = UpdateCheck.evaluate(
            manifest: m,
            installedVersionName: "0.0.1",
            installedBuildNumber: 1004,
            installedChannel: .dev,
            availableAssetNames: ["BeyGram-DEV.ipa"],
            releaseURL: url
        )
        XCTAssertEqual(result, .available(UpdateAvailableInfo(
            versionName: "0.0.1",
            buildNumber: 1005,
            channel: .dev,
            commitSha: "deadbeef",
            changelog: "Fixes",
            releaseURL: url
        )))
    }

    func testSameVersionAndBuildReturnsUpToDate() {
        let m = manifest(versionName: "0.0.1", buildNumber: 1005)
        let result = UpdateCheck.evaluate(
            manifest: m,
            installedVersionName: "0.0.1",
            installedBuildNumber: 1005,
            installedChannel: .dev,
            availableAssetNames: ["BeyGram-DEV.ipa"],
            releaseURL: url
        )
        XCTAssertEqual(result, .upToDate)
    }

    func testAndroidPlatformAndApkAreRejected() {
        let androidPlatform = manifest(platform: "android")
        XCTAssertFalse(androidPlatform.isValid)
        XCTAssertEqual(UpdateCheck.evaluate(
            manifest: androidPlatform,
            installedVersionName: "0.0.1",
            installedBuildNumber: 1,
            installedChannel: .dev,
            releaseURL: url
        ), .failed)

        let apkAsset = manifest(ipaName: "BeyGram.apk")
        XCTAssertFalse(apkAsset.isValid)

        let m = manifest()
        let onlyApkAssets = UpdateCheck.evaluate(
            manifest: m,
            installedVersionName: "0.0.1",
            installedBuildNumber: 1,
            installedChannel: .dev,
            availableAssetNames: ["BeyGram.apk", "BeyGram-stable-update.json"],
            releaseURL: url
        )
        XCTAssertEqual(onlyApkAssets, .failed)
    }

    func testChannelMismatchIsRejected() {
        let m = manifest(channel: "release")
        let result = UpdateCheck.evaluate(
            manifest: m,
            installedVersionName: "0.0.1",
            installedBuildNumber: 1,
            installedChannel: .dev,
            availableAssetNames: ["BeyGram-DEV.ipa"],
            releaseURL: url
        )
        XCTAssertEqual(result, .failed)
    }

    func testMalformedManifestIsRejected() {
        XCTAssertFalse(manifest(schema: 2).isValid)
        XCTAssertFalse(manifest(sha256: "ABC").isValid)
        XCTAssertFalse(manifest(versionName: "0.0.1-beta").isValid)
        XCTAssertThrowsError(try UpdateCheck.selectCompatibleRelease(fromReleasesJSON: Data("not-json".utf8), channel: .dev))
    }
}
