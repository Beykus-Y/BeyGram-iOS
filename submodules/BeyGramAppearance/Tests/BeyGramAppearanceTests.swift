import XCTest
@testable import BeyGramAppearance

final class BeyGramAppearanceTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "BeyGramAppearanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    func testNewUserDefaultsToTelegramOriginal() {
        let (defaults, suite) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let appearance = BeyGramAppearance(defaults: defaults)
        XCTAssertEqual(appearance.style, .telegram)
        XCTAssertFalse(appearance.isEnabled)
        XCTAssertEqual(appearance.glassQuality, .auto)
        XCTAssertEqual(appearance.navigationPlacement, .auto)
    }

    func testLegacyBeyGramValueOneMigratesToLiquidGlassOnce() {
        let (defaults, suite) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(1, forKey: "BeyGram.Appearance.Style")
        let migrated = BeyGramAppearance(defaults: defaults)
        XCTAssertEqual(migrated.style, .liquidGlass)
        XCTAssertTrue(migrated.isEnabled)
        XCTAssertEqual(defaults.integer(forKey: "BeyGram.Appearance.Style"), Int(BeyGramStyle.liquidGlass.rawValue))
        XCTAssertEqual(defaults.integer(forKey: "BeyGram.Appearance.StyleSchemaVersion"), 2)

        // Switching to beygramDefault (1) after migration must NOT be re-migrated.
        migrated.setStyle(.beygramDefault)
        let reloaded = BeyGramAppearance(defaults: defaults)
        XCTAssertEqual(reloaded.style, .beygramDefault)
    }

    func testUnknownRawValueFallsBackToTelegramOriginal() {
        let (defaults, suite) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(2, forKey: "BeyGram.Appearance.StyleSchemaVersion")
        defaults.set(999, forKey: "BeyGram.Appearance.Style")
        let appearance = BeyGramAppearance(defaults: defaults)
        XCTAssertEqual(appearance.style, .telegram)
    }

    func testAllSixStylesProduceDistinctExpectedTokens() {
        XCTAssertEqual(BeyGramStyle.allCases.count, 6)

        let tg = BeyGramResolvedDesign.resolve(style: .telegram)
        XCTAssertFalse(tg.isBeyGramActive)
        XCTAssertEqual(tg.treatment, .original)
        XCTAssertEqual(tg.chatListAvatarMaxDiameter, 60.0)
        XCTAssertEqual(tg.bubbleMainRadius, 16.0)

        let def = BeyGramResolvedDesign.resolve(style: .beygramDefault)
        XCTAssertTrue(def.isBeyGramActive)
        XCTAssertEqual(def.treatment, .flat)
        XCTAssertEqual(def.composerCornerRadius, 20.0)
        XCTAssertEqual(def.chatListAvatarMaxDiameter, 54.0)

        let m2 = BeyGramResolvedDesign.resolve(style: .material2)
        XCTAssertEqual(m2.treatment, .elevated)
        XCTAssertEqual(m2.cardCornerRadius, 4.0)
        XCTAssertEqual(m2.bubbleMainRadius, 6.0)
        XCTAssertTrue(m2.squareSendButton)
        XCTAssertTrue(m2.showListDividers)

        let m3 = BeyGramResolvedDesign.resolve(style: .material3)
        XCTAssertEqual(m3.treatment, .tonal)
        XCTAssertEqual(m3.buttonCornerRadius, 20.0)
        XCTAssertEqual(m3.listRowMinHeight, 72.0)

        let glass = BeyGramResolvedDesign.resolve(style: .liquidGlass)
        XCTAssertEqual(glass.treatment, .glass)
        XCTAssertTrue(glass.glassBlurEnabled)
        XCTAssertTrue(glass.floatingNavigation)
        XCTAssertEqual(glass.bubbleMainRadius, 20.0)
        XCTAssertEqual(glass.composerCornerRadius, 24.0)

        let sig = BeyGramResolvedDesign.resolve(style: .signature)
        XCTAssertEqual(sig.treatment, .layered)
        XCTAssertFalse(sig.floatingNavigation)
        XCTAssertEqual(sig.titleFontSize, 32.0)
    }

    func testAccessibilityFlagsClampGlassAndMotion() {
        let reduced = BeyGramResolvedDesign.resolve(
            style: .liquidGlass,
            glassQuality: .high,
            navigationPlacement: .pinned,
            reduceTransparency: true,
            reduceMotion: true
        )
        XCTAssertEqual(reduced.effectiveGlassQuality, .lite)
        XCTAssertFalse(reduced.glassBlurEnabled)
        XCTAssertEqual(reduced.surfaceAlpha, 1.0)
        XCTAssertFalse(reduced.floatingNavigation)
        XCTAssertEqual(reduced.motionSpeedScale, 0.0)
    }

    func testCustomBubbleRadiiArePreserved() {
        let (defaults, suite) = self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let appearance = BeyGramAppearance(defaults: defaults)
        appearance.setStyle(.material2)
        // Default 16/8 is replaced by Material 2's 6/2.
        let replaced = appearance.bubbleCorners(mainRadius: 16.0, auxiliaryRadius: 8.0)
        XCTAssertEqual(replaced.main, 6.0)
        XCTAssertEqual(replaced.auxiliary, 2.0)

        // Custom user radius (e.g. 12/4) is preserved.
        let custom = appearance.bubbleCorners(mainRadius: 12.0, auxiliaryRadius: 4.0)
        XCTAssertEqual(custom.main, 12.0)
        XCTAssertEqual(custom.auxiliary, 4.0)
    }
}
