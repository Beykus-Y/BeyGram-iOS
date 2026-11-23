import Foundation
import CoreGraphics
import SwiftSignalKit

/// The BeyGram visual style axis. Independent of the Telegram colour theme: colours always come from the
/// active `PresentationTheme`, and this module supplies the geometry, surface treatment, and motion tokens.
public enum BeyGramStyle: Int32, CaseIterable {
    /// Unmodified official Telegram iOS UI (non-invasive bypass).
    case telegram = 0
    /// Original BeyGram Android design (`DesignStyle.Default`).
    case beygramDefault = 1
    /// Classic Material Design (`DesignStyle.Material2`).
    case material2 = 2
    /// Material 3 / Material You (`DesignStyle.Material3`).
    case material3 = 3
    /// Translucent floating glass (`DesignStyle.LiquidGlass`).
    case liquidGlass = 4
    /// BeyGram Signature "ink and mark" (`DesignStyle.Signature`).
    case signature = 5
}

/// Glass rendering budget for `BeyGramStyle.liquidGlass`. Preserved across style switches.
public enum BeyGramGlassQuality: Int32, CaseIterable {
    case auto = 0
    case high = 1
    case balanced = 2
    case lite = 3
}

/// Whether bottom navigation is pinned or floats above content. Preserved across style switches.
public enum BeyGramNavigationPlacement: Int32, CaseIterable {
    case auto = 0
    case pinned = 1
    case floating = 2
}

/// How a style builds surfaces, matching Android's `SurfaceTreatment` plus `.original` for Telegram.
public enum BeyGramSurfaceTreatment: Equatable {
    case original
    case flat
    case elevated
    case tonal
    case glass
    case layered
}

/// Unified design tokens resolved from `BeyGramStyle`, `BeyGramGlassQuality`, `BeyGramNavigationPlacement`,
/// and system accessibility flags (`reduceTransparency`, `reduceMotion`).
public struct BeyGramResolvedDesign: Equatable {
    public let style: BeyGramStyle
    public let treatment: BeyGramSurfaceTreatment
    public let effectiveGlassQuality: BeyGramGlassQuality
    public let glassBlurEnabled: Bool
    public let floatingNavigation: Bool

    // Shapes (pt)
    public let cardCornerRadius: CGFloat
    public let groupCardCornerRadius: CGFloat
    public let buttonCornerRadius: CGFloat
    public let chipCornerRadius: CGFloat
    public let searchCornerRadius: CGFloat
    public let composerCornerRadius: CGFloat
    public let badgeCornerRadius: CGFloat
    public let bubbleMainRadius: CGFloat
    public let bubbleAuxiliaryRadius: CGFloat

    // Spacing & List Geometry (pt)
    public let screenPadding: CGFloat
    public let sectionGap: CGFloat
    public let listRowMinHeight: CGFloat
    public let chatListAvatarMaxDiameter: CGFloat

    // Elevation, Borders & Dividers
    public let cardElevation: CGFloat
    public let barElevation: CGFloat
    public let tintAlpha: CGFloat
    public let surfaceAlpha: CGFloat
    public let showListDividers: Bool
    public let squareSendButton: Bool

    // Typography & Motion
    public let titleFontSize: CGFloat
    public let sectionLabelUppercase: Bool
    public let motionSpeedScale: CGFloat

    public var isBeyGramActive: Bool {
        return self.style != .telegram
    }

