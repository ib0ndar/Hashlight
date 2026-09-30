import AppKit
import SwiftUI

struct PreviewFontOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Fonts available to the rendered Markdown preview, split by their intended role.
/// The menus are built from installed font families so user-installed fonts work without
/// hard-coding a small list that differs from one Mac to another.
enum PreviewFontCatalog {
    static let systemMainID = "__zmd_system_main__"
    static let systemFixedID = "__zmd_system_fixed__"

    private struct InstalledFamily {
        let name: String
        let isMonospaced: Bool
    }

    private static let installedFamilies: [InstalledFamily] = {
        NSFontManager.shared.availableFontFamilies.compactMap { family in
            let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            guard let font = NSFont(descriptor: descriptor, size: 13) else { return nil }
            return InstalledFamily(
                name: family,
                isMonospaced: font.fontDescriptor.symbolicTraits.contains(.monoSpace)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static let mainOptions: [PreviewFontOption] = [
        PreviewFontOption(id: systemMainID, name: "System")
    ] + installedFamilies
        .filter { !$0.isMonospaced }
        .map { PreviewFontOption(id: $0.name, name: $0.name) }

    static let fixedOptions: [PreviewFontOption] = [
        PreviewFontOption(id: systemFixedID, name: "System Monospaced")
    ] + installedFamilies
        .filter(\.isMonospaced)
        .map { PreviewFontOption(id: $0.name, name: $0.name) }

    static func validatedMainID(_ id: String?) -> String {
        guard let id else { return systemMainID }
        if id == systemMainID { return id }
        guard isMonospacedFamily(id) == false else { return systemMainID }
        return id
    }

    static func validatedFixedID(_ id: String?) -> String {
        guard let id else { return systemFixedID }
        if id == systemFixedID { return id }
        guard isMonospacedFamily(id) == true else { return systemFixedID }
        return id
    }

    static func mainFont(id: String, size: CGFloat) -> NSFont {
        font(familyID: validatedMainID(id), size: size, monospaced: false)
    }

    static func fixedFont(id: String, size: CGFloat) -> NSFont {
        font(familyID: validatedFixedID(id), size: size, monospaced: true)
    }

    static func swiftUIFont(id: String, size: CGFloat, monospaced: Bool) -> Font {
        if id == systemMainID {
            return .system(size: size)
        }
        if id == systemFixedID {
            return .system(size: size, design: .monospaced)
        }
        let resolved = monospaced
            ? fixedFont(id: id, size: size)
            : mainFont(id: id, size: size)
        return .custom(resolved.fontName, size: size)
    }

    static func cssFamily(id: String, monospaced: Bool) -> String {
        let validated = monospaced ? validatedFixedID(id) : validatedMainID(id)
        if validated == systemMainID {
            return "-apple-system, BlinkMacSystemFont, sans-serif"
        }
        if validated == systemFixedID {
            return "ui-monospace, \"SF Mono\", Menlo, Monaco, monospace"
        }
        let escaped = validated
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\", \(monospaced ? "monospace" : "sans-serif")"
    }

    private static func font(familyID: String, size: CGFloat, monospaced: Bool) -> NSFont {
        if familyID == systemMainID {
            return NSFont.systemFont(ofSize: size)
        }
        if familyID == systemFixedID {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }

        let descriptor = NSFontDescriptor(fontAttributes: [.family: familyID])
        return NSFont(descriptor: descriptor, size: size)
            ?? (monospaced
                ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                : NSFont.systemFont(ofSize: size))
    }

    private static func isMonospacedFamily(_ family: String) -> Bool? {
        guard NSFontManager.shared.availableFontFamilies.contains(family) else { return nil }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        guard let font = NSFont(descriptor: descriptor, size: 13) else { return nil }
        return font.fontDescriptor.symbolicTraits.contains(.monoSpace)
    }
}
