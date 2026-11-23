import Foundation

/// The BeyGram colour presets (issue #149), the same values as Android `ui/theme/Color.kt` and `ThemePresets.kt`.
/// Pure data with no UIKit, so it can be checked by reading and tested without a device. Applying it to Telegram's
/// `PresentationTheme` is the UI step and is not done here.
public enum BeyGramThemePreset: String, CaseIterable, Sendable {
    case warm
    case graphite
}

public enum BeyGramThemeBrightness: Sendable {
    case light
    case dark
}

/// The colour roles of one preset in one brightness. Values are 0xAARRGGBB.
public struct BeyGramPresetTokens: Equatable, Sendable {
    public let bg: UInt32
    public let surface: UInt32
    public let surface2: UInt32
    public let line: UInt32
    public let text: UInt32
    public let muted: UInt32
    public let accent: UInt32
    public let accentSoft: UInt32
    public let accentInk: UInt32
    public let onAccent: UInt32
    public let bubbleOut: UInt32
    public let ok: UInt32
    public let okInk: UInt32
    public let warn: UInt32
    public let warnInk: UInt32
    public let danger: UInt32

    /// The AMOLED variant: the greys become black, so the theme stays dark whatever the system says (Android `toAmoled`).
    public var amoled: BeyGramPresetTokens {
        return BeyGramPresetTokens(
            bg: 0xFF000000,
            surface: 0xFF121214,
            surface2: 0xFF1C1C20,
            line: 0xFF26262B,
            text: self.text,
            muted: self.muted,
            accent: self.accent,
            accentSoft: self.accentSoft,
            accentInk: self.accentInk,
            onAccent: self.onAccent,
            bubbleOut: self.bubbleOut,
            ok: self.ok,
            okInk: self.okInk,
            warn: self.warn,
            warnInk: self.warnInk,
            danger: self.danger
        )
    }
}

public enum BeyGramPresetCatalog {
    public static func tokens(for preset: BeyGramThemePreset, brightness: BeyGramThemeBrightness) -> BeyGramPresetTokens {
        switch (preset, brightness) {
        case (.warm, .light):
            return BeyGramPresetTokens(
                bg: 0xFFFAF8F5, surface: 0xFFFFFFFF, surface2: 0xFFF3EFEA, line: 0xFFECE7E0,
                text: 0xFF1E1B18, muted: 0xFF67625B,
                accent: 0xFF6A4FDC, accentSoft: 0xFFEEE9FE, accentInk: 0xFF4B33B5, onAccent: 0xFFFFFFFF,
                bubbleOut: 0xFFE6DEFD,
                ok: 0xFFDDF5EC, okInk: 0xFF0F6B57, warn: 0xFFFFF1D6, warnInk: 0xFF7A4B00,
                danger: 0xFFB42318
            )
        case (.warm, .dark):
            return BeyGramPresetTokens(
                bg: 0xFF161417, surface: 0xFF1F1C21, surface2: 0xFF2A262C, line: 0xFF2E2A30,
                text: 0xFFF3EFEA, muted: 0xFFA39C95,
                accent: 0xFFA894FF, accentSoft: 0xFF2D2750, accentInk: 0xFFCFC4FF, onAccent: 0xFF16131F,
                bubbleOut: 0xFF2E2952,
                ok: 0xFF15332B, okInk: 0xFF8BE0CF, warn: 0xFF3A2D16, warnInk: 0xFFFFD28A,
                danger: 0xFFF97066
            )
        case (.graphite, .light):
            return BeyGramPresetTokens(
                bg: 0xFFF5F6F8, surface: 0xFFFFFFFF, surface2: 0xFFECEEF2, line: 0xFFDFE2E8,
                text: 0xFF1B1D22, muted: 0xFF596170,
                accent: 0xFF3B5BDB, accentSoft: 0xFFE3E9FB, accentInk: 0xFF2B45A8, onAccent: 0xFFFFFFFF,
                bubbleOut: 0xFFDCE4F8,
                ok: 0xFFDDF3EA, okInk: 0xFF0F6B57, warn: 0xFFFFF1D6, warnInk: 0xFF7A4B00,
                danger: 0xFFB42318
            )
        case (.graphite, .dark):
            return BeyGramPresetTokens(
                bg: 0xFF16181C, surface: 0xFF1F2227, surface2: 0xFF2A2E35, line: 0xFF2C3038,
                text: 0xFFEEF0F3, muted: 0xFF9AA1AC,
                accent: 0xFF8FA6FF, accentSoft: 0xFF26305A, accentInk: 0xFFC5D1FF, onAccent: 0xFF111527,
                bubbleOut: 0xFF2A3360,
                ok: 0xFF15332B, okInk: 0xFF8BE0CF, warn: 0xFF3A2D16, warnInk: 0xFFFFD28A,
                danger: 0xFFF97066
            )
        }
    }
}
