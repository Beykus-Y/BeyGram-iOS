// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

import Foundation

/// The identifier this installation sends to the subscription host in `X-BeyGram-HWID`. It is a random pseudonym:
/// no device or account identifier is read. The file sits in Application Support and is excluded from backups, so it
/// is not carried to another phone, and it goes with the app on uninstall, the same as the Android identifier.
public enum InstallationIdentifierStore {
    public enum Failure: Error, Equatable {
        case storage
    }

    private static let directoryName = "beygram-mihomo"
    private static let fileName = "installation-id"

    /// Returns this installation's identifier, creating it on first use.
    public static func loadOrCreate() throws -> String {
        let url = try fileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw Failure.storage
            }
            // A damaged file is replaced below. Otherwise it would block every subscription for good.
            if let value = String(data: data, encoding: .utf8), value.hasPrefix("bg-"), value.count > 3 {
                return value
            }
        }
        let created = "bg-" + UUID().uuidString.lowercased()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(created.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw Failure.storage
        }
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        _ = try? target.setResourceValues(values)
        return created
    }

    private static func fileURL() throws -> URL {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return support.appendingPathComponent(directoryName, isDirectory: true).appendingPathComponent(fileName)
        } catch {
            throw Failure.storage
        }
    }
}
