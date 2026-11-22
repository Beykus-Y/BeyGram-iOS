import Foundation
import XCTest

@testable import BeyGramDiagnostics

final class BugReportDeviceInfoTests: XCTestCase {
    func testMapsSystemValuesIntoClientMeta() {
        let meta = BugReportDeviceInfo.clientMeta(
            appVersion: "1.2.3",
            buildNumber: "42",
            osVersion: OperatingSystemVersion(majorVersion: 17, minorVersion: 4, patchVersion: 1),
            deviceModel: "iPhone17,1",
            localeIdentifier: "ru_RU"
        )
        XCTAssertEqual(meta.appVersion, "1.2.3")
        XCTAssertEqual(meta.appVersionCode, 42)
        XCTAssertEqual(meta.platform, "ios")
        XCTAssertEqual(meta.osVersion, "17.4.1")
        XCTAssertEqual(meta.deviceModel, "iPhone17,1")
        XCTAssertEqual(meta.locale, "ru_RU")
        XCTAssertNil(meta.vpnActive)
        XCTAssertNil(meta.proxyEnabled)
    }

    func testBuildNumberThatIsNotAnIntegerGivesNoCode() {
        let meta = BugReportDeviceInfo.clientMeta(
            appVersion: "1.2",
            buildNumber: "2026.1",
            osVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            deviceModel: nil,
            localeIdentifier: "en_US"
        )
        XCTAssertNil(meta.appVersionCode)
        XCTAssertEqual(meta.osVersion, "18.0.0")
        XCTAssertNil(meta.deviceModel)
    }

    func testRunningSystemReportsAHardwareIdentifier() {
        let model = BugReportDeviceInfo.machineIdentifier()
        XCTAssertNotNil(model)
        XCTAssertFalse(model?.isEmpty ?? true)
    }
}