    public static func resolve(
        style: BeyGramStyle,
        glassQuality: BeyGramGlassQuality = .auto,
        navigationPlacement: NavigationPlacementArg = .auto,
        reduceTransparency: Bool = false,
        reduceMotion: Bool = false
    ) -> BeyGramResolvedDesign {
        let resolvedGlass: BeyGramGlassQuality
        if reduceTransparency {
            resolvedGlass = .lite
        } else {
            switch glassQuality {
            case .auto:
                resolvedGlass = .high
            case .high, .balanced, .lite:
                resolvedGlass = glassQuality
            }
        }

        let defaultFloating = (style == .liquidGlass)
        let floatingNav: Bool
        switch navigationPlacement {
        case .auto:
            floatingNav = defaultFloating
        case .pinned:
            floatingNav = false
        case .floating:
            floatingNav = true
        }

        let speedScale: CGFloat
        if reduceMotion {
            speedScale = 0.0
        } else {
            switch style {
            case .telegram, .beygramDefault, .material2:
                speedScale = 1.0
            case .material3:
                speedScale = 0.95
            case .liquidGlass, .signature:
                speedScale = 0.9
            }
        }

        switch style {
        case .telegram:
            return BeyGramResolvedDesign(
                style: .telegram,
                treatment: .original,
                effectiveGlassQuality: resolvedGlass,
                glassBlurEnabled: false,
                floatingNavigation: false,
                cardCornerRadius: 16.0,
                groupCardCornerRadius: 16.0,
                buttonCornerRadius: 12.0,
                chipCornerRadius: 14.0,
                searchCornerRadius: 10.0,
                composerCornerRadius: 18.0,
                badgeCornerRadius: 11.0,
                bubbleMainRadius: 16.0,
                bubbleAuxiliaryRadius: 8.0,
                screenPadding: 16.0,
                sectionGap: 16.0,
                listRowMinHeight: 64.0,
                chatListAvatarMaxDiameter: 60.0,
                cardElevation: 0.0,
                barElevation: 0.0,
                tintAlpha: 0.0,
                surfaceAlpha: 1.0,
                showListDividers: true,
                squareSendButton: false,
                titleFontSize: 17.0,
                sectionLabelUppercase: true,
                motionSpeedScale: speedScale
            )
        case .beygramDefault:
            return BeyGramResolvedDesign(
                style: .beygramDefault,
                treatment: .flat,
                effectiveGlassQuality: resolvedGlass,
                glassBlurEnabled: false,
                floatingNavigation: floatingNav,
                cardCornerRadius: 20.0,
                groupCardCornerRadius: 20.0,
                buttonCornerRadius: 16.0,
                chipCornerRadius: 12.0,
                searchCornerRadius: 24.0,
                composerCornerRadius: 20.0,
                badgeCornerRadius: 11.0,
                bubbleMainRadius: 16.0,
                bubbleAuxiliaryRadius: 8.0,
                screenPadding: 16.0,
                sectionGap: 18.0,
                listRowMinHeight: 64.0,
                chatListAvatarMaxDiameter: 54.0,
                cardElevation: 0.0,
                barElevation: 0.0,
                tintAlpha: 0.0,
                surfaceAlpha: 1.0,
                showListDividers: false,
                squareSendButton: false,
                titleFontSize: 30.0,
                sectionLabelUppercase: false,
                motionSpeedScale: speedScale
            )
        case .material2:
            return BeyGramResolvedDesign(
                style: .material2,
                treatment: .elevated,
                effectiveGlassQuality: resolvedGlass,
                glassBlurEnabled: false,
                floatingNavigation: floatingNav,
                cardCornerRadius: 4.0,
                groupCardCornerRadius: 4.0,
                buttonCornerRadius: 4.0,
                chipCornerRadius: 2.0,
                searchCornerRadius: 2.0,
                composerCornerRadius: 4.0,
                badgeCornerRadius: 11.0,
                bubbleMainRadius: 6.0,
                bubbleAuxiliaryRadius: 2.0,
                screenPadding: 16.0,
                sectionGap: 16.0,
                listRowMinHeight: 64.0,
                chatListAvatarMaxDiameter: 48.0,
                cardElevation: 2.0,
                barElevation: 4.0,
                tintAlpha: 0.0,
                surfaceAlpha: 1.0,
                showListDividers: true,
                squareSendButton: true,
                titleFontSize: 22.0,
                sectionLabelUppercase: true,
                motionSpeedScale: speedScale
            )
        case .material3:
            return BeyGramResolvedDesign(
                style: .material3,
                treatment: .tonal,
                effectiveGlassQuality: resolvedGlass,
                glassBlurEnabled: false,
                floatingNavigation: floatingNav,
                cardCornerRadius: 12.0,
                groupCardCornerRadius: 12.0,
                buttonCornerRadius: 20.0,
                chipCornerRadius: 8.0,
                searchCornerRadius: 28.0,
                composerCornerRadius: 20.0,
                badgeCornerRadius: 11.0,
                bubbleMainRadius: 18.0,
                bubbleAuxiliaryRadius: 4.0,
                screenPadding: 16.0,
                sectionGap: 20.0,
                listRowMinHeight: 72.0,
                chatListAvatarMaxDiameter: 52.0,
                cardElevation: 0.0,
                barElevation: 0.0,
                tintAlpha: 0.14,
                surfaceAlpha: 1.0,
                showListDividers: false,
                squareSendButton: false,
                titleFontSize: 24.0,
                sectionLabelUppercase: false,
                motionSpeedScale: speedScale
            )
        case .liquidGlass:
            let blur = (resolvedGlass == .high)
            let glassTint: CGFloat = resolvedGlass == .high ? 0.48 : (resolvedGlass == .balanced ? 0.76 : 0.96)
            let glassAlpha: CGFloat = resolvedGlass == .high ? 0.86 : (resolvedGlass == .balanced ? 0.80 : 1.0)
            return BeyGramResolvedDesign(
                style: .liquidGlass,
                treatment: .glass,
                effectiveGlassQuality: resolvedGlass,
                glassBlurEnabled: blur,
                floatingNavigation: floatingNav,
                cardCornerRadius: 24.0,
                groupCardCornerRadius: 24.0,
                buttonCornerRadius: 22.0,
                chipCornerRadius: 14.0,
                searchCornerRadius: 20.0,
                composerCornerRadius: 24.0,
                badgeCornerRadius: 11.0,
                bubbleMainRadius: 20.0,
                bubbleAuxiliaryRadius: 8.0,
                screenPadding: 16.0,
                sectionGap: 20.0,
                listRowMinHeight: 68.0,
                chatListAvatarMaxDiameter: 54.0,
                cardElevation: 0.0,
                barElevation: 0.0,
                tintAlpha: glassTint,
                surfaceAlpha: glassAlpha,
                showListDividers: false,
                squareSendButton: false,
                titleFontSize: 26.0,
                sectionLabelUppercase: false,
                motionSpeedScale: speedScale
            )
        case .signature:
            return BeyGramResolvedDesign(
                style: .signature,
                treatment: .layered,
                effectiveGlassQuality: resolvedGlass,
                glassBlurEnabled: false,
                floatingNavigation: floatingNav,
                cardCornerRadius: 16.0,
                groupCardCornerRadius: 18.0,
                buttonCornerRadius: 14.0,
                chipCornerRadius: 12.0,
                searchCornerRadius: 14.0,
                composerCornerRadius: 22.0,
                badgeCornerRadius: 10.0,
                bubbleMainRadius: 18.0,
                bubbleAuxiliaryRadius: 6.0,
                screenPadding: 14.0,
                sectionGap: 20.0,
                listRowMinHeight: 68.0,
                chatListAvatarMaxDiameter: 56.0,
                cardElevation: 0.0,
                barElevation: 0.0,
                tintAlpha: 0.08,
                surfaceAlpha: 1.0,
                showListDividers: false,
                squareSendButton: false,
                titleFontSize: 32.0,
                sectionLabelUppercase: true,
                motionSpeedScale: speedScale
            )
        }
    }
}

