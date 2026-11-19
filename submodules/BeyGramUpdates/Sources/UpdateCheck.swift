import Foundation

/// Manual update check for BeyGram (contract: docs/stable-updates.md, server side).
///
/// Runs only when the user asks. It reads the latest GitHub Release and its `BeyGram-stable-update.json`
/// manifest, validates it, and reports whether the release is newer. It never downloads or installs
/// anything: iOS has no equivalent of an APK install, so the result is a link for the user to open.
public struct StableUpdateManifest: Decodable, Equatable {
    public let schema: Int
    public let versionName: String
    public let versionCode: Int
    public let apkName: String
    public let size: Int64
    public let sha256: String

    public var isValid: Bool {
        guard schema == 1,
              versionCode >= 1, versionCode <= 2_100_000_000,
              !versionName.isEmpty,
              versionName.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              size > 0,
              sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            return false
        }
        return true
    }
}

public enum UpdateCheckResult: Equatable {
    case upToDate
    case available(versionName: String, releaseURL: URL)
    case failed
}

public enum UpdateCheck {
    public static let manifestAssetName = "BeyGram-stable-update.json"
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/Beykus-Y/BeyGram/releases/latest")!

    /// Decides the result from a parsed manifest and the installed build number.
    public static func evaluate(manifest: StableUpdateManifest, installedVersionCode: Int, releaseURL: URL) -> UpdateCheckResult {
        guard manifest.isValid else {
            return .failed
        }
        return manifest.versionCode > installedVersionCode
            ? .available(versionName: manifest.versionName, releaseURL: releaseURL)
            : .upToDate
    }

    /// Reads the latest release and its manifest. Any network or parsing failure is `.failed`.
    public static func check(installedVersionCode: Int, session: URLSession = .shared) async -> UpdateCheckResult {
        do {
            var releaseRequest = URLRequest(url: latestReleaseAPI)
            releaseRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (releaseData, releaseResponse) = try await session.data(for: releaseRequest)
            guard (releaseResponse as? HTTPURLResponse)?.statusCode == 200,
                  let release = try JSONSerialization.jsonObject(with: releaseData) as? [String: Any],
                  let htmlURLString = release["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString),
                  let assets = release["assets"] as? [[String: Any]],
                  let manifestURLString = assets.first(where: { $0["name"] as? String == manifestAssetName })?["browser_download_url"] as? String,
                  let manifestURL = URL(string: manifestURLString) else {
                return .failed
            }
            let (manifestData, manifestResponse) = try await session.data(from: manifestURL)
            guard (manifestResponse as? HTTPURLResponse)?.statusCode == 200 else {
                return .failed
            }
            let manifest = try JSONDecoder().decode(StableUpdateManifest.self, from: manifestData)
            return evaluate(manifest: manifest, installedVersionCode: installedVersionCode, releaseURL: htmlURL)
        } catch {
            return .failed
        }
    }
}
