import AppKit
import XCTest
@testable import Hashlight

/// The bundled highlight.js (`Hashlight/HighlightJS`) and the colours of its styles.
nonisolated final class SyntaxHighlighterTests: XCTestCase {
    @MainActor
    func testBundlesEveryHighlightJSLanguage() {
        let highlighter = SyntaxHighlighter.shared
        XCTAssertGreaterThanOrEqual(highlighter.languageCount, 190)
        for name in ["swift", "python", "bash", "sh", "zsh", "yaml", "yml", "json", "dockerfile", "powershell",
                     "nginx", "routeros", "c++", "objc", "latex", "SQL", "diff", "ini"] {
            XCTAssertTrue(highlighter.supports(language: name), name)
        }
        for name in ["mermaid", "tree", "no-such-language"] {
            XCTAssertFalse(highlighter.supports(language: name), name)
        }
    }

    @MainActor
    func testTheCodeComesBackExactly() {
        let samples: [(String, String)] = [
            ("xml", "<a href=\"x\">&amp; 'q' \"d\" — ✓ 日本語</a>"),
            ("swift", "let s = \"tab\there\" // ü\n\n/* a\n b */\n"),
            ("bash", "echo \"$HOME\" > out.txt 2>&1 # <done> & 'quoted'"),
            ("json", "{\"emoji\": \"🧪\", \"lt\": \"<\"}")
        ]
        for (language, code) in samples {
            let result = highlight(code, language)
            XCTAssertEqual(result.string, code, language)
            XCTAssertGreaterThan(runs(of: .foregroundColor, in: result), 1, "\(language) is highlighted")
        }
    }

    @MainActor
    func testStringsAndCommentsStayWholeAcrossLines() throws {
        let code = "let url = \"https://example.com\" // let\n/* a\n b */\nfunc greet() {}"
        let result = highlight(code, "swift")
        let text = code as NSString

        let keyword = try font(in: result, at: 0)
        XCTAssertTrue(keyword.fontDescriptor.symbolicTraits.contains(.bold), "keywords are bold")
        assertColor(result, at: 0, 0x444444)

        let string = text.range(of: "\"https://example.com\"")
        assertSingleColor(result, in: string, 0x880000, "a // inside a string stays string")
        let comment = text.range(of: "// let")
        assertSingleColor(result, in: comment, 0x697070)
        XCTAssertFalse(try font(in: result, at: NSMaxRange(comment) - 1).fontDescriptor.symbolicTraits.contains(.bold), "no keyword inside a comment")
        assertSingleColor(result, in: text.range(of: "/* a\n b */"), 0x697070, "a block comment spans its lines")

        let function = text.range(of: "greet")
        assertColor(result, at: function.location, 0x880000)
        XCTAssertTrue(try font(in: result, at: function.location).fontDescriptor.symbolicTraits.contains(.bold))
    }

    @MainActor
    func testNestedScopesFollowTheStylesheet() {
        // default.css: `.hljs-meta .hljs-string` is lighter blue; a keyword inside meta keeps the
        // meta colour (keywords only turn bold); a variable inside a string has its own colour.
        let c = highlight("#include \"stdio.h\"", "c")
        let cText = c.string as NSString
        assertColor(c, at: cText.range(of: "include").location, 0x1F7199)
        assertSingleColor(c, in: cText.range(of: "\"stdio.h\""), 0x3388AA)

        let bash = highlight("echo \"$HOME/x\"", "bash")
        let bashText = bash.string as NSString
        assertColor(bash, at: bashText.range(of: "$HOME").location, 0xAB5656)
        assertColor(bash, at: bashText.range(of: "/x").location, 0x880000)
        assertColor(bash, at: 0, 0x397300)
    }

    @MainActor
    func testTheDarkSystemThemeUsesTheDarkStyle() throws {
        let result = highlight("let x = \"s\" // c", "swift", theme: .system(dark: true))
        let text = result.string as NSString
        assertColor(result, at: 0, 0xFFFFFF)
        XCTAssertTrue(try font(in: result, at: 0).fontDescriptor.symbolicTraits.contains(.bold))
        assertColor(result, at: text.range(of: "x").location, 0xDDDDDD)
        assertColor(result, at: text.range(of: "\"s\"").location, 0xDD8888)
        assertColor(result, at: text.range(of: "// c").location, 0x979797)
    }

    @MainActor
    func testBase16ThemesFillTheTemplateWithTheirPalette() throws {
        let theme = try XCTUnwrap(PreviewThemeCatalog.bundled.first { $0.id == "dracula" })
        let result = highlight("func f() { let n = 42; return \"s\" } // c", "swift", theme: theme)
        let text = result.string as NSString
        func color(_ fragment: String) -> NSColor? {
            result.attribute(.foregroundColor, at: text.range(of: fragment).location, effectiveRange: nil) as? NSColor
        }
        XCTAssertEqual(color("func"), theme.purpleColor)
        XCTAssertEqual(color("f("), theme.blueColor)
        XCTAssertEqual(color("42"), theme.orangeColor)
        XCTAssertEqual(color("\"s\""), theme.greenColor)
        XCTAssertEqual(color("// c"), theme.commentColor)
        XCTAssertEqual(color("n ="), theme.textColor)
    }

    @MainActor
    func testUnknownLanguagesAndHugeBlocksStayPlain() throws {
        let huge = String(repeating: "let x = 1\n", count: SyntaxHighlighter.maximumLength / 10 + 1)
        for (code, language) in [("let x = 1", nil), ("graph TD; A-->B;", "mermaid"), (huge, "swift")] as [(String, String?)] {
            let result = highlight(code, language)
            XCTAssertEqual(result.string, code)
            XCTAssertEqual(runs(of: .foregroundColor, in: result), 1)
            XCTAssertEqual(runs(of: .font, in: result), 1)
            assertColor(result, at: 0, 0x444444)
        }
    }

    @MainActor
    func testScopeNamesFromClasses() {
        XCTAssertEqual(HighlightJSMarkup.scope(fromClasses: "hljs-keyword"), "keyword")
        XCTAssertEqual(HighlightJSMarkup.scope(fromClasses: "hljs-title function_"), "title.function")
        XCTAssertEqual(HighlightJSMarkup.scope(fromClasses: "hljs-title class_ inherited__"), "title.class.inherited")
        XCTAssertEqual(HighlightJSMarkup.scope(fromClasses: "hljs-built_in"), "built_in")
        XCTAssertEqual(HighlightJSMarkup.scope(fromClasses: "language-css"), "language:css")
    }

    // MARK: - Helpers

    @MainActor
    private func highlight(_ code: String, _ language: String?, theme: PreviewTheme = .system(dark: false)) -> NSAttributedString {
        SyntaxHighlighter.shared.highlight(
            code: code,
            language: language,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            theme: theme
        )
    }

    private func runs(of key: NSAttributedString.Key, in text: NSAttributedString) -> Int {
        var count = 0
        text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { _, _, _ in count += 1 }
        return count
    }

    private func font(in text: NSAttributedString, at location: Int) throws -> NSFont {
        try XCTUnwrap(text.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    private func assertColor(_ text: NSAttributedString, at location: Int, _ hex: UInt32, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard location != NSNotFound, location < text.length,
              let color = (text.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB) else {
            return XCTFail("no colour at \(location) \(message)", file: file, line: line)
        }
        let expected = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { CGFloat($0) / 255 }
        let actual = [color.redComponent, color.greenComponent, color.blueComponent]
        for (a, e) in zip(actual, expected) where abs(a - e) > 0.003 {
            return XCTFail(String(format: "colour at %d is #%02X%02X%02X, expected #%06X %@", location,
                                  Int((actual[0] * 255).rounded()), Int((actual[1] * 255).rounded()), Int((actual[2] * 255).rounded()), hex, message),
                           file: file, line: line)
        }
    }

    private func assertSingleColor(_ text: NSAttributedString, in range: NSRange, _ hex: UInt32, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard range.location != NSNotFound else { return XCTFail("fragment not found \(message)", file: file, line: line) }
        var effective = NSRange()
        _ = text.attribute(.foregroundColor, at: range.location, longestEffectiveRange: &effective, in: range)
        XCTAssertEqual(effective, range, "one colour across the range \(message)", file: file, line: line)
        assertColor(text, at: range.location, hex, message, file: file, line: line)
    }
}
