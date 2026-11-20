import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Fixed, non-secret device facts for the bug report: the build number, the iOS version and the device model.
///
/// Only system values are read: the bundle's version strings, the OS version and the hardware identifier from
/// `uname`. The VPN and proxy flags are not set here, because the app layer owns those states.
public enum BugReportDeviceInfo {
    /// The client meta for this app on this device. `bundle` and `processInfo` can be replaced in tests.
    public static func current(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo,
        locale: Locale = .current
    ) -> BugReportClientMeta {
        clientMeta(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            osVersion: processInfo.operatingSystemVersion,
            deviceModel: machineIdentifier(),
            localeIdentifier: locale.identifier
        )
    }

    /// Builds the meta from explicit values. This is a pure mapping, so it can be tested without a device.
    /// A build number that is not an integer gives no `app_version_code`.
    public static func clientMeta(
        appVersion: String?,
        buildNumber: String?,
        osVersion: OperatingSystemVersion,
        deviceModel: String?,
        localeIdentifier: String
    ) -> BugReportClientMeta {
        BugReportClientMeta(
            appVersion: appVersion,
            appVersionCode: buildNumber.flatMap { Int($0) },
            platform: "ios",
            osVersion: "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
            deviceModel: deviceModel,
            locale: localeIdentifier
        )
    }

    /// The hardware identifier from `uname`, such as "iPhone17,1". Nil when the system reports nothing.
    public static func machineIdentifier() -> String? {
        var info = utsname()
        guard uname(&info) == 0 else {
            return nil
        }
        let machine = withUnsafeBytes(of: info.machine) { raw -> String? in
            guard let base = raw.baseAddress else {
                return nil
            }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        guard let value = machine, !value.isEmpty else {
            return nil
        }
        return value
    }
}
