import AppKit
import JavaScriptCore

/// Code-block highlighting by highlight.js — the bundled build in `Hashlight/HighlightJS` with
/// every language it ships — run in JavaScriptCore. Colours follow highlight.js's own styles: its
/// `default` and `dark` styles for the System theme, and its Base16 template for the bundled
/// Base16 palettes. Shared with the Quick Look extension, which bundles the same script.
///
/// highlight.js returns HTML (`<span class="hljs-keyword">let</span>`); `HighlightJSMarkup` turns
/// its spans into attributes. The app runs with the hardened runtime and without the JIT
/// entitlement, so JavaScriptCore interprets: about 1 MB of code takes a second or two.
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    /// Longer blocks are shown without highlighting, so one huge log pasted into a code fence
    /// cannot stall the preview.
    static let maximumLength = 200_000

    private init() {}

    /// Loaded on the first highlighted block; nil if the script is missing or fails to load.
    private lazy var engine: HighlightJS? = HighlightJS(bundle: .main)
    private var cachedStyle: (key: String, style: HighlightStyle)?
    /// highlight.js's HTML by language and code. Zoom, font, and theme changes rebuild every
    /// block; with this they only restyle it instead of running the script again.
    private let markupCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    /// The number of languages highlight.js registered, 0 if it did not load.
    var languageCount: Int { engine?.languageCount ?? 0 }

    /// Whether `language` is a highlight.js language name or alias (any case).
    func supports(language: String) -> Bool {
        engine?.supports(language) ?? false
    }

    /// `code` in `font`, coloured for `language`. Without a known language (or for a block over
    /// `maximumLength`) every character gets the style's plain foreground.
    func highlight(code: String, language: String?, font: NSFont, theme: PreviewTheme) -> NSAttributedString {
        let style = style(for: theme)
        let plain = NSAttributedString(string: code, attributes: [.font: font, .foregroundColor: style.foreground])
        guard let language, !language.isEmpty, !code.isEmpty,
              (code as NSString).length <= Self.maximumLength,
              let html = markup(for: code, language: language) else { return plain }
        let highlighted = HighlightJSMarkup.attributedString(html, font: font, style: style)
        // The markup must give back the code exactly; anything else is shown plain.
        return highlighted.string == code ? highlighted : plain
    }

    private func markup(for code: String, language: String) -> String? {
        let key = "\(language.lowercased())\u{1F}\(code)" as NSString
        if let cached = markupCache.object(forKey: key) { return cached as String }
        guard let html = engine?.highlight(code, language: language) else { return nil }
        markupCache.setObject(html as NSString, forKey: key, cost: 2 * ((html as NSString).length + key.length))
        return html
    }

    private func style(for theme: PreviewTheme) -> HighlightStyle {
        if let cachedStyle, cachedStyle.key == theme.cacheKey { return cachedStyle.style }
        let style = HighlightStyle.for(theme)
        cachedStyle = (theme.cacheKey, style)
        return style
    }
}

// MARK: - highlight.js in JavaScriptCore

/// The bundled highlight.js in its own JavaScriptCore context.
private final class HighlightJS {
    private let context: JSContext
    private let hljs: JSValue
    private var known: [String: Bool] = [:]
    let languageCount: Int

