import XCTest
@testable import Hashlight

nonisolated final class PreviewThemeTests: XCTestCase {
    @MainActor
    func testBundledCatalogLoadsEveryPinnedBase16Theme() {
        let themes = PreviewThemeCatalog.all

        XCTAssertEqual(themes.count, 351)
        XCTAssertEqual(Set(themes.map(\.id)).count, themes.count)
        XCTAssertEqual(themes.filter(\.isDark).count, 249)
        XCTAssertEqual(themes.filter { !$0.isDark }.count, 102)
    }

    @MainActor
    func testEveryPaletteContainsValidRGBHexColors() {
        let mirrorKeys = Set((0...15).map { String(format: "base%02X", $0) })

        for theme in PreviewThemeCatalog.all {
            let palette = Mirror(reflecting: theme.palette)
            XCTAssertEqual(Set(palette.children.compactMap(\.label)), mirrorKeys, theme.id)

            for color in palette.children {
                guard let hex = color.value as? String else {
                    return XCTFail("\(theme.id).\(color.label ?? "unknown") is not a string")
                }
                XCTAssertNotNil(
                    hex.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression),
                    "\(theme.id).\(color.label ?? "unknown") is not a six-digit RGB color"
                )
            }
        }
    }

    @MainActor
    func testEffectiveAppearanceSelectsTheMatchingSavedTheme() {
        let light = PreviewThemeCatalog.resolve(
            lightID: "catppuccin-latte",
            darkID: "catppuccin-mocha",
            colorScheme: .light
        )
        let dark = PreviewThemeCatalog.resolve(
            lightID: "catppuccin-latte",
            darkID: "catppuccin-mocha",
            colorScheme: .dark
        )

        XCTAssertEqual(light.id, "catppuccin-latte")
        XCTAssertFalse(light.isDark)
        XCTAssertEqual(dark.id, "catppuccin-mocha")
        XCTAssertTrue(dark.isDark)
    }

    @MainActor
    func testThemeIDsCannotCrossLightAndDarkMenus() {
        XCTAssertEqual(PreviewThemeCatalog.validatedLightID("catppuccin-mocha"), PreviewThemeCatalog.defaultLightID)
        XCTAssertEqual(PreviewThemeCatalog.validatedDarkID("catppuccin-latte"), PreviewThemeCatalog.defaultDarkID)
    }

    @MainActor
    func testApplicationAppearanceReturnsFromForcedDarkToSystemImmediately() {
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }

        application.appearance = nil
        let systemMatch = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])

        ApplicationAppearance.apply(.dark, to: application)
        XCTAssertEqual(application.appearance?.name, .darkAqua)
        XCTAssertEqual(application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)

        ApplicationAppearance.apply(nil, to: application)
        XCTAssertNil(application.appearance)
        XCTAssertEqual(application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), systemMatch)
    }
}
