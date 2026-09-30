import AppKit
import XCTest
@testable import Hashlight

nonisolated final class PreviewFontTests: XCTestCase {
    @MainActor
    func testCatalogSeparatesProportionalAndMonospacedFamilies() {
        XCTAssertEqual(PreviewFontCatalog.mainOptions.first?.id, PreviewFontCatalog.systemMainID)
        XCTAssertEqual(PreviewFontCatalog.fixedOptions.first?.id, PreviewFontCatalog.systemFixedID)
        XCTAssertGreaterThan(PreviewFontCatalog.mainOptions.count, 1)
        XCTAssertGreaterThan(PreviewFontCatalog.fixedOptions.count, 1)

        for option in PreviewFontCatalog.fixedOptions.dropFirst() {
            let font = PreviewFontCatalog.fixedFont(id: option.id, size: 13)
            XCTAssertTrue(
                font.fontDescriptor.symbolicTraits.contains(.monoSpace),
                "\(option.name) must only appear in the Fixed font menu"
            )
        }
    }

    @MainActor
    func testInvalidOrCrossRoleSelectionsFallBackToSystemFonts() {
        let fixedFamily = PreviewFontCatalog.fixedOptions.dropFirst().first?.id
        let mainFamily = PreviewFontCatalog.mainOptions.dropFirst().first?.id

        XCTAssertEqual(PreviewFontCatalog.validatedMainID(fixedFamily), PreviewFontCatalog.systemMainID)
        XCTAssertEqual(PreviewFontCatalog.validatedFixedID(mainFamily), PreviewFontCatalog.systemFixedID)
        XCTAssertEqual(PreviewFontCatalog.validatedMainID("Missing Font"), PreviewFontCatalog.systemMainID)
        XCTAssertEqual(PreviewFontCatalog.validatedFixedID("Missing Font"), PreviewFontCatalog.systemFixedID)
    }

    @MainActor
    func testSyntaxHighlightingKeepsTheSelectedFixedFont() throws {
        let option = try XCTUnwrap(PreviewFontCatalog.fixedOptions.dropFirst().first)
        let selectedFont = PreviewFontCatalog.fixedFont(id: option.id, size: 13)
        let theme = PreviewThemeCatalog.resolve(
            lightID: PreviewThemeCatalog.defaultLightID,
            darkID: PreviewThemeCatalog.defaultDarkID,
            colorScheme: .light
        )
        let rendered = SyntaxHighlighter.shared.highlight(
            code: "let value = 42",
            language: "swift",
            font: selectedFont,
            theme: theme
        )
        let renderedFont = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        XCTAssertEqual(renderedFont.familyName, selectedFont.familyName)
    }
}
