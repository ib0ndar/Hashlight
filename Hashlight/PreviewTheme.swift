import AppKit
import SwiftUI

/// A bundled Base16 palette mapped to the semantic roles used by the native Markdown preview.
///
/// `base00...base07` are background/foreground steps and `base08...base0F` are syntax/accent
/// colors. Keeping the source palette intact means Hashlight can consume the upstream Tinted Theming
/// catalog without inventing a separate theme format.
struct PreviewTheme: Codable, Hashable, Identifiable, Sendable {
    struct Palette: Codable, Hashable, Sendable {
        let base00: String
        let base01: String
        let base02: String
        let base03: String
        let base04: String
        let base05: String
        let base06: String
        let base07: String
        let base08: String
        let base09: String
        let base0A: String
        let base0B: String
        let base0C: String
        let base0D: String
        let base0E: String
        let base0F: String
    }

    let id: String
    let name: String
    let author: String
    let variant: String
    let palette: Palette

    var isDark: Bool { variant == "dark" }

    var backgroundColor: NSColor { NSColor(themeHex: palette.base00) }
    var raisedBackgroundColor: NSColor { NSColor(themeHex: palette.base01) }
    var selectionColor: NSColor { NSColor(themeHex: palette.base02) }
    var commentColor: NSColor { NSColor(themeHex: palette.base03) }
    var secondaryTextColor: NSColor { NSColor(themeHex: palette.base04) }
    var textColor: NSColor { NSColor(themeHex: palette.base05) }
    var strongTextColor: NSColor { NSColor(themeHex: palette.base06) }
    var brightestTextColor: NSColor { NSColor(themeHex: palette.base07) }
    var redColor: NSColor { NSColor(themeHex: palette.base08) }
    var orangeColor: NSColor { NSColor(themeHex: palette.base09) }
    var yellowColor: NSColor { NSColor(themeHex: palette.base0A) }
    var greenColor: NSColor { NSColor(themeHex: palette.base0B) }
    var cyanColor: NSColor { NSColor(themeHex: palette.base0C) }
    var blueColor: NSColor { NSColor(themeHex: palette.base0D) }
    var purpleColor: NSColor { NSColor(themeHex: palette.base0E) }
    var brownColor: NSColor { NSColor(themeHex: palette.base0F) }

    var appearance: NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    /// CSS colors passed to the small headless WebKit renderers used for HTML, Mermaid, and math.
    var backgroundHex: String { palette.base00 }
    var textHex: String { palette.base05 }

    static let systemLightID = "system-light"
    static let systemDarkID = "system-dark"

    /// The System themes are rebuilt from macOS's colors (see `system(dark:)`), so the same
    /// `id` can stand for different palettes over time.
    var isSystem: Bool { id == Self.systemLightID || id == Self.systemDarkID }

    /// Key for caches of rendered output: the id for a bundled theme, the id plus the resolved
    /// palette for a System theme, so an accent or contrast change is not served stale colors.
    var cacheKey: String {
        guard isSystem else { return id }
        let fingerprint = [
            palette.base00, palette.base01, palette.base02, palette.base03,
            palette.base04, palette.base05, palette.base06, palette.base07,
            palette.base08, palette.base09, palette.base0A, palette.base0B,
            palette.base0C, palette.base0D, palette.base0E, palette.base0F
        ].map { $0.dropFirst() }.joined()
        return "\(id)-\(fingerprint)"
    }

    static func system(for colorScheme: ColorScheme) -> PreviewTheme {
        system(dark: colorScheme == .dark)
    }

    /// The macOS palette for the light or dark appearance: text background, label colors,
    /// separator, the accent color for headings and links, and the system hues for syntax,
    /// resolved now (they follow System Settings → Appearance, including the accent color and
    /// Increase Contrast). Semi-transparent system colors are composited over the background
    /// because every consumer, WebKit included, needs opaque RGB.
    static func system(dark: Bool) -> PreviewTheme {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        var palette: Palette?
        appearance.performAsCurrentDrawingAppearance {
            palette = SystemPalette.resolve(dark: dark)
        }
        return PreviewTheme(
            id: dark ? systemDarkID : systemLightID,
            name: "System",
            author: "macOS",
            variant: dark ? "dark" : "light",
            palette: palette ?? SystemPalette.resolve(dark: dark)
        )
    }
}

