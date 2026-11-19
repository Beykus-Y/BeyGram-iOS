import Foundation

/// BeyGram feature switches. Every BeyGram feature is off until it is switched on, so unfinished
/// code paths cannot change the app's behavior. Logic only: the app supplies the storage.
public enum BeyGramFeature: String, CaseIterable {
    case triggerWords
    case chatExport
    case diagnosticsReport
    case appUpdates
}

public protocol BeyGramFlagStorage: AnyObject {
    func bool(forKey key: String) -> Bool?
    func set(_ value: Bool, forKey key: String)
}

public final class BeyGramFeatureFlags {
    private static let keyPrefix = "beygram.feature."
    private let storage: BeyGramFlagStorage

    public init(storage: BeyGramFlagStorage) {
        self.storage = storage
    }

    /// Returns false for every feature that was never switched on.
    public func isEnabled(_ feature: BeyGramFeature) -> Bool {
        storage.bool(forKey: Self.keyPrefix + feature.rawValue) ?? false
    }

    public func setEnabled(_ feature: BeyGramFeature, _ enabled: Bool) {
        storage.set(enabled, forKey: Self.keyPrefix + feature.rawValue)
    }
}