    init?(bundle: Bundle) {
        guard let url = bundle.url(forResource: "highlight.min", withExtension: "js", subdirectory: "HighlightJS"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { return nil }
        context.name = "highlight.js"
        context.evaluateScript(source, withSourceURL: url)
        guard context.exception == nil,
              let hljs = context.objectForKeyedSubscript("hljs"), hljs.isObject else { return nil }
        self.context = context
        self.hljs = hljs
        languageCount = Int(hljs.invokeMethod("listLanguages", withArguments: [])?.objectForKeyedSubscript("length")?.toInt32() ?? 0)
    }

    func supports(_ language: String) -> Bool {
        let name = language.lowercased()
        if let cached = known[name] { return cached }
        let definition = hljs.invokeMethod("getLanguage", withArguments: [name])
        let found = context.exception == nil && definition.map { !$0.isUndefined && !$0.isNull } == true
        context.exception = nil
        known[name] = found
        return found
    }

    /// highlight.js's HTML for `code`, or nil for an unknown language or a script error.
    func highlight(_ code: String, language: String) -> String? {
        guard supports(language),
              let options = JSValue(object: ["language": language.lowercased(), "ignoreIllegals": true], in: context)
        else { return nil }
        let result = hljs.invokeMethod("highlight", withArguments: [code, options])
        defer { context.exception = nil }
        guard context.exception == nil,
              let value = result?.objectForKeyedSubscript("value"), value.isString else { return nil }
        return value.toString()
    }
}

// MARK: - From highlight.js's HTML to attributes

/// Reads highlight.js's output: text with `&amp; &lt; &gt; &quot; &#x27;` escapes, and nested
/// `<span class="…">` elements, nothing else.
enum HighlightJSMarkup {
    static func attributedString(_ html: String, font: NSFont, style: HighlightStyle) -> NSAttributedString {
        let fonts = FontVariants(font)
        func attributes(_ look: HighlightStyle.Look) -> [NSAttributedString.Key: Any] {
            [.font: fonts.font(bold: look.bold, italic: look.italic), .foregroundColor: look.color]
        }

        let bytes = Array(html.utf8)
        let result = NSMutableAttributedString()
        var scopes: [String] = []
        var looks: [HighlightStyle.Look] = [style.base]
        var stack: [[NSAttributedString.Key: Any]] = [attributes(style.base)]
        var text: [UInt8] = []
        text.reserveCapacity(256)

        func flush() {
            guard !text.isEmpty else { return }
            result.append(NSAttributedString(string: String(decoding: text, as: UTF8.self), attributes: stack[stack.count - 1]))
            text.removeAll(keepingCapacity: true)
        }

        let openTag = Array("<span class=\"".utf8)
        let closeTag = Array("</span>".utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "<") {
                if bytes.hasPrefix(closeTag, at: index) {
                    flush()
                    if !scopes.isEmpty {
                        scopes.removeLast()
                        looks.removeLast()
                        stack.removeLast()
                    }
                    index += closeTag.count
                    continue
                }
                if bytes.hasPrefix(openTag, at: index),
                   let quote = bytes[(index + openTag.count)...].firstIndex(of: UInt8(ascii: "\"")),
                   quote + 1 < bytes.count, bytes[quote + 1] == UInt8(ascii: ">") {
                    flush()
                    let scope = Self.scope(fromClasses: String(decoding: bytes[(index + openTag.count)..<quote], as: UTF8.self))
                    let look = style.look(for: scope, ancestors: scopes, inherited: looks[looks.count - 1])
                    scopes.append(scope)
                    looks.append(look)
                    stack.append(attributes(look))
                    index = quote + 2
                    continue
                }
            } else if byte == UInt8(ascii: "&"),
                      let semicolon = bytes[index..<min(bytes.count, index + 8)].firstIndex(of: UInt8(ascii: ";")),
                      let decoded = Self.entity(String(decoding: bytes[(index + 1)..<semicolon], as: UTF8.self)) {
                text.append(decoded)
                index = semicolon + 1
                continue
            }
            text.append(byte)
            index += 1
        }
        flush()
        return result
    }

    /// The scope a span's classes stand for: `hljs-title function_` is `title.function`,
    /// `hljs-title class_ inherited__` is `title.class.inherited`, and an embedded language's
    /// `language-css` is `language:css`.
    static func scope(fromClasses classes: String) -> String {
        let parts = classes.split(separator: " ")
        guard let first = parts.first else { return "" }
        if first.hasPrefix("hljs-") {
            var scope = String(first.dropFirst(5))
            for part in parts.dropFirst() {
                scope += "." + part.prefix { $0 != "_" }
            }
            return scope
        }
        if first.hasPrefix("language-") {
            return "language:" + first.dropFirst(9)
        }
        return String(first)
    }