public typealias NavigationPlacementArg = BeyGramNavigationPlacement

/// Holds the chosen BeyGram style, glass quality, and navigation placement.
/// Thread-safe reads; persisted in `UserDefaults`.
public final class BeyGramAppearance {
    public static let shared = BeyGramAppearance()

    static let userDefaultsKey = "BeyGram.Appearance.Style"
    static let schemaVersionKey = "BeyGram.Appearance.StyleSchemaVersion"
    static let glassQualityKey = "BeyGram.Appearance.GlassQuality"
    static let navPlacementKey = "BeyGram.Appearance.NavigationPlacement"
    static let currentSchemaVersion = 2

    private let defaults: UserDefaults
    private let styleValue: Atomic<BeyGramStyle>
    private let stylePromise: ValuePromise<BeyGramStyle>
    private let glassValue: Atomic<BeyGramGlassQuality>
    private let glassPromise: ValuePromise<BeyGramGlassQuality>
    private let navValue: Atomic<BeyGramNavigationPlacement>
    private let navPromise: ValuePromise<BeyGramNavigationPlacement>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedVersion = defaults.integer(forKey: BeyGramAppearance.schemaVersionKey)
        let hasStoredStyle = defaults.object(forKey: BeyGramAppearance.userDefaultsKey) != nil
        var rawStyle = Int32(defaults.integer(forKey: BeyGramAppearance.userDefaultsKey))

        // Explicit v1 -> v2 migration: legacy `1` ("BeyGram", Liquid Glass geometry) becomes `.liquidGlass` (`4`).
        if storedVersion < BeyGramAppearance.currentSchemaVersion {
            if hasStoredStyle && rawStyle == 1 {
                rawStyle = BeyGramStyle.liquidGlass.rawValue
                defaults.set(Int(rawStyle), forKey: BeyGramAppearance.userDefaultsKey)
            }
            defaults.set(BeyGramAppearance.currentSchemaVersion, forKey: BeyGramAppearance.schemaVersionKey)
        }

