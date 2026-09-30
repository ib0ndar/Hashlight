import AppKit
import SwiftUI

/// A bundled Base16 palette mapped to the semantic roles used by the native Markdown preview.
///
/// `base00...base07` are background/foreground steps and `base08...base0F` are syntax/accent
/// colors. Keeping the source palette intact means zMD can consume the upstream Tinted Theming
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

    static func system(for colorScheme: ColorScheme) -> PreviewTheme {
        colorScheme == .dark ? systemDark : systemLight
    }

    // GitHub's neutral palettes are close to the native NSTextView defaults while still giving
    // the WebKit renderers concrete RGB values. These remain the default "System" preview.
    private static let systemLight = PreviewTheme(
        id: "system-light",
        name: "System",
        author: "zMD",
        variant: "light",
        palette: Palette(
            base00: "#FFFFFF", base01: "#F6F8FA", base02: "#D0D7DE", base03: "#6E7781",
            base04: "#57606A", base05: "#24292F", base06: "#1F2328", base07: "#000000",
            base08: "#CF222E", base09: "#953800", base0A: "#9A6700", base0B: "#1A7F37",
            base0C: "#0A7A83", base0D: "#0969DA", base0E: "#8250DF", base0F: "#A40E26"
        )
    )

    private static let systemDark = PreviewTheme(
        id: "system-dark",
        name: "System",
        author: "zMD",
        variant: "dark",
        palette: Palette(
            base00: "#0D1117", base01: "#161B22", base02: "#30363D", base03: "#8B949E",
            base04: "#B1BAC4", base05: "#C9D1D9", base06: "#E6EDF3", base07: "#FFFFFF",
            base08: "#FF7B72", base09: "#FFA657", base0A: "#D29922", base0B: "#7EE787",
            base0C: "#A5D6FF", base0D: "#58A6FF", base0E: "#D2A8FF", base0F: "#F2CC60"
        )
    )
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
    static let defaultLightID = "github"
    static let defaultDarkID = "github-dark"

    static let all: [PreviewTheme] = {
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

    static var light: [PreviewTheme] { all.filter { !$0.isDark } }
    static var dark: [PreviewTheme] { all.filter(\.isDark) }

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
