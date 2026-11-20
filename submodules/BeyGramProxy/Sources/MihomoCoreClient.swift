import Foundation

/// Why a call to the core failed. `refused` carries the core's own message, which the user sees.
public enum MihomoCoreError: Error, Equatable {
    case notLinked
    case refused(String)
    case malformedReply
}

extension MihomoCoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notLinked:
            return "Ядро Mihomo не подключено в этой сборке."
        case let .refused(message):
            return message
        case .malformedReply:
            return "Ядро вернуло ответ, который не удалось разобрать."
        }
    }
}

/// Runs one JSON action of the core. The caller must not run two actions at once.
public protocol MihomoCoreDriver: AnyObject {
    /// Runs one action and returns the `data` of the reply. Throws `MihomoCoreError.refused` when the core refuses.
    func call(_ method: String, data: [String: Any]) throws -> Any?
}

/// The driver used until the c-archive is linked into the app. Every action fails with `notLinked`.
public final class UnlinkedMihomoCoreDriver: MihomoCoreDriver {
    public init() {}

    public func call(_ method: String, data: [String: Any]) throws -> Any? {
        throw MihomoCoreError.notLinked
    }
}

/// A normalized subscription. `yaml` is the profile the core runs.
public struct MihomoProfile: Equatable {
    public let yaml: String
    public let serverNames: [String]
    public let skipped: Int

    public init(yaml: String, serverNames: [String], skipped: Int) {
        self.yaml = yaml
        self.serverNames = serverNames
        self.skipped = skipped
    }
}

/// One node of the selectable group. `delay` is in milliseconds, or -1 when unknown or failed.
public struct MihomoNode: Equatable {
    public let name: String
    public let type: String
    public let delay: Int

    public init(name: String, type: String, delay: Int) {
        self.name = name
        self.type = type
        self.delay = delay
    }
}

/// The selectable group: the node in use and the nodes it can use.
public struct MihomoGroupState: Equatable {
    public let now: String
    public let nodes: [MihomoNode]

    public init(now: String, nodes: [MihomoNode]) {
        self.now = now
        self.nodes = nodes
    }
}

/// Typed calls over the JSON actions of the core (see core/bridge/bridge.go).
public final class MihomoCoreClient {
    private let driver: MihomoCoreDriver

    public init(driver: MihomoCoreDriver) {
        self.driver = driver
    }

    public func initialize(homeDirectory: String) throws {
        _ = try driver.call("init", data: ["home-dir": homeDirectory])
    }

    public func normalize(source: String, credentials: LoopbackCredentials) throws -> MihomoProfile {
        let reply = try driver.call("normalize", data: [
            "source": source,
            "username": credentials.username,
            "password": credentials.password
        ])
        guard let object = reply as? [String: Any], let yaml = object["yaml"] as? String else {
            throw MihomoCoreError.malformedReply
        }
        let serverNames = ((object["servers"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        let skipped = (object["skipped"] as? Int) ?? 0
        return MihomoProfile(yaml: yaml, serverNames: serverNames, skipped: skipped)
    }

    public func setup(config: String, selected: [String: String]) throws {
        _ = try driver.call("setup", data: ["config": config, "selected": selected])
    }

    public func stop() throws {
        _ = try driver.call("stop", data: [:])
    }

    public func proxies(group: String) throws -> MihomoGroupState {
        let reply = try driver.call("proxies", data: ["group": group])
        guard let object = reply as? [String: Any], let now = object["now"] as? String else {
            throw MihomoCoreError.malformedReply
        }
        let nodes = ((object["nodes"] as? [[String: Any]]) ?? []).compactMap { item -> MihomoNode? in
            guard let name = item["name"] as? String else {
                return nil
            }
            return MihomoNode(name: name, type: (item["type"] as? String) ?? "", delay: (item["delay"] as? Int) ?? -1)
        }
        return MihomoGroupState(now: now, nodes: nodes)
    }

    public func select(group: String, proxy: String) throws {
        _ = try driver.call("select", data: ["group": group, "proxy": proxy])
    }

    /// Returns the delay in milliseconds, or -1 when the node did not answer.
    public func testDelay(proxy: String, timeoutMilliseconds: Int) throws -> Int {
        let reply = try driver.call("testDelay", data: ["proxy-name": proxy, "timeout": timeoutMilliseconds])
        let object = reply as? [String: Any]
        return (object?["delay"] as? Int) ?? -1
    }
}
