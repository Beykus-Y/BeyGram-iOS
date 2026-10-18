import SwiftUI

enum BeyGramPalette {
    static let accent = Color(red: 106 / 255, green: 79 / 255, blue: 220 / 255)
    static let background = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 22 / 255, green: 20 / 255, blue: 23 / 255, alpha: 1)
                : UIColor(red: 250 / 255, green: 248 / 255, blue: 245 / 255, alpha: 1)
        }
    )
}
