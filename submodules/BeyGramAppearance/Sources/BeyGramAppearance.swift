import Foundation
import SwiftSignalKit

/// The BeyGram visual style axis. It is independent of the Telegram colour theme: colours always come from the
/// active PresentationTheme, and this module only supplies the geometry and the glass choice on top of it.
public enum BeyGramStyle: Int32 {
    /// The upstream Telegram look, unchanged.
    case telegram = 0
    /// BeyGram geometry on the Liquid Glass chrome (the Liquid Glass column of BeyGram's design-system-v2).
    case beygram = 1
}

/// Holds the chosen BeyGram style. Reads are thread-safe, so layout code on any queue can ask for the style.
/// The choice is stored in UserDefaults: it is app-wide and does not depend on the account.
public final class BeyGramAppearance {
    public static let shared = BeyGramAppearance()

    private static let userDefaultsKey = "BeyGram.Appearance.Style"

    private let styleValue: Atomic<BeyGramStyle>
    private let stylePromise: ValuePromise<BeyGramStyle>

    private init() {
        let storedRawValue = Int32(UserDefaults.standard.integer(forKey: BeyGramAppearance.userDefaultsKey))
        let stored = BeyGramStyle(rawValue: storedRawValue) ?? .telegram
        self.styleValue = Atomic(value: stored)
        self.stylePromise = ValuePromise(stored, ignoreRepeated: true)
    }

    /// The current style. Safe to read from any thread.
    public var style: BeyGramStyle {
        return self.styleValue.with { $0 }
    }

    /// Whether the BeyGram geometry applies.
    public var isEnabled: Bool {
        return self.style == .beygram
    }

    /// Emits the current style at once and then every change. Presentation data is rebuilt from it.
    public var styleSignal: Signal<BeyGramStyle, NoError> {
        return self.stylePromise.get()
    }

    /// Stores a new style and notifies the observers. Setting the style that is already chosen does nothing.
    public func setStyle(_ style: BeyGramStyle) {
        let previous = self.styleValue.swap(style)
        guard previous != style else {
            return
        }
        UserDefaults.standard.set(Int(style.rawValue), forKey: BeyGramAppearance.userDefaultsKey)
        self.stylePromise.set(style)
    }

    /// Main and auxiliary bubble radii. BeyGram uses 20/8 (the Liquid Glass bubble). A user who changed the bubble
    /// radius in the bubble settings keeps the value they chose, so only the Telegram default 16/8 is replaced.
    public func bubbleCorners(mainRadius: CGFloat, auxiliaryRadius: CGFloat) -> (main: CGFloat, auxiliary: CGFloat) {
        guard self.isEnabled, mainRadius == 16.0, auxiliaryRadius == 8.0 else {
            return (mainRadius, auxiliaryRadius)
        }
        return (20.0, 8.0)
    }

    /// Corner radius of the composer's glass field. BeyGram uses 24pt, which the glass clamps to half the height
    /// of a one-line field, so the radius only shows once the field grows into several lines.
    public func composerCornerRadius(defaultRadius: CGFloat) -> CGFloat {
        return self.isEnabled ? 24.0 : defaultRadius
    }

    private static let navigationVariantKey = "BeyGram.Appearance.NavigationVariant"

    /// Which of the five bottom-bar styles (Android `NavigationSpec`) the BeyGram style uses. Read at layout time.
    public var navigationVariant: BeyGramNavigationVariant {
        get {
            let raw = UserDefaults.standard.string(forKey: BeyGramAppearance.navigationVariantKey) ?? ""
            return BeyGramNavigationVariant(rawValue: raw) ?? .floatingGlass
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: BeyGramAppearance.navigationVariantKey)
        }
    }

    /// The spec of the bottom bar, or nil when the Telegram style is on (its bar is never changed).
    public var navigationSpec: BeyGramNavigationSpec? {
        guard self.isEnabled else {
            return nil
        }
        return BeyGramNavigationCatalog.spec(for: self.navigationVariant)
    }

    /// The largest avatar diameter in the chat list. BeyGram uses 54pt, Telegram keeps 60pt.
    public var chatListAvatarMaxDiameter: CGFloat {
        return self.isEnabled ? 54.0 : 60.0
    }
}
