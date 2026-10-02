import AppKit
import XCTest
@testable import Hashlight

/// Tests for the Quick Look extension. Its sources (`QuickLookDocument.swift` and
/// `PreviewViewController.swift`) are compiled directly into this test bundle (an .appex cannot
/// host XCTest) and run against the app module's renderer, the same composition the extension
/// performs.
nonisolated final class QuickLookPreviewTests: XCTestCase {
    // MARK: - The preview

    @MainActor
    func testUsesTheDefaultLayoutLeftFullWidthNormalMargins() throws {
        let controller = PreviewViewController()
        controller.show("# Title\n\nBody.", baseURL: nil, truncated: false, options: .defaults)
        let textView = try XCTUnwrap(controller.textView)
        XCTAssertEqual(textView.contentAlignment, .left)
        XCTAssertNil(textView.preferredColumnWidth, "Full width has no maximum")
        XCTAssertEqual(textView.textContainerInset, NSSize(width: PreviewPageMargin.normal.points, height: 40))

        // The column fills the pane less the margins.
        textView.enclosingScrollView?.setFrameSize(NSSize(width: 1600, height: 900))
        textView.setFrameSize(NSSize(width: 1600, height: 900))
        let container = try XCTUnwrap(textView.textContainer)
        XCTAssertEqual(container.containerSize.width, 1600 - 2 * PreviewPageMargin.normal.points, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerOrigin.x, PreviewPageMargin.normal.points, accuracy: 0.5)
    }

    @MainActor
    func testTaskItemsShowReadOnlyCheckboxesWithoutBullets() throws {
        let storage = try render("- [ ] open task\n- [x] done task\n- plain item\n")
        let text = storage.string
        XCTAssertTrue(text.contains("☐  open task"))
        XCTAssertTrue(text.contains("☑  done task"))
        XCTAssertFalse(text.contains("[ ]"))
        XCTAssertFalse(text.contains("[x]"))
        XCTAssertEqual(text.components(separatedBy: "•").count - 1, 1, "only the plain item has a bullet")
    }

    @MainActor
    func testCodeBlocksAreSyntaxHighlightedInACard() throws {
        let storage = try render("```swift\nlet greeting = \"hello\"\nprint(greeting)\n```\n")
        let text = storage.string as NSString
        func color(of fragment: String) -> NSColor? {
            (storage.attribute(.foregroundColor, at: text.range(of: fragment).location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB)
        }
        // highlight.js's default style: bold keywords, dark red strings, green built-ins.
        let keyword = try XCTUnwrap(storage.attribute(.font, at: text.range(of: "let").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(keyword.fontDescriptor.symbolicTraits.contains(.bold), "keywords")
        XCTAssertEqual(color(of: "\"hello\"")?.redComponent ?? 0, 0x88 / 255.0, accuracy: 0.003, "strings")
        XCTAssertEqual(color(of: "print")?.greenComponent ?? 0, 0x73 / 255.0, accuracy: 0.003, "built-ins")
        let payload = try XCTUnwrap(storage.attribute(PreviewTextView.codeBlockKey, at: text.range(of: "let").location, effectiveRange: nil) as? CodeBlockPayload)
        XCTAssertEqual(payload.label?.string, "swift")
        XCTAssertEqual(payload.code, "let greeting = \"hello\"\nprint(greeting)")
    }

    @MainActor
    func testDiagramsAndDisplayMathShowTheirSourceAndNothingWaitsToRender() throws {
        let storage = try render("Inline $x^2$ math.\n\n```mermaid\ngraph TD; A-->B;\n```\n\n$$\na < b\n$$\n")
        let text = storage.string as NSString
        XCTAssertFalse(storage.string.contains("Rendering"))
        func label(of fragment: String) -> String? {
            let location = text.range(of: fragment).location
            XCTAssertNotEqual(location, NSNotFound, fragment)
            return (storage.attribute(PreviewTextView.codeBlockKey, at: location, effectiveRange: nil) as? CodeBlockPayload)?.label?.string
        }
        XCTAssertEqual(label(of: "graph TD; A-->B;"), "mermaid")
        XCTAssertEqual(label(of: "a < b"), "latex")
        let inline = text.range(of: "x^2").location
        XCTAssertEqual(storage.attribute(.foregroundColor, at: inline, effectiveRange: nil) as? NSColor, PreviewTheme.system(dark: false).purpleColor)
    }

    @MainActor
    func testTruncatedDocumentsEndWithANotice() throws {
        let storage = try render("```\nunterminated code", truncated: true)
        XCTAssertTrue(storage.string.hasSuffix(QuickLookDocument.truncationNotice + "\n"))
        let notice = (storage.string as NSString).range(of: QuickLookDocument.truncationNotice)
        XCTAssertNil(storage.attribute(PreviewTextView.codeBlockKey, at: notice.location, effectiveRange: nil), "the notice is outside the open code block")
    }

    @MainActor
    func testTheFrontmatterCardOpensAndClosesLikeTheApps() throws {
        let controller = PreviewViewController()
        controller.show("---\ntitle: Folded\nauthor: Someone\n---\n\nBody.", baseURL: nil, truncated: false, options: .defaults)
        let textView = try XCTUnwrap(controller.textView)
        XCTAssertTrue(textView.string.contains("Folded"))
        XCTAssertFalse(textView.string.contains("author: Someone"), "collapsed at first")
        textView.onFrontmatterToggle?()
        XCTAssertTrue(textView.string.contains("author: Someone"))
        textView.onFrontmatterToggle?()
        XCTAssertFalse(textView.string.contains("author: Someone"))
    }

    @MainActor
    func testPreparesThePreviewFromTheFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-ql-\(UUID().uuidString).md")
        try Data("# From disk\n\n- [x] read\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = PreviewViewController()
        try await controller.preparePreviewOfFile(at: url)
        let text = try XCTUnwrap(controller.textView?.string)
        XCTAssertTrue(text.contains("From disk"))
        XCTAssertTrue(text.contains("☑  read"))
        XCTAssertFalse(text.contains(QuickLookDocument.truncationNotice))
    }

    @MainActor
    func testFollowsTheAppearanceWithTheSystemTheme() throws {
        let controller = PreviewViewController()
        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.show("Some `code`.", baseURL: nil, truncated: false, options: .defaults)
        let textView = try XCTUnwrap(controller.textView)
        let dark = PreviewTheme.system(dark: true)
        XCTAssertEqual(textView.backgroundColor, dark.backgroundColor)
        let storage = try XCTUnwrap(textView.textStorage)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, dark.textColor)

        controller.view.appearance = NSAppearance(named: .aqua)
        let light = PreviewTheme.system(dark: false)
        XCTAssertEqual(textView.backgroundColor, light.backgroundColor, "a Light/Dark switch rebuilds the text")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, light.textColor)
    }

    /// The point of the extension: a document looks as it does in a Hashlight window with the
    /// same themes and fonts and a full-width column.
    @MainActor
    func testRendersLikeTheAppWithDefaultSettings() throws {
        try assertRendersLikeTheApp(.defaults, dark: false)
        try assertRendersLikeTheApp(.defaults, dark: true)
    }

    @MainActor
    func testRendersLikeTheAppWithTheChosenThemesAndFonts() throws {
        let options = try chosenOptions()
        try assertRendersLikeTheApp(options, dark: false)
        try assertRendersLikeTheApp(options, dark: true)
    }

    @MainActor
    func testFollowsTheChosenThemeForEachAppearance() throws {
        let options = try chosenOptions()
        let controller = PreviewViewController()
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.show("# Title\n\n```swift\nlet s = \"hi\"\n```\n", baseURL: nil, truncated: false, options: options)
        let textView = try XCTUnwrap(controller.textView)
        let storage = try XCTUnwrap(textView.textStorage)
        let string = (storage.string as NSString).range(of: "\"hi\"").location
        let github = try XCTUnwrap(PreviewThemeCatalog.bundled.first { $0.id == "github" })
        XCTAssertEqual(textView.backgroundColor, github.backgroundColor)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, github.blueColor, "headings")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: string, effectiveRange: nil) as? NSColor, github.greenColor, "code strings")

        controller.view.appearance = NSAppearance(named: .darkAqua)
        let dracula = try XCTUnwrap(PreviewThemeCatalog.bundled.first { $0.id == "dracula" })
        XCTAssertEqual(textView.backgroundColor, dracula.backgroundColor, "Dark mode uses the dark theme")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: string, effectiveRange: nil) as? NSColor, dracula.greenColor)
    }

    @MainActor
    func testFollowsTheChosenFontsAndSizes() throws {
        let options = try chosenOptions()
        let controller = PreviewViewController()
        controller.show("Body with `inline`.\n\n```\nlet block = 1\n```\n", baseURL: nil, truncated: false, options: options)
        let storage = try XCTUnwrap(controller.textView?.textStorage)
        func font(_ fragment: String) throws -> NSFont {
            let location = (storage.string as NSString).range(of: fragment).location
            return try XCTUnwrap(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
        }
        XCTAssertEqual(try font("Body").familyName, PreviewFontCatalog.mainFont(id: options.mainFontID, size: 20).familyName)
        XCTAssertEqual(try font("Body").pointSize, 20, accuracy: 0.01)
        XCTAssertEqual(try font("let block").familyName, PreviewFontCatalog.fixedFont(id: options.fixedFontID, size: 15).familyName)
        XCTAssertEqual(try font("let block").pointSize, 15, accuracy: 0.01)
        XCTAssertEqual(try font("inline").pointSize, 18.75, accuracy: 0.01, "inline code follows the body size, as in the app")
    }

    @MainActor
    func testUnusableChoicesFallBackToTheDefaults() {
        let options = PreviewViewController.Options(
            QuickLookViewingSettings(
                lightThemeID: "dracula", // a dark theme in the light slot
                darkThemeID: "no-such-theme",
                mainFontID: PreviewFontCatalog.fixedOptions.dropFirst().first?.id, // monospaced as the main font
                fixedFontID: "No Such Font",
                mainFontSize: 400,
                fixedFontSize: .nan
            ),
            tableColumnConfiguration: nil
        )
        XCTAssertEqual(options.lightThemeID, PreviewThemeCatalog.defaultLightID)
        XCTAssertEqual(options.darkThemeID, PreviewThemeCatalog.defaultDarkID)
        XCTAssertEqual(options.mainFontID, PreviewFontCatalog.systemMainID)
        XCTAssertEqual(options.fixedFontID, PreviewFontCatalog.systemFixedID)
        XCTAssertEqual(options.mainFontSize, PreviewFontCatalog.mainSizeRange.upperBound)
        XCTAssertEqual(options.fixedFontSize, PreviewFontCatalog.defaultFixedSize)
        XCTAssertEqual(PreviewViewController.Options(QuickLookViewingSettings(), tableColumnConfiguration: nil), .defaults,
                       "nothing shared yet: Hashlight's defaults")
    }

    @MainActor
    func testTheViewingChoicesRoundTripThroughTheSharedPreferences() throws {
        let domain = "io.github.ib0ndar.hashlight.tests.ql-viewing.\(UUID().uuidString)"
        let shared = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { shared.removePersistentDomain(forName: domain) }
        XCTAssertEqual(QuickLookViewingPreferences.load(from: shared), QuickLookViewingSettings())

        let settings = QuickLookViewingSettings(lightThemeID: "github", darkThemeID: "dracula", mainFontID: "Charter",
                                                fixedFontID: "Menlo", mainFontSize: 18, fixedFontSize: 12)
        QuickLookViewingPreferences.persist(settings, sharedPreferences: shared)
        XCTAssertEqual(QuickLookViewingPreferences.load(from: shared), settings)

        shared.set(true, forKey: QuickLookViewingPreferences.mainFontSizeKey)
        shared.set(7, forKey: QuickLookViewingPreferences.lightThemeKey)
        let wrongTypes = QuickLookViewingPreferences.load(from: shared)
        XCTAssertNil(wrongTypes.mainFontSize, "a Boolean is not a size")
        XCTAssertNil(wrongTypes.lightThemeID)
    }

    @MainActor
    func testTheAppSharesItsThemesAndFontsWithQuickLook() throws {
        let settings = SettingsManager.shared
        let saved = settings.quickLookViewingSettings
        // The test host shares the Debug app's defaults: put back exactly what was there.
        let keys = [DefaultsKeys.lightPreviewThemeID, DefaultsKeys.darkPreviewThemeID, DefaultsKeys.mainPreviewFontID,
                    DefaultsKeys.fixedPreviewFontID, DefaultsKeys.mainPreviewFontSize, DefaultsKeys.fixedPreviewFontSize]
        let unset = keys.filter { UserDefaults.standard.object(forKey: $0) == nil }
        defer {
            settings.lightPreviewThemeID = saved.lightThemeID!
            settings.darkPreviewThemeID = saved.darkThemeID!
            settings.mainPreviewFontID = saved.mainFontID!
            settings.fixedPreviewFontID = saved.fixedFontID!
            settings.mainPreviewFontSize = saved.mainFontSize!
            settings.fixedPreviewFontSize = saved.fixedFontSize!
            unset.forEach(UserDefaults.standard.removeObject(forKey:))
        }
        let shared = UserDefaults(suiteName: QuickLookViewingPreferences.sharedDomain)
        settings.lightPreviewThemeID = "github"
        settings.darkPreviewThemeID = "dracula"
        settings.mainPreviewFontSize = 21
        settings.fixedPreviewFontSize = 11
        let mirrored = QuickLookViewingPreferences.load(from: shared)
        XCTAssertEqual(mirrored, settings.quickLookViewingSettings)
        XCTAssertEqual(mirrored.lightThemeID, "github")
        XCTAssertEqual(mirrored.darkThemeID, "dracula")
        XCTAssertEqual(mirrored.mainFontSize, 21)
        XCTAssertEqual(mirrored.fixedFontSize, 11)
    }

    // MARK: - decode

    func testDecodesUTF8AndStripsBOM() {
        XCTAssertEqual(QuickLookDocument.decode(Data("héllo — ✓".utf8)), "héllo — ✓")
        XCTAssertEqual(QuickLookDocument.decode(Data([0xEF, 0xBB, 0xBF]) + Data("# Hi".utf8)), "# Hi")
    }

    func testDecodesUTF16WithBOMBothEndians() {
        let little = Data([0xFF, 0xFE]) + "# Hé".data(using: .utf16LittleEndian)!
        let big = Data([0xFE, 0xFF]) + "# Hé".data(using: .utf16BigEndian)!
        XCTAssertEqual(QuickLookDocument.decode(little), "# Hé")
        XCTAssertEqual(QuickLookDocument.decode(big), "# Hé")
    }

    func testFallsBackToWindows1252ForInvalidUTF8() {
        // 0x93/0x94 are curly quotes in CP1252 and invalid as UTF-8 lead bytes; 0xE9 is é.
        let data = Data([0x93, 0x63, 0x61, 0x66, 0xE9, 0x94])
        XCTAssertEqual(QuickLookDocument.decode(data), "\u{201C}caf\u{E9}\u{201D}")
    }

    func testBytesUndefinedInCP1252StillDecode() {
        // 0x81 is unassigned in CP1252; must not produce an empty preview.
        XCTAssertFalse(QuickLookDocument.decode(Data([0x41, 0x81, 0xE9])).isEmpty)
    }

    func testTruncatedUTF8TailDoesNotFallBackToCP1252() {
        let full = Data("abc✓".utf8)          // ✓ = E2 9C 93
        let cut = full.dropLast()              // E2 9C — incomplete scalar
        XCTAssertEqual(QuickLookDocument.decode(cut, truncated: true), "abc")
        // Same bytes claimed complete are genuinely not UTF-8 → CP1252 mojibake, not a crash.
        XCTAssertNotEqual(QuickLookDocument.decode(cut, truncated: false), "abc")
    }

    func testEmptyData() {
        XCTAssertEqual(QuickLookDocument.decode(Data()), "")
        XCTAssertEqual(QuickLookDocument.decode(Data(), truncated: true), "")
    }

    // MARK: - readPrefix

    func testReadPrefixCapsAndReportsTruncation() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashlight-ql-\(UUID().uuidString).md")
        try Data(repeating: 0x61, count: 100).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let capped = try QuickLookDocument.readPrefix(of: url, maxBytes: 40)
        XCTAssertEqual(capped.data.count, 40)
        XCTAssertTrue(capped.truncated)

        let exact = try QuickLookDocument.readPrefix(of: url, maxBytes: 100)
        XCTAssertEqual(exact.data.count, 100)
        XCTAssertFalse(exact.truncated)

        let whole = try QuickLookDocument.readPrefix(of: url)
        XCTAssertEqual(whole.data.count, 100)
        XCTAssertFalse(whole.truncated)
    }

    func testReadPrefixThrowsForMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-ql-missing-\(UUID().uuidString).md")
        XCTAssertThrowsError(try QuickLookDocument.readPrefix(of: url))
    }

    // MARK: - Helpers

    /// Non-default choices: Github light and Dracula, the first other installed proportional and
    /// monospaced families, 20 / 15 pt.
    @MainActor
    private func chosenOptions() throws -> PreviewViewController.Options {
        var options = PreviewViewController.Options.defaults
        options.lightThemeID = "github"
        options.darkThemeID = "dracula"
        options.mainFontID = try XCTUnwrap(PreviewFontCatalog.mainOptions.dropFirst().first).id
        options.fixedFontID = try XCTUnwrap(PreviewFontCatalog.fixedOptions.dropFirst().first).id
        options.mainFontSize = 20
        options.fixedFontSize = 15
        return options
    }

    /// Renders the same document in Quick Look and in the app's preview (Full width, the same
    /// themes and fonts) and compares the text, fonts, and colours run by run.
    @MainActor
    private func assertRendersLikeTheApp(_ options: PreviewViewController.Options, dark: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let markdown = """
        ---
        title: Rendering check
        ---

        # Rendering check

        A paragraph with **bold**, *italic*, ~~strike~~, ==highlight==, `inline code` and a [link](https://example.com).

        - [ ] open task alpha
        - [x] done task beta
          - nested bullet

        | Interface | Description | Status |
        |-----------|:-----------:|-------:|
        | eth1/1 | Uplink toward the aggregation switch | Up |

        ```swift
        let greeting = "hello" // comment
        ```

        > [!NOTE]
        > Alerts render as callouts.

        > A quotation.

        ---
        """
        let controller = PreviewViewController()
        controller.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        controller.show(markdown, baseURL: nil, truncated: false, options: options)
        let quickLook = try XCTUnwrap(controller.textView?.textStorage)

        let theme = options.theme(dark: dark)
        let (scrollView, textView) = PreviewTextView.makeScrollView(
            theme: theme, contentAlignment: .left, contentWidth: .full, pageMargin: .normal, verticalInset: 40
        )
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        textView.setFrameSize(NSSize(width: 800, height: 1000))
        let coordinator = MarkdownTextView.Coordinator()
        let documentId = UUID()
        coordinator.documentId = documentId
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        let app = MarkdownTextView(
            content: markdown, baseURL: nil, documentId: documentId,
            scrollToHeadingId: .constant(nil), searchText: "", currentMatchIndex: 0,
            mainFontID: options.mainFontID, fixedFontID: options.fixedFontID,
            mainFontSize: CGFloat(options.mainFontSize), fixedFontSize: CGFloat(options.fixedFontSize),
            theme: theme, contentWidth: .full
        )
        coordinator.scheduleRebuild(for: app, textView: textView, scrollView: scrollView, contentChanged: false, isReload: false)
        let appStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(quickLook.string, appStorage.string, file: file, line: line)
        for key in [NSAttributedString.Key.font, .foregroundColor, .backgroundColor] {
            XCTAssertEqual(runs(of: key, in: quickLook), runs(of: key, in: appStorage), "\(key.rawValue) differs (dark: \(dark))", file: file, line: line)
        }
    }

    @MainActor
    private func render(_ markdown: String, truncated: Bool = false) throws -> NSTextStorage {
        let controller = PreviewViewController()
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.show(markdown, baseURL: nil, truncated: truncated, options: .defaults)
        return try XCTUnwrap(controller.textView?.textStorage)
    }

    /// An attribute's runs as (range, description) pairs, comparable across two builds.
    @MainActor
    private func runs(of key: NSAttributedString.Key, in text: NSAttributedString) -> [String] {
        var result: [String] = []
        text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let description: String
            switch value {
            case let font as NSFont: description = "\(font.fontName) \(font.pointSize)"
            case let color as NSColor: description = color.usingColorSpace(.sRGB).map { "\($0.redComponent) \($0.greenComponent) \($0.blueComponent) \($0.alphaComponent)" } ?? "\(color)"
            case nil: description = "none"
            default: description = "\(value!)"
            }
            result.append("\(range.location)+\(range.length) \(description)")
        }
        return result
    }
}
