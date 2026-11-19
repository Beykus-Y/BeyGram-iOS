import Foundation

/// What BeyGram keeps about the Mihomo proxy between launches. The subscription and Telegram's settings
/// snapshot are stored as plain text inside the app sandbox, the same way Telegram stores its proxy settings.
public struct MihomoProxyState: Codable, Equatable {
    /// An https link, or the subscription text itself. It can hold node passwords.
    public var subscriptionSource: String?
    /// Server names of the last valid subscription. The profile itself is rebuilt on every start.
    public var serverNames: [String]
    public var selectedNode: String?
    public var isRunning: Bool
    /// Telegram's proxy settings as they were before the first connect, encoded by the caller. Restored on disconnect.
    public var telegramSettingsBeforeConnect: Data?

    public init(subscriptionSource: String? = nil, serverNames: [String] = [], selectedNode: String? = nil, isRunning: Bool = false, telegramSettingsBeforeConnect: Data? = nil) {
        self.subscriptionSource = subscriptionSource
        self.serverNames = serverNames
        self.selectedNode = selectedNode
        self.isRunning = isRunning
        self.telegramSettingsBeforeConnect = telegramSettingsBeforeConnect
    }
}

/// Reads and writes `state.json` in the given directory.
public final class MihomoProxyStateStore {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("state.json")
    }

    /// Returns the saved state, or an empty one when there is no readable file.
    public func load() -> MihomoProxyState {
        guard let data = try? Data(contentsOf: fileURL), let state = try? JSONDecoder().decode(MihomoProxyState.self, from: data) else {
            return MihomoProxyState()
        }
        return state
    }

    public func save(_ state: MihomoProxyState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
