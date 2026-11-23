import Foundation
import CoreGraphics

/// Chat list tokens of the five BeyGram styles (issue #146, Android `DesignMainScreen` in `DesignPresets.kt`).
/// Values are in points. NOT CHECKED BY COMPILATION OR ON A DEVICE.
public enum BeyGramSearchFieldKind: Sendable {
    case filled
    case outlined
    case glass
}

public enum BeyGramFolderChipKind: Sendable {
    /// Accent fill (Default).
    case accentFilled
    /// Accent underline, no pill (Material 2).
    case underlined
    /// Outlined, tonal when selected (Material 3).
    case tonalOutlined
    /// Tonal fill (Liquid Glass).
    case tonal
    /// Fill in the text colour with a caption in the background colour (Signature).
    case ink
}

public enum BeyGramArchiveRowKind: Sendable {
    case tonalCard
    case elevatedCard
    case flat
}

public struct BeyGramChatListSpec: Sendable {
    public let titleSize: CGFloat
    public let titleWeight: BeyGramNavigationLabelWeight
    public let titleTracking: CGFloat
    public let searchKind: BeyGramSearchFieldKind
    public let searchHeight: CGFloat?
    public let searchRadius: CGFloat
    public let chipKind: BeyGramFolderChipKind
    public let chipRadius: CGFloat
    public let archiveKind: BeyGramArchiveRowKind
    public let archiveRadius: CGFloat
    public let archiveElevation: CGFloat
    /// Weight of a chat's name in the list.
    public let chatTitleWeight: BeyGramNavigationLabelWeight
    public let unreadBadgeRadius: CGFloat
    /// Signature draws rows as rounded inset tiles.
    public let rowInset: CGFloat
    public let rowRadius: CGFloat
    public let unreadPreviewEmphasis: Bool
}

public enum BeyGramChatListCatalog {
    public static func spec(for style: BeyGramStyle) -> BeyGramChatListSpec? {
        switch style {
        case .telegram:
            return nil
        case .beygramDefault:
            return BeyGramChatListSpec(
                titleSize: 30, titleWeight: .bold, titleTracking: -0.3,
                searchKind: .filled, searchHeight: nil, searchRadius: 24,
                chipKind: .accentFilled, chipRadius: 16,
                archiveKind: .tonalCard, archiveRadius: 14, archiveElevation: 0,
                chatTitleWeight: .semiBold, unreadBadgeRadius: 11,
                rowInset: 0, rowRadius: 0, unreadPreviewEmphasis: false
            )
        case .material2:
            return BeyGramChatListSpec(
                titleSize: 22, titleWeight: .medium, titleTracking: 0,
                searchKind: .outlined, searchHeight: nil, searchRadius: 2,
                chipKind: .underlined, chipRadius: 2,
                archiveKind: .elevatedCard, archiveRadius: 4, archiveElevation: 2,
                chatTitleWeight: .medium, unreadBadgeRadius: 2,
                rowInset: 0, rowRadius: 0, unreadPreviewEmphasis: false
            )
        case .material3:
            return BeyGramChatListSpec(
                titleSize: 24, titleWeight: .normal, titleTracking: 0,
                searchKind: .filled, searchHeight: 56, searchRadius: 28,
                chipKind: .tonalOutlined, chipRadius: 8,
                archiveKind: .tonalCard, archiveRadius: 12, archiveElevation: 0,
                chatTitleWeight: .medium, unreadBadgeRadius: 8,
                rowInset: 0, rowRadius: 0, unreadPreviewEmphasis: false
            )
        case .liquidGlass, .legacyBeyGram:
            return BeyGramChatListSpec(
                titleSize: 26, titleWeight: .semiBold, titleTracking: -0.2,
                searchKind: .glass, searchHeight: 44, searchRadius: 20,
                chipKind: .tonal, chipRadius: 14,
                archiveKind: .tonalCard, archiveRadius: 14, archiveElevation: 0,
                chatTitleWeight: .semiBold, unreadBadgeRadius: 11,
                rowInset: 0, rowRadius: 0, unreadPreviewEmphasis: false
            )
        case .signature:
            return BeyGramChatListSpec(
                titleSize: 32, titleWeight: .bold, titleTracking: -0.6,
                searchKind: .filled, searchHeight: nil, searchRadius: 14,
                chipKind: .ink, chipRadius: 12,
                archiveKind: .flat, archiveRadius: 0, archiveElevation: 0,
                chatTitleWeight: .bold, unreadBadgeRadius: 10,
                rowInset: 8, rowRadius: 16, unreadPreviewEmphasis: true
            )
        }
    }
}

extension BeyGramAppearance {
    /// The chat list tokens of the current style, nil in Telegram Original.
    public var chatListSpec: BeyGramChatListSpec? {
        return BeyGramChatListCatalog.spec(for: self.style)
    }
}