/// Builds a Base16 palette from the system colors of the current drawing appearance.
private enum SystemPalette {
    static func resolve(dark: Bool) -> PreviewTheme.Palette {
        let background = rgb(.textBackgroundColor) ?? (dark ? RGB(0.12, 0.12, 0.12) : RGB(1, 1, 1))
        func over(_ color: NSColor) -> RGB {
            composite(rgb(color, keepAlpha: true) ?? background, over: background)
        }

        let ink = over(NSColor.labelColor.withAlphaComponent(1))
        let text = over(.labelColor)
        let secondary = over(.secondaryLabelColor)
        // Light text on white needs more ink than the system hues carry; the dark variants are
        // already designed for dark backgrounds. The accent keeps its exact color.
        func hue(_ color: NSColor, extra: Double = 0) -> RGB {
            let resolved = over(color)
            return dark ? resolved : mix(resolved, ink, 0.35 + extra)
        }

        return PreviewTheme.Palette(
            base00: hex(background),
            base01: hex(mix(background, ink, 0.05)),
            base02: hex(over(.separatorColor)),
            base03: hex(secondary),
            base04: hex(mix(secondary, text, 0.4)),
            base05: hex(text),
            base06: hex(mix(text, ink, 0.5)),
            base07: hex(ink),
            base08: hex(hue(.systemRed)),
            base09: hex(hue(.systemOrange)),
            base0A: hex(hue(.systemYellow, extra: 0.15)),
            base0B: hex(hue(.systemGreen)),
            base0C: hex(hue(.systemTeal)),
            base0D: hex(over(.controlAccentColor)),
            base0E: hex(hue(.systemPurple)),
            base0F: hex(hue(.systemBrown))
        )
    }

    struct RGB {
        var red: Double, green: Double, blue: Double, alpha: Double = 1
        init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
            self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        }
    }

    private static func rgb(_ color: NSColor, keepAlpha: Bool = false) -> RGB? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return RGB(srgb.redComponent, srgb.greenComponent, srgb.blueComponent, alpha: keepAlpha ? srgb.alphaComponent : 1)
    }

    private static func composite(_ color: RGB, over background: RGB) -> RGB {
        mix(background, RGB(color.red, color.green, color.blue), color.alpha)
    }

    private static func mix(_ from: RGB, _ to: RGB, _ fraction: Double) -> RGB {
        let t = min(max(fraction, 0), 1)
        return RGB(
            from.red + (to.red - from.red) * t,
            from.green + (to.green - from.green) * t,
            from.blue + (to.blue - from.blue) * t
        )
    }

    private static func hex(_ color: RGB) -> String {
        func channel(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(color.red), channel(color.green), channel(color.blue))
    }
}

struct PreviewThemeBundle: Decodable, Sendable {
    struct Source: Decodable, Sendable {
        let repository: String
        let revision: String
    }

    let source: Source
    let themes: [PreviewTheme]
}

enum PreviewThemeCatalog {
    /// New users start on the System themes; a saved Base16 choice is kept.
    static let defaultLightID = PreviewTheme.systemLightID
    static let defaultDarkID = PreviewTheme.systemDarkID

    /// The pinned Base16 catalog, loaded once.
    static let bundled: [PreviewTheme] = {
        guard let url = Bundle.main.url(
            forResource: "Base16Themes",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? Bundle.main.url(forResource: "Base16Themes", withExtension: "json"),
        let data = try? Data(contentsOf: url),
        let bundle = try? JSONDecoder().decode(PreviewThemeBundle.self, from: data)
        else {
            return []
        }
        return bundle.themes
    }()

    /// The System theme of each appearance, resolved from the current system colors on every
    /// access, followed by the bundled catalog.
    static var all: [PreviewTheme] { [systemLight, systemDark] + bundled }

    static var systemLight: PreviewTheme { .system(dark: false) }
    static var systemDark: PreviewTheme { .system(dark: true) }

    static var light: [PreviewTheme] { all.filter { !$0.isDark } }
    static var dark: [PreviewTheme] { all.filter(\.isDark) }

    static var bundledLight: [PreviewTheme] { bundled.filter { !$0.isDark } }
    static var bundledDark: [PreviewTheme] { bundled.filter(\.isDark) }

    static func validatedLightID(_ id: String?) -> String {
        if let id, light.contains(where: { $0.id == id }) {
            return id
        }
        return light.first(where: { $0.id == defaultLightID })?.id
            ?? light.first?.id
            ?? defaultLightID
    }

    static func validatedDarkID(_ id: String?) -> String {
        if let id, dark.contains(where: { $0.id == id }) {
            return id
        }
        return dark.first(where: { $0.id == defaultDarkID })?.id
            ?? dark.first?.id
            ?? defaultDarkID
    }

    static func resolve(lightID: String, darkID: String, colorScheme: ColorScheme) -> PreviewTheme {
        if colorScheme == .dark {
            return dark.first(where: { $0.id == darkID })
                ?? dark.first(where: { $0.id == defaultDarkID })
                ?? dark.first
                ?? .system(for: .dark)
        }
        return light.first(where: { $0.id == lightID })
            ?? light.first(where: { $0.id == defaultLightID })
            ?? light.first
            ?? .system(for: .light)
    }
}

extension NSColor {
    convenience init(themeHex value: String) {
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
        var rgb: UInt64 = 0
        guard hex.count == 6, Scanner(string: hex).scanHexInt64(&rgb) else {
            self.init(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            return
        }
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        self.init(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }
}
