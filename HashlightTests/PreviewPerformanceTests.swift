import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Hashlight

nonisolated final class PreviewPerformanceTests: XCTestCase {
    @MainActor
    func testImageCostUsesPixelRowsRatherThanLogicalPointSize() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 320, bitsPerPixel: 32))
        bitmap.size = NSSize(width: 32, height: 16)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        XCTAssertEqual(PreviewImage.decodedByteCost(image), 320 * 32)
    }

    @MainActor
    func testThumbnailPreservesNaturalSizeWhileReducingDecodedPixels() throws {
        let data = try imageData(width: 1200, height: 600)
        let original = try XCTUnwrap(NSImage(data: data))
        let thumbnail = try XCTUnwrap(PreviewImage.load(data: data, maximumPixelWidth: 200))
        let bitmap = try XCTUnwrap(thumbnail.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(thumbnail.size.width, original.size.width, accuracy: 0.1)
        XCTAssertEqual(thumbnail.size.height, original.size.height, accuracy: 0.1)
        XCTAssertEqual(bitmap.pixelsWide, 200)
        XCTAssertEqual(bitmap.pixelsHigh, 100)
        XCTAssertLessThan(PreviewImage.decodedByteCost(thumbnail), 100_000)

        let full = try XCTUnwrap(PreviewImage.load(data: data, maximumPixelWidth: nil))
        XCTAssertEqual(full.representations.first?.pixelsWide, 1200, "Full width retains the original resolution")
    }

    @MainActor
    func testThumbnailHonorsOrientationAndDensityWithoutUpscaling() throws {
        let data = try imageData(width: 120, height: 60, properties: [
            kCGImagePropertyOrientation: 6, kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144
        ])
        let image = try XCTUnwrap(PreviewImage.load(data: data, maximumPixelWidth: 300))
        let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(bitmap.pixelsWide, 60)
        XCTAssertEqual(bitmap.pixelsHigh, 120)
        XCTAssertEqual(image.size.width, 30, accuracy: 0.1)
        XCTAssertEqual(image.size.height, 60, accuracy: 0.1)
    }

    @MainActor
    func testAnimatedImagesKeepTheirFrames() throws {
        let data = try imageData(width: 32, height: 16, type: UTType.gif.identifier as CFString, frames: 2)
        let image = try XCTUnwrap(PreviewImage.load(data: data, maximumPixelWidth: 8))
        let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual((bitmap.value(forProperty: .frameCount) as? NSNumber)?.intValue, 2)
    }

    @MainActor
    func testCompletedImagesSurviveEvictionAndAreReleasedWithTheirAttachments() throws {
        let resources = PreviewImageResources()
        let cache = NSCache<NSString, NSImage>()
        resources.prepare(documentId: UUID(), content: "image", style: "light")
        weak var releasedImage: NSImage?
        try autoreleasepool {
            let image = try XCTUnwrap(PreviewImage.load(data: imageData(width: 32, height: 16), maximumPixelWidth: 32))
            releasedImage = image
            resources.insert(image, forKey: "key", generation: resources.generation)
            cache.removeAllObjects()
            XCTAssertTrue(resources.image(forKey: "key", cache: cache) === image)
            XCTAssertTrue(resources.image(forKey: "key", cache: cache) === image)
        }
        XCTAssertNil(releasedImage, "The consumed-resource index must not pin an unused decoded bitmap")
        XCTAssertNil(resources.image(forKey: "key", cache: cache))
    }

    @MainActor
    func testObsoleteImageCompletionsCannotPopulateANewDocument() {
        let resources = PreviewImageResources()
        let cache = NSCache<NSString, NSImage>()
        resources.prepare(documentId: UUID(), content: "first", style: "light")
        let generation = resources.generation
        resources.prepare(documentId: UUID(), content: "second", style: "light")
        resources.insert(NSImage(size: NSSize(width: 10, height: 10)), forKey: "old", generation: generation)
        XCTAssertNil(resources.image(forKey: "old", cache: cache))
    }

    @MainActor
    func testReloadPreservesSelectionAndSearchAndClampsAfterTruncation() {
        let harness = NativePreviewHarness()
        harness.render("# Heading\n\nKeep this selection.\n", search: "selection")
        let selected = (harness.textView.string as NSString).range(of: "selection")
        harness.textView.setSelectedRange(selected)
        harness.render("# Heading\n\nKeep this selection.\n\nMore text.", search: "selection")
        XCTAssertEqual(harness.textView.selectedRange(), selected)
        XCTAssertEqual(harness.coordinator.matchRanges, [selected])
        XCTAssertNotNil(harness.textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: selected.location, effectiveRange: nil))

        harness.render("Short")
        XCTAssertLessThanOrEqual(NSMaxRange(harness.textView.selectedRange()), harness.textView.string.utf16.count)
        XCTAssertTrue(harness.coordinator.matchRanges.isEmpty)
    }

    @MainActor
    func testDiagramAttachmentSurvivesSharedCacheEviction() throws {
        let harness = NativePreviewHarness()
        let code = "graph TD; A-->B;"
        let key = "mermaid-\(harness.theme.cacheKey)-" + code
        let image = try XCTUnwrap(PreviewImage.load(data: imageData(width: 100, height: 50), maximumPixelWidth: 100))
        let cache = MarkdownTextView.Coordinator.diagramCache
        cache.setObject(image, forKey: key as NSString, cost: PreviewImage.decodedByteCost(image))
        defer { cache.removeObject(forKey: key as NSString) }
        harness.render("```mermaid\n\(code)\n```")
        cache.removeObject(forKey: key as NSString)
        harness.render("```mermaid\n\(code)\n```")
        XCTAssertFalse(harness.textView.string.contains("Rendering"))
        let storage = try XCTUnwrap(harness.textView.textStorage)
        var images: [NSImage] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let image = (value as? NSTextAttachment)?.image { images.append(image) }
        }
        XCTAssertEqual(images.count, 1)
        XCTAssertTrue(images.first === image, "Sizing a diagram should reuse its decoded backing")
    }

    @MainActor
    func testTableFramesInvalidateAfterResizeTextAndAttributeChanges() throws {
        let harness = NativePreviewHarness()
        let source = "| Name | Description |\n| --- | --- |\n| Item | A long description that wraps over several lines in a narrow table column. |\n"
        harness.render(source)
        _ = try backgrounds(harness)
        harness.textView.setFrameSize(NSSize(width: 430, height: 600))
        try assertBackgroundMatchesFreshLayout(harness)

        let storage = try XCTUnwrap(harness.textView.textStorage)
        storage.insert(NSAttributedString(string: "A new paragraph above the table.\n", attributes: [.font: NSFont.systemFont(ofSize: 16)]), at: 0)
        try assertBackgroundMatchesFreshLayout(harness)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 24), range: NSRange(location: 0, length: storage.length))
        try assertBackgroundMatchesFreshLayout(harness)
    }

    @MainActor
    func testRepeatedTablePayloadsHaveDistinctCachedFrames() throws {
        let harness = NativePreviewHarness()
        harness.render("| A | B |\n| --- | --- |\n| One | Two |\n\nBetween tables.\n\n| C | D |\n| --- | --- |\n| Three | Four |\n")
        let storage = try XCTUnwrap(harness.textView.textStorage)
        var ranges: [NSRange] = []
        storage.enumerateAttribute(PreviewTextView.tableKey, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value is TablePayload { ranges.append(range) }
        }
        XCTAssertEqual(ranges.count, 2)
        let shared = TablePayload(borderColor: harness.theme.selectionColor)
        for range in ranges { storage.addAttribute(PreviewTextView.tableKey, value: shared, range: range) }
        let repeated = try backgrounds(harness)
        storage.addAttribute(PreviewTextView.tableKey, value: TablePayload(borderColor: harness.theme.selectionColor), range: ranges[1])
        XCTAssertEqual(repeated, try backgrounds(harness))
    }

    @MainActor
    func testInlineLineBreakFastPathKeepsUnicode() {
        XCTAssertEqual(InlineMarkdown.tokenize("café<BR />日本語 `a<br>b`"), [.text("café"), .lineBreak, .text("日本語 "), .code("a<br>b")])
    }

    @MainActor
    func testTableColumnsAreContentSizedUnlessCategoriesAreSupplied() throws {
        let source = "| ID | Name | Description |\n| --- | --- | --- |\n| 1 | en0 | A long description of the first item. |\n"
        func headerBlocks(_ configuration: MarkdownTableColumnConfiguration?) throws -> [NSTextTableBlock] {
            let harness = NativePreviewHarness()
            harness.render(source, tableColumnConfiguration: configuration)
            return try tableBlocks(harness).filter { $0.startingRow == 0 }
        }

        let sized = try headerBlocks(nil)
        XCTAssertEqual(sized.count, 3)
        XCTAssertTrue(sized.allSatisfy { $0.contentWidthValueType == .absoluteValueType })
        let sizedWidths = sized.map(\.contentWidth)
        XCTAssertGreaterThan(sizedWidths[2], sizedWidths[1])
        XCTAssertLessThan(sizedWidths.reduce(0, +) + 3 * PreviewTableLayout.cellChrome, 940, "a small table shrinks to its content")

        let weighted = try headerBlocks(.defaults)
        XCTAssertTrue(weighted.allSatisfy { $0.contentWidthValueType == .percentageValueType })
        XCTAssertEqual(weighted.map(\.contentWidth), MarkdownTableColumnLayout.widthPercentages(
            for: [["ID", "Name", "Description"], ["1", "en0", "A long description of the first item."]],
            configuration: .defaults
        ))
    }

    @MainActor
    func testACellAtItsNaturalWidthKeepsItsTextOnOneLine() throws {
        let harness = NativePreviewHarness()
        harness.render("| Operational State | VLAN | MAC Address |\n| --- | --- | --- |\n| Up | 1234 | `aa:bb:cc:dd:ee:ff` |\n")
        let storage = try XCTUnwrap(harness.textView.textStorage)
        let manager = try XCTUnwrap(harness.textView.layoutManager)
        manager.ensureLayout(for: try XCTUnwrap(harness.textView.textContainer))
        for text in ["Operational State", "aa:bb:cc:dd:ee:ff"] {
            let range = (storage.string as NSString).range(of: text)
            var lines = 0
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)) { _, _, _, _, _ in lines += 1 }
            XCTAssertEqual(lines, 1, "\(text) should fit its column")
        }
    }

    @MainActor
    func testAResizeRefitsContentSizedTablesWithoutARebuild() throws {
        let harness = NativePreviewHarness()
        harness.render("| Name | Description |\n| --- | --- |\n| Item | \(String(repeating: "A long description that wraps. ", count: 12)) |\n")
        let storage = try XCTUnwrap(harness.textView.textStorage)
        let wide = try tableBlocks(harness).filter { $0.startingRow == 0 }.map(\.contentWidth)
        let container = try XCTUnwrap(harness.textView.textContainer)
        XCTAssertEqual(wide.reduce(0, +) + 2 * PreviewTableLayout.cellChrome, container.containerSize.width - 2 * container.lineFragmentPadding, accuracy: 0.5)

        let before = storage.string
        harness.textView.setFrameSize(NSSize(width: 500, height: 700))
        let narrow = try tableBlocks(harness).filter { $0.startingRow == 0 }.map(\.contentWidth)
        XCTAssertEqual(storage.string, before)
        XCTAssertEqual(narrow.reduce(0, +) + 2 * PreviewTableLayout.cellChrome, container.containerSize.width - 2 * container.lineFragmentPadding, accuracy: 0.5)
        XCTAssertLessThan(narrow[1], wide[1])
        XCTAssertEqual(narrow[0], wide[0], accuracy: 0.01, "the short column keeps its natural width")

        harness.textView.setFrameSize(NSSize(width: 1000, height: 700))
        let restored = try tableBlocks(harness).filter { $0.startingRow == 0 }.map(\.contentWidth)
        XCTAssertEqual(restored, wide, "widening again restores the fresh build's widths")

        // Built while narrow (a theme change in a small window), then widened.
        let builtNarrow = NativePreviewHarness()
        builtNarrow.textView.setFrameSize(NSSize(width: 500, height: 700))
        builtNarrow.render("| Name | Description |\n| --- | --- |\n| Item | \(String(repeating: "A long description that wraps. ", count: 12)) |\n")
        builtNarrow.textView.setFrameSize(NSSize(width: 1000, height: 700))
        XCTAssertEqual(try tableBlocks(builtNarrow).filter { $0.startingRow == 0 }.map(\.contentWidth), wide)
    }

    @MainActor
    func testDelimiterRowAlignmentReachesTheCells() throws {
        let harness = NativePreviewHarness()
        harness.render("| Left | Centre | Right | Default |\n|:--|:-:|--:|---|\n| one | two | three | four |\n")
        let storage = try XCTUnwrap(harness.textView.textStorage)
        func alignment(of text: String) -> NSTextAlignment? {
            let location = (storage.string as NSString).range(of: text).location
            return (storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.alignment
        }
        XCTAssertEqual(alignment(of: "Centre"), .center)
        XCTAssertEqual(alignment(of: "two"), .center)
        XCTAssertEqual(alignment(of: "Right"), .right)
        XCTAssertEqual(alignment(of: "three"), .right)
        XCTAssertEqual(alignment(of: "one"), .left)
        XCTAssertEqual(alignment(of: "four"), .natural)
    }

    @MainActor
    func testCellMeasurementFindsTheWidestLineAndLongestWord() {
        let font = NSFont.systemFont(ofSize: 16)
        let cell = NSAttributedString(string: "Short line\nA wider extraordinary line ", attributes: [.font: font])
        let size = PreviewTableLayout.measure(cell)
        let widest = NSAttributedString(string: "A wider extraordinary line", attributes: [.font: font]).size().width
        let word = NSAttributedString(string: "extraordinary", attributes: [.font: font]).size().width
        XCTAssertEqual(size.natural, widest, accuracy: 0.5)
        XCTAssertEqual(size.longestWord, word, accuracy: 0.5)
    }

    @MainActor
    func testFontSizeSettingsScaleMainAndFixedTextSeparately() throws {
        let source = "# Title\n\nBody with `inline` code.\n\n```\nlet block = 1\n```\n"
        let harness = NativePreviewHarness()
        func size(of text: String) throws -> CGFloat {
            let storage = try XCTUnwrap(harness.textView.textStorage)
            let location = (storage.string as NSString).range(of: text).location
            XCTAssertNotEqual(location, NSNotFound, text)
            return try XCTUnwrap(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont).pointSize
        }

        harness.render(source)
        XCTAssertEqual(try size(of: "Body"), 16, accuracy: 0.01)
        XCTAssertEqual(try size(of: "Title"), 28, accuracy: 0.01)
        XCTAssertEqual(try size(of: "inline"), 15, accuracy: 0.01, "inline code is a point below its text")
        XCTAssertEqual(try size(of: "let block"), 13, accuracy: 0.01)

        // Same document and content: the sizes are part of the style key, so nothing cached is reused.
        harness.render(source, mainFontSize: 20)
        XCTAssertEqual(try size(of: "Body"), 20, accuracy: 0.01)
        XCTAssertEqual(try size(of: "Title"), 35, accuracy: 0.01, "headings keep their ratio to the body")
        XCTAssertEqual(try size(of: "inline"), 18.75, accuracy: 0.01)
        XCTAssertEqual(try size(of: "let block"), 13, accuracy: 0.01, "the main size leaves code blocks alone")

        harness.render(source, mainFontSize: 20, fixedFontSize: 15.6)
        XCTAssertEqual(try size(of: "Body"), 20, accuracy: 0.01)
        XCTAssertEqual(try size(of: "let block"), 15.6, accuracy: 0.01)
        XCTAssertEqual(try size(of: "inline"), 18.75, accuracy: 0.01, "inline code follows its text, not the code-block size")
    }

    @MainActor
    private func tableBlocks(_ harness: NativePreviewHarness) throws -> [NSTextTableBlock] {
        let storage = try XCTUnwrap(harness.textView.textStorage)
        var blocks: [NSTextTableBlock] = []
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let block = (value as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock,
                  !blocks.contains(where: { $0 === block }) else { return }
            blocks.append(block)
        }
        return blocks
    }

    @MainActor
    private func assertBackgroundMatchesFreshLayout(_ harness: NativePreviewHarness) throws {
        let cached = try backgrounds(harness)
        let manager = try XCTUnwrap(harness.textView.layoutManager)
        manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: harness.textView.string.utf16.count), actualCharacterRange: nil)
        XCTAssertEqual(cached, try backgrounds(harness), "Invalidation must produce the same table geometry as fresh layout")
    }

    @MainActor
    private func backgrounds(_ harness: NativePreviewHarness) throws -> Data {
        let manager = try XCTUnwrap(harness.textView.layoutManager)
        let container = try XCTUnwrap(harness.textView.textContainer)
        manager.ensureLayout(for: container)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4000, bitsPerPixel: 32))
        memset(bitmap.bitmapData!, 0, bitmap.bytesPerRow * bitmap.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        defer { NSGraphicsContext.restoreGraphicsState() }
        let glyphs = manager.glyphRange(forBoundingRect: NSRect(x: 0, y: 0, width: 1000, height: 700), in: container)
        manager.drawBackground(forGlyphRange: glyphs, at: NSPoint(x: 24, y: 40))
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    @MainActor
    private func imageData(width: Int, height: Int, properties: [CFString: Any] = [:], type: CFString = UTType.png.identifier as CFString, frames: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type, frames, nil))
        for _ in 0..<frames { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

@MainActor
private final class NativePreviewHarness {
    let scrollView: NSScrollView
    let textView: PreviewTextView
    let coordinator = MarkdownTextView.Coordinator()
    let documentId = UUID()
    let theme = PreviewTheme.system(dark: false)

    init() {
        scrollView = PreviewTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        textView = scrollView.documentView as! PreviewTextView
        _ = textView.layoutManager
        textView.textContainer?.replaceLayoutManager(PreviewLayoutManager())
        textView.textContainerInset = NSSize(width: 24, height: 40)
        textView.textContainer?.widthTracksTextView = false
        textView.preferredColumnWidth = SettingsManager.ContentWidth.medium.points
        textView.setFrameSize(NSSize(width: 1000, height: 700))
        textView.isEditable = false
        textView.isSelectable = true
        coordinator.documentId = documentId
        coordinator.textView = textView
        coordinator.scrollView = scrollView
    }

    func render(
        _ content: String,
        search: String = "",
        tableColumnConfiguration: MarkdownTableColumnConfiguration? = nil,
        mainFontSize: CGFloat = 16,
        fixedFontSize: CGFloat = 13
    ) {
        let parent = MarkdownTextView(content: content, baseURL: nil, documentId: documentId,
                                      scrollToHeadingId: .constant(nil), searchText: search, currentMatchIndex: 0,
                                      mainFontID: PreviewFontCatalog.systemMainID,
                                      fixedFontID: PreviewFontCatalog.systemFixedID,
                                      mainFontSize: mainFontSize, fixedFontSize: fixedFontSize, theme: theme,
                                      tableColumnConfiguration: tableColumnConfiguration)
        coordinator.scheduleRebuild(for: parent, textView: textView, scrollView: scrollView, contentChanged: false, isReload: false)
    }
}
