import Foundation

/// Player equalizer model, value-compatible with Android's `EqualizerController` / `EqualizerStore`:
/// the same presets, anchor frequencies, millibel levels, boost cap, stored range and headroom rule.
/// Pure math and storage format only. The audio node that applies the levels is not part of this file.
public enum BeyGramEqualizerPreset: String, CaseIterable {
    case flat = "Flat"
    case bass = "Bass"
    case vocal = "Vocal"
    case pop = "Pop"
    case rock = "Rock"
    case electronic = "Electronic"
    case classical = "Classical"
    case jazz = "Jazz"
    case custom = "Custom"
}

public struct BeyGramEqualizerSettings: Equatable {
    public var enabled: Bool
    public var selectedPreset: BeyGramEqualizerPreset
    /// Frequency (Hz) to level (millibels), so a curve survives a different band layout.
    public var customLevelsMb: [Int: Int]

    public init(enabled: Bool = false, selectedPreset: BeyGramEqualizerPreset = .flat, customLevelsMb: [Int: Int] = [:]) {
        self.enabled = enabled
        self.selectedPreset = selectedPreset
        self.customLevelsMb = customLevelsMb
    }

    public var hasCustomPreset: Bool {
        return !self.customLevelsMb.isEmpty
    }
}

public enum BeyGramEqualizer {
    /// Anchor frequencies of the preset curves, as on Android.
    public static let presetAnchorFrequenciesHz: [Int] = [31, 63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    /// Positive gain is capped to avoid clipping when several bands boost together.
    public static let maxBoostMb = 600
    /// Bounds of a stored level, wider than any hardware range.
    public static let minStoredLevelMb = -2_400
    public static let maxStoredLevelMb = 2_400

    /// Preset gains in decibels at the anchor frequencies.
    public static func presetCurveDb(_ preset: BeyGramEqualizerPreset) -> [Float] {
        switch preset {
        case .flat, .custom: return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bass: return [6, 5, 3, 1, 0, 0, 0, 0, 0, 0]
        case .vocal: return [-2, -1, 0, 1, 2, 3, 4, 2, 1, 0]
        case .pop: return [-1, 0, 1, 2, 2, 1, 1, 2, 2, 1]
        case .rock: return [4, 3, 2, 1, -1, -1, 0, 1, 2, 3]
        case .electronic: return [5, 4, 2, 0, -1, 1, 2, 3, 4, 4]
        case .classical: return [3, 2, 1, 0, 0, 0, 1, 2, 3, 3]
        case .jazz: return [3, 2, 1, 1, 0, 1, 2, 2, 2, 1]
        }
    }

    /// The preset resolved against the bands of the actual effect, in millibels.
    public static func presetLevelsMb(_ preset: BeyGramEqualizerPreset, frequenciesHz: [Int]) -> [Int] {
        if preset == .custom {
            return [Int](repeating: 0, count: frequenciesHz.count)
        }
        let curve = self.presetCurveDb(preset)
        let anchors = zip(self.presetAnchorFrequenciesHz, curve).map { (frequency: $0, level: $1) }
        return frequenciesHz.map { Int(self.roundHalfUp(self.interpolateLog(anchors, frequencyHz: $0) * 100)) }
    }

    /// A saved custom curve resolved against the bands of the actual effect, in millibels.
    public static func customLevelsMb(frequenciesHz: [Int], custom: [Int: Int]) -> [Int] {
        let points = custom
            .filter { $0.key > 0 && $0.value >= self.minStoredLevelMb && $0.value <= self.maxStoredLevelMb }
            .sorted { $0.key < $1.key }
            .map { (frequency: $0.key, level: Float($0.value)) }
        if points.isEmpty {
            return [Int](repeating: 0, count: frequenciesHz.count)
        }
        return frequenciesHz.map { Int(self.roundHalfUp(self.interpolateLog(points, frequencyHz: $0))) }
    }

    /// Levels for the settings, clamped to `minLevelMb ... maxBoostMb` (and the hardware maximum when lower).
    public static func levels(for settings: BeyGramEqualizerSettings, frequenciesHz: [Int], minLevelMb: Int, hardwareMaxLevelMb: Int) -> [Int] {
        let raw: [Int]
        if settings.selectedPreset == .custom {
            raw = self.customLevelsMb(frequenciesHz: frequenciesHz, custom: settings.customLevelsMb)
        } else {
            raw = self.presetLevelsMb(settings.selectedPreset, frequenciesHz: frequenciesHz)
        }
        let maxLevel = min(hardwareMaxLevelMb, self.maxBoostMb)
        return raw.map { min(max($0, minLevelMb), maxLevel) }
    }

    /// Takes the largest boost off every band, so boosted bands cannot clip. No band goes below `minLevelMb`.
    public static func withHeadroom(_ levelsMb: [Int], minLevelMb: Int) -> [Int] {
        let boost = max(levelsMb.max() ?? 0, 0)
        if boost == 0 {
            return levelsMb
        }
        return levelsMb.map { max($0 - boost, minLevelMb) }
    }

    /// `frequency:level;frequency:level`, sorted by frequency; invalid entries are dropped.
    public static func encodeLevels(_ levelsMb: [Int: Int]) -> String {
        return levelsMb
            .filter { $0.key > 0 && $0.value >= self.minStoredLevelMb && $0.value <= self.maxStoredLevelMb }
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ";")
    }

    public static func decodeLevels(_ encoded: String?) -> [Int: Int] {
        guard let encoded = encoded, !encoded.trimmingCharacters(in: .whitespaces).isEmpty else {
            return [:]
        }
        var result: [Int: Int] = [:]
        for entry in encoded.split(separator: ";", omittingEmptySubsequences: true) {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let frequency = Int(parts[0]), let level = Int(parts[1]) else {
                continue
            }
            if frequency <= 0 || level < self.minStoredLevelMb || level > self.maxStoredLevelMb {
                continue
            }
            result[frequency] = level
        }
        return result
    }

    /// Kotlin's `roundToInt` rounds half up.
    private static func roundHalfUp(_ value: Float) -> Float {
        return (value + 0.5).rounded(.down)
    }

    /// Interpolates in log-frequency space, as Android does.
    private static func interpolateLog(_ points: [(frequency: Int, level: Float)], frequencyHz: Int) -> Float {
        guard let first = points.first, let last = points.last else {
            return 0
        }
        if points.count == 1 {
            return first.level
        }
        let x = log10(Float(max(frequencyHz, 1)))
        if x <= log10(Float(first.frequency)) {
            return first.level
        }
        for index in 0 ..< (points.count - 1) {
            let left = points[index]
            let right = points[index + 1]
            let leftX = log10(Float(left.frequency))
            let rightX = log10(Float(right.frequency))
            if x <= rightX {
                if rightX == leftX {
                    return right.level
                }
                let fraction = (x - leftX) / (rightX - leftX)
                return left.level + (right.level - left.level) * fraction
            }
        }
        return last.level
    }
}