        let storedStyle = hasStoredStyle ? (BeyGramStyle(rawValue: rawStyle) ?? .telegram) : .telegram
        self.styleValue = Atomic(value: storedStyle)
        self.stylePromise = ValuePromise(storedStyle, ignoreRepeated: true)

        let rawGlass = Int32(defaults.integer(forKey: BeyGramAppearance.glassQualityKey))
        let storedGlass = BeyGramGlassQuality(rawValue: rawGlass) ?? .auto
        self.glassValue = Atomic(value: storedGlass)
        self.glassPromise = ValuePromise(storedGlass, ignoreRepeated: true)

        let rawNav = Int32(defaults.integer(forKey: BeyGramAppearance.navPlacementKey))
        let storedNav = BeyGramNavigationPlacement(rawValue: rawNav) ?? .auto
        self.navValue = Atomic(value: storedNav)
        self.navPromise = ValuePromise(storedNav, ignoreRepeated: true)
    }

    /// The current style. Safe to read from any thread.
    public var style: BeyGramStyle {
        return self.styleValue.with { $0 }
    }

    public var glassQuality: BeyGramGlassQuality {
        return self.glassValue.with { $0 }
    }

    public var navigationPlacement: BeyGramNavigationPlacement {
        return self.navValue.with { $0 }
    }

    /// Whether any BeyGram style (non-Telegram Original) is active.
    public var isEnabled: Bool {
        return self.style != .telegram
    }

    public var styleSignal: Signal<BeyGramStyle, NoError> {
        return self.stylePromise.get()
    }

    public var glassQualitySignal: Signal<BeyGramGlassQuality, NoError> {
        return self.glassPromise.get()
    }

    public var navigationPlacementSignal: Signal<BeyGramNavigationPlacement, NoError> {
        return self.navPromise.get()
    }

    /// Emits whenever any appearance axis changes.
    public var designChangedSignal: Signal<BeyGramStyle, NoError> {
        return combineLatest(self.stylePromise.get(), self.glassPromise.get(), self.navPromise.get())
        |> map { style, _, _ in style }
    }

    public func resolvedDesign(reduceTransparency: Bool = false, reduceMotion: Bool = false) -> BeyGramResolvedDesign {
        return BeyGramResolvedDesign.resolve(
            style: self.style,
            glassQuality: self.glassQuality,
            navigationPlacement: self.navigationPlacement,
            reduceTransparency: reduceTransparency,
            reduceMotion: reduceMotion
        )
    }

    public func setStyle(_ style: BeyGramStyle) {
        let previous = self.styleValue.swap(style)
        guard previous != style else {
            return
        }
        self.defaults.set(Int(style.rawValue), forKey: BeyGramAppearance.userDefaultsKey)
        self.defaults.set(BeyGramAppearance.currentSchemaVersion, forKey: BeyGramAppearance.schemaVersionKey)
        self.stylePromise.set(style)
    }

    public func setGlassQuality(_ quality: BeyGramGlassQuality) {
        let previous = self.glassValue.swap(quality)
        guard previous != quality else {
            return
        }
        self.defaults.set(Int(quality.rawValue), forKey: BeyGramAppearance.glassQualityKey)
        self.glassPromise.set(quality)
    }

    public func setNavigationPlacement(_ placement: BeyGramNavigationPlacement) {
        let previous = self.navValue.swap(placement)
        guard previous != placement else {
            return
        }
        self.defaults.set(Int(placement.rawValue), forKey: BeyGramAppearance.navPlacementKey)
        self.navPromise.set(placement)
    }

    /// Main and auxiliary bubble radii. Preserves user-customized bubble settings (only replaces Telegram default 16/8).
    public func bubbleCorners(mainRadius: CGFloat, auxiliaryRadius: CGFloat) -> (main: CGFloat, auxiliary: CGFloat) {
        let design = self.resolvedDesign()
        guard design.isBeyGramActive, mainRadius == 16.0, auxiliaryRadius == 8.0 else {
            return (mainRadius, auxiliaryRadius)
        }
        return (design.bubbleMainRadius, design.bubbleAuxiliaryRadius)
    }

    /// Corner radius of the composer's field. Telegram Original keeps `defaultRadius`.
    public func composerCornerRadius(defaultRadius: CGFloat) -> CGFloat {
        let design = self.resolvedDesign()
        return design.isBeyGramActive ? design.composerCornerRadius : defaultRadius
    }

    /// Largest avatar diameter in the chat list.
    public var chatListAvatarMaxDiameter: CGFloat {
        return self.resolvedDesign().chatListAvatarMaxDiameter
    }
}