    private static func entity(_ name: String) -> UInt8? {
        switch name {
        case "amp": return UInt8(ascii: "&")
        case "lt": return UInt8(ascii: "<")
        case "gt": return UInt8(ascii: ">")
        case "quot": return UInt8(ascii: "\"")
        case "#x27", "#39": return UInt8(ascii: "'")
        default: return nil
        }
    }

    /// The code font in the four weights and slants a style can ask for, made once per block.
    private struct FontVariants {
        let regular: NSFont
        let bold: NSFont
        let italic: NSFont
        let boldItalic: NSFont

        init(_ font: NSFont) {
            // NSFontManager finds a family's real bold and italic faces (SF Mono's semibold,
            // Menlo-Bold); a face the family lacks leaves the font as it is.
            let manager = NSFontManager.shared
            regular = font
            bold = manager.convert(font, toHaveTrait: .boldFontMask)
            italic = manager.convert(font, toHaveTrait: .italicFontMask)
            boldItalic = manager.convert(bold, toHaveTrait: .italicFontMask)
        }

        func font(bold isBold: Bool, italic isItalic: Bool) -> NSFont {
            switch (isBold, isItalic) {
            case (false, false): return regular
            case (true, false): return bold
            case (false, true): return italic
            case (true, true): return boldItalic
            }
        }
    }
}

private extension Array where Element == UInt8 {
    func hasPrefix(_ prefix: [UInt8], at index: Int) -> Bool {
        guard index + prefix.count <= count else { return false }
        for offset in 0..<prefix.count where self[index + offset] != prefix[offset] {
            return false
        }
        return true
    }
}

// MARK: - Colours

/// highlight.js's look for its scopes, transcribed from its CSS styles (highlight.js 11.12.0,
/// BSD-3-Clause): rules apply by specificity and then in order, and a scope without a rule
/// inherits its enclosing scope's look, as in CSS.
struct HighlightStyle {
    struct Look: Equatable {
        var color: NSColor
        var bold = false
        var italic = false
    }

    struct Rule {
        /// Scopes, outermost first, as in a CSS descendant selector: `meta string` is a string
        /// inside a meta scope. A scope also matches its sub-scopes (`title` matches `title.class`).
        let selector: [String]
        let color: NSColor?
        let bold: Bool?
        let italic: Bool?
        var specificity: Int { selector.reduce(0) { $0 + $1.split(separator: ".").count } }
    }

    let foreground: NSColor
    /// Ordered by specificity, keeping declaration order among equals.
    let rules: [Rule]

    init(foreground: NSColor, rules: [Rule]) {
        self.foreground = foreground
        self.rules = rules.enumerated()
            .sorted { ($0.element.specificity, $0.offset) < ($1.element.specificity, $1.offset) }
            .map(\.element)
    }

    var base: Look { Look(color: foreground) }

    func look(for scope: String, ancestors: [String], inherited: Look) -> Look {
        var look = inherited
        for rule in rules where Self.matches(rule.selector, scope: scope, ancestors: ancestors) {
            if let color = rule.color { look.color = color }
            if let bold = rule.bold { look.bold = bold }
            if let italic = rule.italic { look.italic = italic }
        }
        return look
    }

    private static func matches(_ selector: [String], scope: String, ancestors: [String]) -> Bool {
        guard let target = selector.last, matches(target, scope) else { return false }
        // The rest must match ancestors in order, innermost last (CSS descendant combinators).
        var remaining = selector.dropLast()
        for ancestor in ancestors.reversed() {
            guard let next = remaining.last else { break }
            if matches(next, ancestor) { remaining.removeLast() }
        }
        return remaining.isEmpty
    }

    private static func matches(_ component: String, _ scope: String) -> Bool {
        scope == component || scope.hasPrefix(component + ".")
    }

