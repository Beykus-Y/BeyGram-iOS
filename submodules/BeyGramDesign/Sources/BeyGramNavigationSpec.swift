import Foundation
import CoreGraphics

/// The five bottom navigation styles of BeyGram (issue #145). Values are the Android `navigationSpecFor` table in
/// `ui/components/MainTabs.kt`, in points (dp = pt). This is the data layer only: the bar's drawing is a later step.
/// NOT CHECKED BY COMPILATION OR ON A DEVICE.
public enum BeyGramNavigationVariant: String, CaseIterable, Sendable {
    case pillTabs
    case classicTabs
    case navigationBar
    case floatingGlass
    case signatureMark
}

public enum BeyGramNavigationLabelWeight: String, Sendable {
    case normal
    case medium
    case semiBold
    case bold
}

public struct BeyGramNavigationSpec: Equatable, Sendable {
    public let pillWidth: CGFloat
    public let pillHeight: CGFloat
    public let pillRadius: CGFloat
    public let showSelectionPill: Bool
    public let showLabels: Bool
    public let labelSize: CGFloat
    public let labelWeight: BeyGramNavigationLabelWeight
    public let iconSize: CGFloat
    public let barTopPadding: CGFloat
    public let barBottomPadding: CGFloat
    /// Shadow of the bar in the ordinary bottom slot.
    public let pinnedElevation: CGFloat
    /// Shadow of the floating capsule.
    public let floatingElevation: CGFloat
    public let divider: Bool
    public let horizontalMargin: CGFloat
    public let bottomMargin: CGFloat
    public let dockRadius: CGFloat
    public let indicatorAlpha: CGFloat
    public let selectedLabelWeight: BeyGramNavigationLabelWeight
    public let selectedLabelOnSurface: Bool
    public let indicatorMark: Bool
    public let markWidth: CGFloat
    public let markHeight: CGFloat
    public let selectedInk: Bool
    public let hairline: Bool
    public let labelSidePadding: CGFloat
}

public enum BeyGramNavigationCatalog {
    /// The spec of a style. `floatingGlassShadow` is the glass surface's own shadow elevation (Android `glass.shadowElevation`, 12 when absent).
    public static func spec(for variant: BeyGramNavigationVariant, floatingGlassShadow: CGFloat = 12) -> BeyGramNavigationSpec {
        switch variant {
        case .pillTabs:
            return BeyGramNavigationSpec(
                pillWidth: 56, pillHeight: 32, pillRadius: 16,
                showSelectionPill: true, showLabels: true, labelSize: 12,
                labelWeight: .normal, iconSize: 24,
                barTopPadding: 10, barBottomPadding: 8, pinnedElevation: 0, floatingElevation: 8,
                divider: false,
                horizontalMargin: 12, bottomMargin: 8, dockRadius: 16, indicatorAlpha: 1,
                selectedLabelWeight: .semiBold, selectedLabelOnSurface: false,
                indicatorMark: false, markWidth: 20, markHeight: 3,
                selectedInk: false, hairline: false, labelSidePadding: 0
            )
        case .classicTabs:
            return BeyGramNavigationSpec(
                pillWidth: 56, pillHeight: 32, pillRadius: 2,
                showSelectionPill: false, showLabels: true, labelSize: 12,
                labelWeight: .medium, iconSize: 24,
                barTopPadding: 8, barBottomPadding: 8, pinnedElevation: 8, floatingElevation: 8,
                divider: true,
                horizontalMargin: 12, bottomMargin: 8, dockRadius: 2, indicatorAlpha: 1,
                selectedLabelWeight: .semiBold, selectedLabelOnSurface: false,
                indicatorMark: false, markWidth: 20, markHeight: 3,
                selectedInk: false, hairline: false, labelSidePadding: 0
            )
        case .navigationBar:
            return BeyGramNavigationSpec(
                pillWidth: 64, pillHeight: 32, pillRadius: 16,
                showSelectionPill: true, showLabels: true, labelSize: 12,
                labelWeight: .medium, iconSize: 24,
                barTopPadding: 12, barBottomPadding: 16, pinnedElevation: 0, floatingElevation: 6,
                divider: false,
                horizontalMargin: 12, bottomMargin: 8, dockRadius: 20, indicatorAlpha: 1,
                selectedLabelWeight: .medium, selectedLabelOnSurface: true,
                indicatorMark: false, markWidth: 20, markHeight: 3,
                selectedInk: false, hairline: false, labelSidePadding: 0
            )
        case .floatingGlass:
            return BeyGramNavigationSpec(
                pillWidth: 58, pillHeight: 30, pillRadius: 20,
                showSelectionPill: true, showLabels: true, labelSize: 11,
                labelWeight: .medium, iconSize: 22,
                barTopPadding: 9, barBottomPadding: 9, pinnedElevation: 0,
                floatingElevation: floatingGlassShadow,
                divider: false,
                horizontalMargin: 16, bottomMargin: 10, dockRadius: 24, indicatorAlpha: 0.82,
                selectedLabelWeight: .semiBold, selectedLabelOnSurface: false,
                indicatorMark: false, markWidth: 20, markHeight: 3,
                selectedInk: false, hairline: false, labelSidePadding: 4
            )
        case .signatureMark:
            return BeyGramNavigationSpec(
                pillWidth: 56, pillHeight: 28, pillRadius: 2,
                showSelectionPill: true, showLabels: true, labelSize: 11,
                labelWeight: .medium, iconSize: 22,
                barTopPadding: 10, barBottomPadding: 9, pinnedElevation: 0, floatingElevation: 3,
                divider: false,
                horizontalMargin: 14, bottomMargin: 9, dockRadius: 20, indicatorAlpha: 1,
                selectedLabelWeight: .bold, selectedLabelOnSurface: false,
                indicatorMark: true, markWidth: 20, markHeight: 3,
                selectedInk: true, hairline: true, labelSidePadding: 0
            )
        }
    }
}
