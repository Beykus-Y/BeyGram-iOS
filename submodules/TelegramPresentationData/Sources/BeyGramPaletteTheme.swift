import Foundation
import UIKit
import Display
import BeyGramAppearance

private func beyGramColor(_ value: UInt32) -> UIColor {
    return UIColor(
        red: CGFloat((value >> 16) & 0xff) / 255.0,
        green: CGFloat((value >> 8) & 0xff) / 255.0,
        blue: CGFloat(value & 0xff) / 255.0,
        alpha: CGFloat((value >> 24) & 0xff) / 255.0
    )
}

private func beyGramMix(_ from: UIColor, _ to: UIColor, _ t: CGFloat) -> UIColor {
    var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
    var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
    from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
    to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
    return UIColor(red: fr + (tr - fr) * t, green: fg + (tg - fg) * t, blue: fb + (tb - fb) * t, alpha: 1.0)
}

public extension PresentationTheme {
    /// The theme with the BeyGram colour preset applied (#149): backgrounds, cards, separators, text and accent of the
    /// lists, the bars and the chat list. Telegram Original, and the "Telegram Theme" palette, return the theme as it is.
    /// The chat wallpaper and the bubble colours stay with the Telegram theme. NOT CHECKED BY COMPILATION.
    func withBeyGramPalette() -> PresentationTheme {
        guard let tokens = BeyGramAppearance.shared.paletteTokens(isDark: self.overallDarkAppearance) else {
            return self
        }
        let bg = beyGramColor(tokens.bg)
        let surface = beyGramColor(tokens.surface)
        let card = beyGramMix(bg, surface, BeyGramAppearance.shared.tonalStep)
        let line = beyGramColor(tokens.line)
        let text = beyGramColor(tokens.text)
        let muted = beyGramColor(tokens.muted)
        let accent = beyGramColor(tokens.accent)

        let list = self.list.withUpdated(
            blocksBackgroundColor: bg,
            plainBackgroundColor: bg,
            itemPrimaryTextColor: text,
            itemSecondaryTextColor: muted,
            itemAccentColor: accent,
            itemBlocksBackgroundColor: card,
            itemHighlightedBackgroundColor: beyGramColor(tokens.surface2),
            itemBlocksSeparatorColor: line,
            itemPlainSeparatorColor: line,
            sectionHeaderTextColor: muted,
            freeTextColor: muted
        )
        let chatList = self.chatList.withUpdated(
            backgroundColor: bg,
            itemSeparatorColor: line,
            itemBackgroundColor: bg
        )
        let rootController = self.rootController.withUpdated(
            tabBar: self.rootController.tabBar.withUpdated(
                backgroundColor: bg,
                separatorColor: line,
                selectedIconColor: accent,
                selectedTextColor: accent
            ),
            navigationBar: self.rootController.navigationBar.withUpdated(
                primaryTextColor: text,
                secondaryTextColor: muted,
                accentTextColor: accent,
                separatorColor: line
            )
        )
        return PresentationTheme(
            name: self.name,
            index: self.index,
            referenceTheme: self.referenceTheme,
            overallDarkAppearance: self.overallDarkAppearance,
            intro: self.intro,
            passcode: self.passcode,
            rootController: rootController,
            list: list,
            chatList: chatList,
            chat: self.chat,
            actionSheet: self.actionSheet,
            contextMenu: self.contextMenu,
            inAppNotification: self.inAppNotification,
            chart: self.chart,
            preview: self.preview
        )
    }
}
