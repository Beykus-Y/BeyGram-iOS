import SwiftUI

/// Matching token subset from Android ui/theme/Color.kt (Warm preset).
/// The views below avoid native List styling so BeyGram feels like one product.
struct BeyGramChatColors {
    let screen: Color
    let surface: Color
    let surface2: Color
    let divider: Color
    let primary: Color
    let secondary: Color
    let accent: Color
    let accentSoft: Color
    let accentInk: Color
    let outgoingBubble: Color
    let onAccent: Color

    static func warm(_ scheme: ColorScheme) -> Self {
        if scheme == .dark {
            return Self(
                screen: Color(red: 22/255, green: 20/255, blue: 23/255),
                surface: Color(red: 31/255, green: 28/255, blue: 33/255),
                surface2: Color(red: 42/255, green: 38/255, blue: 44/255),
                divider: Color(red: 46/255, green: 42/255, blue: 48/255),
                primary: Color(red: 243/255, green: 239/255, blue: 234/255),
                secondary: Color(red: 163/255, green: 156/255, blue: 149/255),
                accent: Color(red: 168/255, green: 148/255, blue: 255/255),
                accentSoft: Color(red: 45/255, green: 39/255, blue: 80/255),
                accentInk: Color(red: 207/255, green: 196/255, blue: 255/255),
                outgoingBubble: Color(red: 46/255, green: 41/255, blue: 82/255),
                onAccent: Color(red: 22/255, green: 19/255, blue: 31/255)
            )
        }
        return Self(
            screen: Color(red: 250/255, green: 248/255, blue: 245/255),
            surface: .white,
            surface2: Color(red: 243/255, green: 239/255, blue: 234/255),
            divider: Color(red: 236/255, green: 231/255, blue: 224/255),
            primary: Color(red: 30/255, green: 27/255, blue: 24/255),
            secondary: Color(red: 103/255, green: 98/255, blue: 91/255),
            accent: Color(red: 106/255, green: 79/255, blue: 220/255),
            accentSoft: Color(red: 238/255, green: 233/255, blue: 254/255),
            accentInk: Color(red: 75/255, green: 51/255, blue: 181/255),
            outgoingBubble: Color(red: 230/255, green: 222/255, blue: 253/255),
            onAccent: .white
        )
    }
}

/// Reuses the Android avatar palette rather than random colors every redraw.
enum BeyGramAvatarStyle {
    static let palette: [Color] = [
        Color(red: 194/255, green: 89/255, blue: 63/255),
        Color(red: 91/255, green: 75/255, blue: 196/255),
        Color(red: 47/255, green: 138/255, blue: 123/255),
        Color(red: 169/255, green: 115/255, blue: 29/255),
        Color(red: 58/255, green: 120/255, blue: 194/255),
        Color(red: 176/255, green: 71/255, blue: 110/255)
    ]

    static func color(for chatID: Int64) -> Color {
        let index = Int(chatID.magnitude % UInt64(palette.count))
        return palette[index]
    }
}
