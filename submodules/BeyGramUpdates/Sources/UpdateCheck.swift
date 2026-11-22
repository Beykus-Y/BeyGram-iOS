import Foundation

public enum UpdateChannel: String, Codable, Equatable {
    case dev
    case release

    public var manifestAssetName: String {
        switch self {
        case .dev:
            return "BeyGram-ios-dev-update.json"
        case .release:
            return "BeyGram-ios-update.json"
        }
    }
}

/// Dedicated iOS update manifest (never shares Android's APK manifest).
public struct IOSUpdateManifest: Decodable, Equatable {
    public let schema: Int
    public let platform: String
    public let channel: String
    public let versionName: String
    public let buildNumber: Int
    public let ipaName: String
    public let commitSha: String?
    public let changelog: String?
    public let size: Int64
    public let sha256: String

    public init(
        schema: Int,
        platform: String,
        channel: String,
        versionName: String,
        buildNumber: Int,
        ipaName: String,
        commitSha: String? = nil,
        changelog: String? = nil,
        size: Int64,
        sha256: String
    ) {
        self.schema = schema
        self.platform = platform
        self.channel = channel
        self.versionName = versionName
        self.buildNumber = buildNumber
        self.ipaName = ipaName
        self.commitSha = commitSha
        self.changelog = changelog
        self.size = size
        self.sha256 = sha256
    }

    public var isValid: Bool {
        guard schema == 1,
              platform.lowercased() == "ios",
              UpdateChannel(rawValue: channel.lowercased()) != nil,
              buildNumber >= 1, buildNumber <= 2_100_000_000,
              !versionName.isEmpty,
              versionName.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              ipaName.lowercased().hasSuffix(".ipa"),
              !ipaName.lowercased().hasSuffix(".apk"),
              size > 0,
              sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            return false
        }
        return true
    }
}

public struct UpdateAvailableInfo: Equatable {
    public let versionName: String
    public let buildNumber: Int
    public let channel: UpdateChannel
    public let commitSha: String?
    public let changelog: String?
    public let releaseURL: URL

    public init(
        versionName: String,
        buildNumber: Int,
        channel: UpdateChannel,
        commitSha: String?,
        changelog: String?,
        releaseURL: URL
    ) {
        self.versionName = versionName
        self.buildNumber = buildNumber
        self.channel = channel
        self.commitSha = commitSha
        self.changelog = changelog
        self.releaseURL = releaseURL
    }
}

public enum UpdateCheckResult: Equatable {
    case upToDate
    case noReleases
    case available(UpdateAvailableInfo)
    case failed
}

public enum UpdateCheck {
    public static let releasesAPI = URL(string: "https://api.github.com/repos/Beykus-Y/BeyGram-iOS/releases?per_page=10")!

    /// Compares semantic dotted versions (e.g. "0.0.2" vs "0.0.10").
    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lParts.count, rParts.count)
        for idx in 0..<count {
            let l = idx < lParts.count ? lParts[idx] : 0
            let r = idx < rParts.count ? rParts[idx] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Evaluates a parsed iOS manifest against the installed version, build number, channel, and IPA assets.
    public static func evaluate(
        manifest: IOSUpdateManifest,
        installedVersionName: String,
        installedBuildNumber: Int,
        installedChannel: UpdateChannel,
        availableAssetNames: [String]? = nil,
        releaseURL: URL
    ) -> UpdateCheckResult {
        guard manifest.isValid else {
            return .failed
        }
        guard manifest.channel.lowercased() == installedChannel.rawValue else {
            return .failed
        }
        if let assets = availableAssetNames {
            let hasMatchingIPA = assets.contains { $0 == manifest.ipaName }
            let hasAnyIPA = assets.contains { $0.lowercased().hasSuffix(".ipa") }
            guard hasMatchingIPA && hasAnyIPA else {
                return .failed
            }
        }

        let versionCmp = compareVersions(manifest.versionName, installedVersionName)
        let isNewer: Bool
        switch versionCmp {
        case .orderedDescending:
            isNewer = true
        case .orderedAscending:
            isNewer = false
        case .orderedSame:
            isNewer = manifest.buildNumber > installedBuildNumber
        }

        guard isNewer else {
            return .upToDate
        }
        return .available(UpdateAvailableInfo(
            versionName: manifest.versionName,
            buildNumber: manifest.buildNumber,
            channel: installedChannel,
            commitSha: manifest.commitSha,
            changelog: manifest.changelog,
            releaseURL: releaseURL
        ))
    }

    /// Parses GitHub releases JSON and returns the first compatible iOS release manifest URL and asset names.
    public static func selectCompatibleRelease(
        fromReleasesJSON data: Data,
        channel: UpdateChannel
    ) throws -> (htmlURL: URL, manifestURL: URL, assetNames: [String])? {
        guard let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "BeyGramUpdates", code: 1)
        }
        if releases.isEmpty {
            return nil
        }

        let expectedManifest = channel.manifestAssetName
        for release in releases {
            if (release["draft"] as? Bool) == true {
                continue
            }
            if channel == .release && (release["prerelease"] as? Bool) == true {
                continue
            }
            guard let htmlURLString = release["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString),
                  let assets = release["assets"] as? [[String: Any]] else {
                continue
            }
            let assetNames = assets.compactMap { $0["name"] as? String }
            let hasIPA = assetNames.contains { $0.lowercased().hasSuffix(".ipa") }
            guard hasIPA,
                  let manifestURLString = assets.first(where: { ($0["name"] as? String) == expectedManifest })?["browser_download_url"] as? String,
                  let manifestURL = URL(string: manifestURLString) else {
                continue
            }
            return (htmlURL, manifestURL, assetNames)
        }
        return nil
    }

    /// Reads releases from `Beykus-Y/BeyGram-iOS` and validates the iOS manifest for `channel`.
    public static func check(
        installedVersionName: String,
        installedBuildNumber: Int,
        channel: UpdateChannel,
        session: URLSession = .shared
    ) async -> UpdateCheckResult {
        do {
            var request = URLRequest(url: releasesAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (releaseData, releaseResponse) = try await session.data(for: request)
            if let http = releaseResponse as? HTTPURLResponse, http.statusCode == 404 {
                return .noReleases
            }
            guard (releaseResponse as? HTTPURLResponse)?.statusCode == 200 else {
                return .failed
            }
            guard let selected = try selectCompatibleRelease(fromReleasesJSON: releaseData, channel: channel) else {
                return .noReleases
            }
            let (manifestData, manifestResponse) = try await session.data(from: selected.manifestURL)
            guard (manifestResponse as? HTTPURLResponse)?.statusCode == 200 else {
                return .failed
            }
            let manifest = try JSONDecoder().decode(IOSUpdateManifest.self, from: manifestData)
            return evaluate(
                manifest: manifest,
                installedVersionName: installedVersionName,
                installedBuildNumber: installedBuildNumber,
                installedChannel: channel,
                availableAssetNames: selected.assetNames,
                releaseURL: selected.htmlURL
            )
        } catch {
            return .failed
        }
    }
}