    static func `for`(_ theme: PreviewTheme) -> HighlightStyle {
        guard theme.isSystem else { return base16(theme) }
        return theme.isDark ? dark : defaultLight
    }

    // MARK: Styles

    /// A CSS rule group: the same declarations for several selectors.
    private static func rule(_ selectors: String..., color: NSColor? = nil, bold: Bool? = nil, italic: Bool? = nil) -> [Rule] {
        selectors.map { Rule(selector: $0.split(separator: " ").map(String.init), color: color, bold: bold, italic: italic) }
    }

    private static func rgb(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// `styles/default.css` — "Original highlight.js style" by Ivan Sagalaev.
    static let defaultLight = HighlightStyle(foreground: rgb(0x444444), rules: [
        rule("comment", color: rgb(0x697070)),
        rule("tag", "punctuation", color: rgb(0x444444, alpha: 0xAA / 255.0)),
        rule("tag name", "tag attr", color: rgb(0x444444)),
        rule("keyword", "attribute", "selector-tag", "meta keyword", "doctag", "name", bold: true),
        rule("type", "string", "number", "selector-id", "selector-class", "quote", "template-tag", "deletion",
             color: rgb(0x880000)),
        rule("title", "section", color: rgb(0x880000), bold: true),
        rule("regexp", "symbol", "variable", "template-variable", "link", "selector-attr", "operator", "selector-pseudo",
             color: rgb(0xAB5656)),
        rule("literal", color: rgb(0x669955)),
        rule("built_in", "bullet", "code", "addition", color: rgb(0x397300)),
        rule("meta", color: rgb(0x1F7199)),
        rule("meta string", color: rgb(0x3388AA)),
        rule("emphasis", italic: true),
        rule("strong", bold: true)
    ].flatMap { $0 })

    /// `styles/dark.css` — "Dark style from softwaremaniacs.org" by Ivan Sagalaev, the default
    /// style's dark counterpart.
    static let dark = HighlightStyle(foreground: rgb(0xDDDDDD), rules: [
        rule("keyword", "selector-tag", "literal", "section", "link", color: rgb(0xFFFFFF)),
        rule("string", "title", "name", "type", "attribute", "symbol", "bullet", "built_in", "addition", "variable",
             "template-tag", "template-variable", color: rgb(0xDD8888)),
        rule("comment", "quote", "deletion", "meta", color: rgb(0x979797)),
        rule("keyword", "selector-tag", "literal", "title", "section", "doctag", "type", "name", "strong", bold: true),
        rule("emphasis", italic: true)
    ].flatMap { $0 })

    /// highlight.js's Base16 template (`styles/base16/*.css`, from highlightjs/base16-highlightjs)
    /// filled in with the theme's palette.
    static func base16(_ theme: PreviewTheme) -> HighlightStyle {
        HighlightStyle(foreground: theme.textColor, rules: [
            rule("comment", color: theme.commentColor),
            rule("tag", color: theme.secondaryTextColor),
            rule("subst", "punctuation", "operator", color: theme.textColor),
            rule("operator", color: theme.textColor.withAlphaComponent(0.7)),
            rule("bullet", "variable", "template-variable", "selector-tag", "name", "deletion", color: theme.redColor),
            rule("symbol", "number", "link", "attr", "variable.constant", "literal", color: theme.orangeColor),
            rule("title", "class title", "title.class", color: theme.yellowColor),
            rule("strong", color: theme.yellowColor, bold: true),
            rule("code", "addition", "title.class.inherited", "string", color: theme.greenColor),
            rule("built_in", "doctag", "quote", "regexp", color: theme.cyanColor),
            rule("function title", "attribute", "title.function", "section", color: theme.blueColor),
            rule("type", "template-tag", "keyword", color: theme.purpleColor),
            rule("emphasis", color: theme.purpleColor, italic: true),
            rule("meta", "meta keyword", "meta string", color: theme.brownColor),
            rule("meta keyword", bold: true)
        ].flatMap { $0 })
    }
}
