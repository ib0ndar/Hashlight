import XCTest
@testable import Hashlight

nonisolated final class PreviewThemeTests: XCTestCase {
    @MainActor
    func testBundledCatalogLoadsEveryPinnedBase16Theme() {
        let themes = PreviewThemeCatalog.bundled

        XCTAssertEqual(themes.count, 351)
        XCTAssertEqual(Set(themes.map(\.id)).count, themes.count)
        XCTAssertEqual(themes.filter(\.isDark).count, 249)
        XCTAssertEqual(themes.filter { !$0.isDark }.count, 102)
        XCTAssertFalse(themes.contains(where: \.isSystem))
    }

    @MainActor
    func testSystemThemesLeadBothMenus() {
        let all = PreviewThemeCatalog.all
        XCTAssertEqual(all.count, 353)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)

        let light = PreviewThemeCatalog.light
        let dark = PreviewThemeCatalog.dark
        XCTAssertEqual(light.first?.id, PreviewTheme.systemLightID)
        XCTAssertEqual(dark.first?.id, PreviewTheme.systemDarkID)
        XCTAssertEqual(light.first?.name, "System")
        XCTAssertEqual(dark.first?.name, "System")
        XCTAssertEqual(light.first?.isDark, false)
        XCTAssertEqual(dark.first?.isDark, true)
        XCTAssertEqual(light.count, 103)
        XCTAssertEqual(dark.count, 250)

        XCTAssertEqual(PreviewThemeCatalog.validatedLightID(PreviewTheme.systemLightID), PreviewTheme.systemLightID)
        XCTAssertEqual(PreviewThemeCatalog.validatedDarkID(PreviewTheme.systemDarkID), PreviewTheme.systemDarkID)
        XCTAssertEqual(PreviewThemeCatalog.validatedDarkID(PreviewTheme.systemLightID), PreviewThemeCatalog.defaultDarkID)
    }

    @MainActor
    func testSystemPalettesFollowTheResolvedSystemColors() throws {
        func hex(_ color: NSColor, in appearanceName: NSAppearance.Name) throws -> String {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            var result = ""
            appearance.performAsCurrentDrawingAppearance {
                let srgb = color.usingColorSpace(.sRGB)!
                result = String(format: "#%02X%02X%02X",
                                Int((srgb.redComponent * 255).rounded()),
                                Int((srgb.greenComponent * 255).rounded()),
                                Int((srgb.blueComponent * 255).rounded()))
            }
            return result
        }

        let light = PreviewTheme.system(dark: false)
        let dark = PreviewTheme.system(dark: true)

        // Opaque system colors come through exactly; the accent is kept as is in both.
        XCTAssertEqual(light.palette.base00, try hex(.textBackgroundColor, in: .aqua))
        XCTAssertEqual(dark.palette.base00, try hex(.textBackgroundColor, in: .darkAqua))
        XCTAssertEqual(light.palette.base0D, try hex(.controlAccentColor, in: .aqua))
        XCTAssertEqual(dark.palette.base0D, try hex(.controlAccentColor, in: .darkAqua))
        XCTAssertEqual(dark.palette.base08, try hex(.systemRed, in: .darkAqua))
        XCTAssertNotEqual(light.palette.base00, dark.palette.base00)

        // Text is the label color composited over the background: darker than the background in
        // light, lighter in dark, and every value is opaque six-digit RGB.
        func luminance(_ hex: String) -> Int {
            Int(hex.dropFirst(), radix: 16).map { ($0 >> 16 & 0xFF) + ($0 >> 8 & 0xFF) + ($0 & 0xFF) } ?? -1
        }
        XCTAssertLessThan(luminance(light.palette.base05), luminance(light.palette.base00))
        XCTAssertGreaterThan(luminance(dark.palette.base05), luminance(dark.palette.base00))
        XCTAssertLessThan(luminance(light.palette.base0B), luminance(try hex(.systemGreen, in: .aqua)), "light hues gain ink for legibility on white")
    }

    @MainActor
    func testCacheKeyChangesWithTheSystemPaletteOnly() throws {
        let system = PreviewTheme.system(dark: false)
        XCTAssertNotEqual(system.cacheKey, system.id)
        XCTAssertTrue(system.cacheKey.hasPrefix(system.id))

        let bundled = try XCTUnwrap(PreviewThemeCatalog.bundled.first(where: { $0.id == "github" }))
        XCTAssertEqual(bundled.cacheKey, bundled.id)
        XCTAssertFalse(bundled.isSystem)
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
