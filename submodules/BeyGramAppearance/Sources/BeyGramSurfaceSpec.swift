import Foundation
import CoreGraphics

/// Top bar, composer, reply, list-card and sheet tokens of the five BeyGram styles (issues #147 and #148, Android
/// `DesignPresets.kt`, `AppBarSurface.kt`, `StyledControls.kt`). Values are in points.
/// NOT CHECKED BY COMPILATION OR ON A DEVICE.
public enum BeyGramTopBarKind: Sendable {
    case flat
    case elevated
    case glass
    case signature
}

public enum BeyGramComposerKind: Sendable {
    case filled
    case outlined
    case glass
    case signature
}

public struct BeyGramSurfaceSpec: Sendable {
    public let topBar: BeyGramTopBarKind
    /// Real shadow of an elevated bar (Material 2).
    public let barElevation: CGFloat
    public let composer: BeyGramComposerKind
    public let composerRadius: CGFloat
    public let squareSendButton: Bool
    public let replyRadius: CGFloat?
    /// Corner radius of grouped list cards.
    public let groupCardRadius: CGFloat
    public let cardElevation: CGFloat
    /// Radius of the card's first and last corners kept square-ish (Material 2 `cornerCap`).
    public let cornerCap: CGFloat?
    public let sectionLabelUppercase: Bool
    public let sectionLabelTracking: CGFloat
    public let sheetRadius: CGFloat
    public let sheetShadow: CGFloat
    public let dialogRadius: CGFloat
}

public enum BeyGramSurfaceCatalog {
    public static func spec(for style: BeyGramStyle) -> BeyGramSurfaceSpec? {
        switch style {
        case .telegram:
            return nil
        case .beygramDefault:
            return BeyGramSurfaceSpec(
                topBar: .flat, barElevation: 0, composer: .filled, composerRadius: 24, squareSendButton: false,
                replyRadius: nil, groupCardRadius: 20, cardElevation: 0, cornerCap: nil,
                sectionLabelUppercase: false, sectionLabelTracking: 0,
                sheetRadius: 24, sheetShadow: 0, dialogRadius: 24
            )
        case .material2:
            return BeyGramSurfaceSpec(
                topBar: .elevated, barElevation: 4, composer: .outlined, composerRadius: 4, squareSendButton: true,
                replyRadius: 4, groupCardRadius: 4, cardElevation: 2, cornerCap: 4,
                sectionLabelUppercase: true, sectionLabelTracking: 0.6,
                sheetRadius: 0, sheetShadow: 16, dialogRadius: 4
            )
        case .material3:
            return BeyGramSurfaceSpec(
                topBar: .flat, barElevation: 0, composer: .filled, composerRadius: 24, squareSendButton: false,
                replyRadius: 12, groupCardRadius: 12, cardElevation: 0, cornerCap: nil,
                sectionLabelUppercase: false, sectionLabelTracking: 0,
                sheetRadius: 28, sheetShadow: 0, dialogRadius: 28
            )
        case .liquidGlass, .legacyBeyGram:
            return BeyGramSurfaceSpec(
                topBar: .glass, barElevation: 0, composer: .glass, composerRadius: 24, squareSendButton: false,
                replyRadius: 14, groupCardRadius: 24, cardElevation: 0, cornerCap: nil,
                sectionLabelUppercase: false, sectionLabelTracking: 0,
                sheetRadius: 28, sheetShadow: 0, dialogRadius: 28
            )
        case .signature:
            return BeyGramSurfaceSpec(
                topBar: .signature, barElevation: 0, composer: .signature, composerRadius: 22, squareSendButton: false,
                replyRadius: 12, groupCardRadius: 18, cardElevation: 0, cornerCap: nil,
                sectionLabelUppercase: true, sectionLabelTracking: 0.8,
                sheetRadius: 26, sheetShadow: 8, dialogRadius: 22
            )
        }
    }
}

extension BeyGramAppearance {
    /// The surface tokens of the current style, nil in Telegram Original.
    public var surfaceSpec: BeyGramSurfaceSpec? {
        return BeyGramSurfaceCatalog.spec(for: self.style)
    }
}
