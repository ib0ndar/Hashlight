import SwiftUI
import XCTest
@testable import Hashlight

nonisolated final class InlineMarkdownTests: XCTestCase {
    @MainActor
    func testCodeSpansAreAtomicBeforeEmphasis() {
        XCTAssertEqual(
            InlineMarkdown.tokenize("`*literal*` **strong**"),
            [.code("*literal*"), .text(" "), .strong("strong")]
        )
    }

    @MainActor
    func testInlineMathIsAtomicBeforeEmphasis() {
        XCTAssertEqual(
            InlineMarkdown.tokenize("value $a * b$ end"),
            [.text("value "), .math("a * b"), .text(" end")]
        )
    }

    @MainActor
    func testMathTokenRejectsCarriageReturnAndLineSeparators() {
        // A \r, U+2028, or U+2029 inside a $...$ span must not be accepted into a
        // .math token — those characters break the single-quoted JS string literal
        // that WebRenderer splices math content into. The tokenizer already rejects
        // literal \n the same way; confirm \r and the Unicode line separators are
        // rejected too. With no other token type able to claim a lone "$", a rejected
        // span falls all the way through to plain buffered text (mirroring how "\n"
        // already behaves today).
        XCTAssertEqual(InlineMarkdown.tokenize("$a\rb$"), [.text("$a\rb$")])
        XCTAssertEqual(InlineMarkdown.tokenize("$a\u{2028}b$"), [.text("$a\u{2028}b$")])
        XCTAssertEqual(InlineMarkdown.tokenize("$a\u{2029}b$"), [.text("$a\u{2029}b$")])

        XCTAssertNil(InlineMarkdown.tokenize("$a\rb$").first { if case .math = $0 { return true } else { return false } })
        XCTAssertNil(InlineMarkdown.tokenize("$a\u{2028}b$").first { if case .math = $0 { return true } else { return false } })
        XCTAssertNil(InlineMarkdown.tokenize("$a\u{2029}b$").first { if case .math = $0 { return true } else { return false } })
    }

    @MainActor
    func testHighlightTokenizesAsDistinctFromEquals() {
        XCTAssertEqual(
            InlineMarkdown.tokenize("==important== and =not= this"),
            [.highlight("important"), .text(" and =not= this")]
        )
    }

    @MainActor
    func testMixedInlineImagePreservesSurroundingTextInHTML() {
        let html = MarkdownParser.shared.toHTML("See ![diagram](diagram.png) for the flow.", includeStyles: false)

        XCTAssertTrue(html.contains("See "))
        XCTAssertTrue(html.contains("<img src=\"diagram.png\" alt=\"diagram\">"))
        XCTAssertTrue(html.contains(" for the flow."))
    }

    @MainActor
    func testInlineImageURLIsEscapedOnce() {
        let html = MarkdownParser.shared.formatInlineHTML("![remote](https://host/img.png?a=1&b=2)")

        XCTAssertTrue(html.contains("src=\"https://host/img.png?a=1&amp;b=2\""))
        XCTAssertFalse(html.contains("&amp;amp;"))
    }

    @MainActor
    func testRawHTMLBlockIsEscapedInExportHTML() {
        let html = MarkdownParser.shared.toHTML("<div/onclick=alert(1)>raw</div>", includeStyles: false)

        XCTAssertTrue(html.contains("&lt;div/onclick=alert(1)&gt;raw&lt;/div&gt;"))
        XCTAssertFalse(html.contains("<div/onclick"))
    }

    @MainActor
    func testMarkdownGeneratedLinkStillEmitsHTML() {
        let html = MarkdownParser.shared.toHTML("[site](https://example.com?a=1&b=2)", includeStyles: false)

        XCTAssertTrue(html.contains("<a href=\"https://example.com?a=1&amp;b=2\">site</a>"))
    }

    @MainActor
    func testObfuscatedJavaScriptLinkIsNeutralized() {
        let html = MarkdownParser.shared.toHTML("[bad](java&#9;script:alert(1))", includeStyles: false)

        XCTAssertTrue(html.contains("<a href=\"#\">bad</a>"))
        XCTAssertFalse(html.contains("java&#9;script"))
    }

    @MainActor
    func testSVGDataImageSourceIsNeutralized() {
        let html = MarkdownParser.shared.toHTML("![bad](data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=)", includeStyles: false)

        XCTAssertTrue(html.contains("<img src=\"#\" alt=\"bad\">"))
        XCTAssertFalse(html.contains("data:image/svg+xml"))
    }

    @MainActor
    func testNestedInlineFormattingInsideLinkLabelRendersInHTML() {
        let html = MarkdownParser.shared.formatInlineHTML("[**bold**](https://example.com)")

        XCTAssertEqual(html, "<a href=\"https://example.com\"><strong>bold</strong></a>")
    }

    @MainActor
    func testLinkInsideStrongFormattingRendersInHTML() {
        let html = MarkdownParser.shared.formatInlineHTML("**[label](https://example.com)**")

        XCTAssertEqual(html, "<strong><a href=\"https://example.com\">label</a></strong>")
    }

    @MainActor
    func testHighlightRendersAsMarkTagInHTML() {
        let html = MarkdownParser.shared.formatInlineHTML("==important==")

        XCTAssertEqual(html, "<mark>important</mark>")
    }

    @MainActor
    func testDOCXHyperlinkURLsUseSameSchemeHardening() {
        XCTAssertEqual(ExportManager.safeDOCXHyperlinkURL("https://example.com?a=1&b=2"), "https://example.com?a=1&b=2")
        XCTAssertNil(ExportManager.safeDOCXHyperlinkURL("javascript:alert(1)"))
        XCTAssertNil(ExportManager.safeDOCXHyperlinkURL("java&#9;script:alert(1)"))
        XCTAssertNil(ExportManager.safeDOCXHyperlinkURL("#fragment"))
    }

    @MainActor
    func testEmphasisSkipsEscapedDelimiter() {
        XCTAssertEqual(
            InlineMarkdown.tokenize("*a\\*b*"),
            [.emphasis("a\\*b")]
        )
    }

    @MainActor
    func testMathExtractionDoesNotReuseUserAuthoredPlaceholderText() {
        let extraction = ExportManager.shared.extractMathFromMarkdown("literal HASHLIGHTMATHPH0HASHLIGHTEND and $x + y$")

        XCTAssertTrue(extraction.modified.contains("literal HASHLIGHTMATHPH0HASHLIGHTEND"))
        XCTAssertEqual(extraction.math.count, 1)
        XCTAssertNotEqual(extraction.placeholder(at: 0), "HASHLIGHTMATHPH0HASHLIGHTEND")
        XCTAssertTrue(extraction.modified.contains(extraction.placeholder(at: 0)))
    }

    @MainActor
    func testReduceMotionDisablesLayoutAnimation() {
        XCTAssertNil(Motion.layoutAnimation(reduceMotion: true))
        XCTAssertNotNil(Motion.layoutAnimation(reduceMotion: false))
    }

    @MainActor
    func testHelpHTMLSupportsDarkAppearance() {
        XCTAssertTrue(HelpHTML.content.contains("color-scheme: light dark"))
        XCTAssertTrue(HelpHTML.content.contains("prefers-color-scheme: dark"))
    }
}

nonisolated final class RuntimeSmokeTests: XCTestCase {
    /// Editors save by writing a temporary file and renaming it over the original, which leaves
    /// the watcher on an orphaned inode unless it re-arms itself.
    @MainActor
    func testFileWatcherReportsEditsAcrossAtomicRenames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashlight-filewatcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("watch.md")
        try "initial".write(to: url, atomically: true, encoding: .utf8)

        let changed = expectation(description: "reports both atomic-rename saves")
        changed.expectedFulfillmentCount = 2
        changed.assertForOverFulfill = false
        let delegate = FileWatcherProbe(expectedURL: url, changed: changed)
        let watcher = FileWatcher(url: url)
        watcher.delegate = delegate
        watcher.startWatching()
        defer { watcher.stopWatching() }

        try "first-edit".write(to: url, atomically: true, encoding: .utf8)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? "second-edit".write(to: url, atomically: true, encoding: .utf8)
        }

        wait(for: [changed], timeout: 4.0)
    }

    @MainActor
    func testExternalChangeReloadsTheOpenDocumentWithoutAPrompt() throws {
        let manager = DocumentManager.shared
        let previousDocuments = manager.openDocuments
        let previousSelectedId = manager.selectedDocumentId

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashlight-reload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("reload.md")
        try "# Before".write(to: url, atomically: true, encoding: .utf8)
        defer {
            if let opened = manager.openDocuments.first(where: { $0.url == url }) {
                manager.closeDocument(opened)
            }
            manager.openDocuments = previousDocuments
            manager.selectedDocumentId = previousSelectedId
            try? FileManager.default.removeItem(at: directory)
        }

        manager.loadDocument(from: url)
        let id = try XCTUnwrap(manager.openDocuments.first(where: { $0.url == url })?.id)

        // Another app saves over the file the way most editors do (write, then rename).
        let changedText = "# After\n\nChanged on disk."
        try changedText.write(to: url, atomically: true, encoding: .utf8)

        // A prompt would block the main thread in NSAlert.runModal, so this poll could never
        // see the reload; the reload landing on its own is the assertion.
        let reloaded = expectation(description: "the open tab picks up the new text")
        var attempts = 0
        func poll() {
            attempts += 1
            if manager.openDocuments.first(where: { $0.id == id })?.content == changedText {
                reloaded.fulfill()
            } else if attempts < 80 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
        wait(for: [reloaded], timeout: 5.0)

        XCTAssertNil(NSApp.modalWindow)
        XCTAssertEqual(manager.openDocuments.filter { $0.url == url }.map(\.id), [id], "reloaded in place, not reopened")
    }

    @MainActor
    func testClosingATabIsImmediate() {
        let manager = DocumentManager.shared
        let previousDocuments = manager.openDocuments
        let previousSelectedId = manager.selectedDocumentId
        defer {
            manager.openDocuments = previousDocuments
            manager.selectedDocumentId = previousSelectedId
        }

        let documentId = UUID()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashlight-close-\(UUID().uuidString).md")
        let document = MarkdownDocument(id: documentId, url: url, content: "text")
        manager.openDocuments = [document]
        manager.selectedDocumentId = documentId

        // Any confirmation would block here in NSAlert.runModal; returning at all is the
        // load-bearing assertion.
        manager.closeDocument(document)

        XCTAssertTrue(manager.openDocuments.isEmpty)
        XCTAssertNil(manager.selectedDocumentId)
    }
}

private final class FileWatcherProbe: FileWatcherDelegate {
    private let expectedURL: URL
    private let changed: XCTestExpectation

    init(expectedURL: URL, changed: XCTestExpectation) {
        self.expectedURL = expectedURL
        self.changed = changed
    }

    func fileWatcher(_ watcher: FileWatcher, fileDidChange url: URL) {
        if url == expectedURL {
            changed.fulfill()
        }
    }

    func fileWatcher(_ watcher: FileWatcher, fileWasDeleted url: URL) {}
}

/// A viewer has nothing to save, so closing the window and quitting never ask.
nonisolated final class CloseWithoutPromptTests: XCTestCase {
    @MainActor
    func testWindowCloseButtonClosesEveryTabImmediately() {
        let manager = DocumentManager.shared
        let previousDocuments = manager.openDocuments
        let previousSelectedId = manager.selectedDocumentId
        defer {
            manager.openDocuments = previousDocuments
            manager.selectedDocumentId = previousSelectedId
        }

        let tmp = FileManager.default.temporaryDirectory
        let docA = MarkdownDocument(url: tmp.appendingPathComponent("window-a-\(UUID().uuidString).md"), content: "a")
        let docB = MarkdownDocument(url: tmp.appendingPathComponent("window-b-\(UUID().uuidString).md"), content: "b")
        manager.openDocuments = [docA, docB]
        manager.selectedDocumentId = docA.id

        let delegate = WindowCloseDelegate()
        delegate.documentManager = manager
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)

        XCTAssertTrue(delegate.windowShouldClose(window), "the window closes at once")
        XCTAssertTrue(manager.openDocuments.isEmpty)
        XCTAssertNil(manager.selectedDocumentId)
    }

    @MainActor
    func testQuitIsNeverHeldUp() {
        // applicationShouldTerminate(_:) is the only hook that can delay or cancel Quit; without
        // it AppKit terminates immediately.
        XCTAssertFalse(AppDelegate().responds(to: #selector(NSApplicationDelegate.applicationShouldTerminate(_:))))
    }
}

/// Finder, the Dock, `open`, and AppleScript all send an "open documents" Apple Event. Once the
/// main window has appeared, OpenDocumentsEvents handles it: it opens the Markdown files, for a
/// single file as well as a list, and replies at once.
nonisolated final class OpenDocumentsEventTests: XCTestCase {
    @MainActor
    func testASingleFileOpens() throws {
        // AppleScript's `open POSIX file …` sends one file rather than a list. The handler
        // inherited from zMD trapped on it: `1...numberOfItems` with zero items.
        let files = try makeFiles(["single.md"])
        try assertOpenDocumentsEvent(NSAppleEventDescriptor(fileURL: files[0]), opens: files)
    }

    @MainActor
    func testAListOpensItsMarkdownFilesInOrder() throws {
        let files = try makeFiles(["Upper.MD", "notes.txt", "long.markdown"])
        let list = NSAppleEventDescriptor.list()
        for (index, url) in files.enumerated() {
            list.insert(NSAppleEventDescriptor(fileURL: url), at: index + 1)
        }
        try assertOpenDocumentsEvent(list, opens: [files[0], files[2]])
    }

    @MainActor
    func testFileURLsReadEveryFormSendersUse() throws {
        let files = try makeFiles(["one.md", "two.md"])
        let bookmark = try XCTUnwrap(NSAppleEventDescriptor(
            descriptorType: DescType(typeBookmarkData), data: try files[1].bookmarkData()
        ))
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(fileURL: files[0]), at: 1)
        list.insert(bookmark, at: 2)

        func paths(_ directObject: NSAppleEventDescriptor?) -> [String] {
            OpenDocumentsEvents.fileURLs(in: directObject).map { $0.resolvingSymlinksInPath().path }
        }
        let expected = files.map { $0.resolvingSymlinksInPath().path }
        XCTAssertEqual(paths(list), expected, "a file URL (AppleScript) and a bookmark (Finder, open)")
        XCTAssertEqual(paths(NSAppleEventDescriptor(fileURL: files[0])), [expected[0]], "one file, not in a list")
        XCTAssertEqual(paths(bookmark), [expected[1]], "one bookmark, not in a list")
        XCTAssertEqual(paths(NSAppleEventDescriptor.list()), [], "an empty list")
        XCTAssertEqual(paths(nil), [], "no direct object")
    }

    @MainActor
    func testAnEventReopensTheClosedMainWindow() throws {
        // SwiftUI no longer sees these events, so once the window is closed it is DocumentManager
        // that has to bring it back, through the opener the window registered.
        func mainWindow() -> NSWindow? {
            NSApp.windows.first { $0.identifier?.rawValue == "main" && $0.isVisible }
        }
        let manager = DocumentManager.shared
        if mainWindow() == nil {
            manager.showMainWindow()
        }
        waitUntil("the host's main window is open") { mainWindow() != nil }
        let window = try XCTUnwrap(mainWindow(), "windows: \(NSApp.windows.map { "\($0.identifier?.rawValue ?? "-") visible=\($0.isVisible)" })")
        let previousDocuments = manager.openDocuments
        let previousSelectedId = manager.selectedDocumentId
        defer {
            manager.openDocuments = previousDocuments
            manager.selectedDocumentId = previousSelectedId
            if mainWindow() == nil {
                manager.showMainWindow()
            }
        }

        window.performClose(nil)
        waitUntil("the main window closes") { mainWindow() == nil }

        let files = try makeFiles(["reopen.md"])
        try assertOpenDocumentsEvent(NSAppleEventDescriptor(fileURL: files[0]), opens: files) {
            self.waitUntil("the main window reopens") { mainWindow() != nil }
        }
    }

    @MainActor
    private func makeFiles(_ names: [String]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashlight-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try names.map { name in
            let url = directory.appendingPathComponent(name)
            try "# \(name)".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    /// Sends this process an "open documents" event and waits for `expected` to open as the
    /// newest tabs, in order; `whileOpen` runs before they close again. Puts the tabs and the
    /// recent files back afterwards.
    @MainActor
    private func assertOpenDocumentsEvent(_ directObject: NSAppleEventDescriptor, opens expected: [URL],
                                          whileOpen: () throws -> Void = {}) throws {
        let manager = DocumentManager.shared
        let previousDocuments = manager.openDocuments
        let previousSelectedId = manager.selectedDocumentId
        let previousRecentFiles = manager.recentFileURLs
        let previousRecentData = UserDefaults.standard.array(forKey: DefaultsKeys.recentFiles)
        let previousIds = Set(previousDocuments.map(\.id))
        defer {
            for document in manager.openDocuments where !previousIds.contains(document.id) {
                manager.closeDocument(document)
            }
            manager.openDocuments = previousDocuments
            manager.selectedDocumentId = previousSelectedId
            manager.recentFileURLs = previousRecentFiles
            UserDefaults.standard.set(previousRecentData, forKey: DefaultsKeys.recentFiles)
        }

        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenDocuments),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(directObject, forKeyword: AEKeyword(keyDirectObject))
        // The sender waits for the reply. AppKit's own handler held it until the app could come
        // to the front, so a script's `open` timed out whenever Hashlight stayed behind. The
        // host's window may not have appeared yet, so take the events over here.
        OpenDocumentsEvents.shared.takeOver()
        try event.sendEvent(options: [.waitForReply], timeout: 5)

        func path(_ url: URL) -> String { url.resolvingSymlinksInPath().path }
        let expectedPaths = expected.map(path)
        func openedPaths() -> [String] {
            manager.openDocuments.filter { !previousIds.contains($0.id) }.map { path($0.url) }
        }

        waitUntil("the event's Markdown files open as tabs") { openedPaths() == expectedPaths }
        XCTAssertEqual(openedPaths(), expectedPaths)
        try whileOpen()
    }

    /// Polls `condition` on the main run loop for up to `timeout` seconds.
    @MainActor
    private func waitUntil(_ description: String, timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) {
        let done = expectation(description: description)
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() {
                done.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
        wait(for: [done], timeout: timeout + 1)
    }
}

nonisolated final class FolderManagerTests: XCTestCase {
    @MainActor
    func testFolderScanDoesNotRecurseIntoSymlinkCycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashlight-symlink-cycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A real markdown file so the folder isn't filtered out as empty.
        try "hello".write(to: root.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        // A directory symlink pointing back at `root` itself — the simplest cycle.
        let cycleLink = root.appendingPathComponent("loop")
        try FileManager.default.createSymbolicLink(at: cycleLink, withDestinationURL: root)

        // FolderManager's initializer is private (singleton), so drive this through
        // .shared and restore its state afterward, matching the RuntimeSmokeTests pattern
        // above for DocumentManager.shared.
        let manager = FolderManager.shared
        let previousFolderURL = manager.folderURL
        let previousFileTree = manager.fileTree

        defer {
            manager.closeFolder()
            manager.folderURL = previousFolderURL
            manager.fileTree = previousFileTree
        }

        let done = expectation(description: "tree scan completes without crashing")

        // setFolder dispatches the scan async and publishes fileTree on main;
        // poll briefly rather than relying on a Combine subscription to keep this
        // test dependency-free.
        manager.setFolder(root)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            done.fulfill()
        }
        wait(for: [done], timeout: 3.0)

        // Reaching here without a crash/timeout is the primary assertion. Also
        // confirm the real file surfaced and the cyclic symlink did not appear
        // as a nested directory entry.
        XCTAssertTrue(manager.fileTree.contains { $0.name == "note.md" })
        XCTAssertFalse(manager.fileTree.contains { $0.name == "loop" })
    }
}

/// Placement math for the preview's left/center/right text-column alignment
/// (`PreviewTextView.containerOriginX`). Column 800pt, margin 50pt — the app's real values.
nonisolated final class ContentAlignmentTests: XCTestCase {
    private func originX(_ alignment: SettingsManager.ContentAlignment, viewWidth: CGFloat) -> CGFloat {
        PreviewTextView.containerOriginX(alignment: alignment, viewWidth: viewWidth, containerWidth: 800, inset: 50)
    }

    func testWidePanePlacesColumnLeftCenterRight() {
        // 1500 wide → 600pt of free space beyond column + both margins.
        XCTAssertEqual(originX(.left, viewWidth: 1500), 50)
        XCTAssertEqual(originX(.center, viewWidth: 1500), 350)   // equal space on both sides
        XCTAssertEqual(originX(.right, viewWidth: 1500), 650)    // right margin stays exactly 50
        XCTAssertEqual(1500 - (originX(.right, viewWidth: 1500) + 800), 50)
    }

    func testNarrowPaneCollapsesEveryAlignmentToTheLeftMargin() {
        // No free space (split panes, Focus Mode's 720pt column): the column must never be
        // pushed off-screen or lose its leading margin, whatever the setting.
        for width in [300, 720, 899, 900] as [CGFloat] {
            for alignment in SettingsManager.ContentAlignment.allCases {
                XCTAssertEqual(originX(alignment, viewWidth: width), 50, "\(alignment) at \(width)")
            }
        }
    }

    func testCenteringIsContinuousAsThePaneGrows() {
        // Just past the threshold the column should nudge, not jump.
        XCTAssertEqual(originX(.center, viewWidth: 902), 51)
        XCTAssertEqual(originX(.right, viewWidth: 902), 52)
    }
}

/// Column-width math for the Content Width setting (`PreviewTextView.columnWidth`).
nonisolated final class ContentWidthTests: XCTestCase {
    func testColumnNeverExceedsThePane() {
        // Regression: the column was a hard 800pt, so a 720pt pane (Focus Mode) laid text out
        // to x=847 and silently clipped ~127pt off the right edge of every line.
        XCTAssertEqual(PreviewTextView.columnWidth(preferred: 800, viewWidth: 720, inset: 50), 620)
        XCTAssertEqual(PreviewTextView.columnWidth(preferred: 1000, viewWidth: 600, inset: 50), 500)
    }

    func testColumnStopsGrowingAtTheSetting() {
        XCTAssertEqual(PreviewTextView.columnWidth(preferred: 640, viewWidth: 2000, inset: 50), 640)
        XCTAssertEqual(PreviewTextView.columnWidth(preferred: 800, viewWidth: 900, inset: 50), 800)
    }

    func testFullTracksThePane() {
        XCTAssertEqual(PreviewTextView.columnWidth(preferred: nil, viewWidth: 1500, inset: 50), 1400)
    }

    func testUnsizedViewUsesThePreferredWidthAndTinyPanesKeepAFloor() {
        XCTAssertEqual(PreviewTextView.columnWidth(preferred: 800, viewWidth: 0, inset: 50), 800)
        XCTAssertEqual(PreviewTextView.columnWidth(preferred: 800, viewWidth: 120, inset: 50), 200)
    }

    /// The viewport's top edge after a reflow, from its offset into the anchor's line fragment.
    func testReadingAnchorScalesWithinItsFragmentAndKeepsOtherOffsets() {
        // Halfway down a 645 pt image that is now 495 pt tall at y = 1000: still halfway down.
        let image = NSRect(x: 0, y: 1000, width: 660, height: 495)
        XCTAssertEqual(PreviewTextView.anchoredTop(offset: 322.5, fragmentHeight: 645, newFragment: image), 1247.5)
        // A line of prose that moved but kept its height keeps the exact offset.
        let line = NSRect(x: 0, y: 300, width: 700, height: 24)
        XCTAssertEqual(PreviewTextView.anchoredTop(offset: 10, fragmentHeight: 24, newFragment: line), 310)
        // Above the first line (the top inset) and below a short table cell: kept as is.
        XCTAssertEqual(PreviewTextView.anchoredTop(offset: -40, fragmentHeight: 24, newFragment: line), 260)
        XCTAssertEqual(PreviewTextView.anchoredTop(offset: 60, fragmentHeight: 24, newFragment: line), 360)
    }

    /// End-to-end against the real view, reproducing the original bug's exact geometry.
    @MainActor
    func testTextIsNotClippedInAFocusModeWidthPane() throws {
        let scrollView = PreviewTextView.scrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? PreviewTextView)
        textView.textContainerInset = NSSize(width: 50, height: 40)
        textView.textContainer?.widthTracksTextView = false
        scrollView.frame = NSRect(x: 0, y: 0, width: 720, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        textView.string = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 40)

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let textRightEdge = textView.textContainerOrigin.x + layoutManager.usedRect(for: container).maxX

        XCTAssertLessThanOrEqual(textRightEdge, textView.frame.width, "text runs past the pane's right edge")
        XCTAssertGreaterThan(textRightEdge, 500, "sanity: text should still use most of the column")
    }

    @MainActor
    func testPresetsUseReaderOrientedWidthsAndFullHasNoAttachmentCap() {
        XCTAssertEqual(SettingsManager.ContentWidth.narrow.points, 760)
        XCTAssertEqual(SettingsManager.ContentWidth.medium.points, 960)
        XCTAssertEqual(SettingsManager.ContentWidth.wide.points, 1300)
        XCTAssertNil(SettingsManager.ContentWidth.full.points)
        XCTAssertEqual(SettingsManager.ContentWidth.medium.attachmentMaxWidth, 860)
        XCTAssertNil(SettingsManager.ContentWidth.full.attachmentMaxWidth)
        XCTAssertEqual(SettingsManager.ContentWidth.full.displayName, "Full")
    }
}

nonisolated final class PageMarginTests: XCTestCase {
    @MainActor
    func testMarginsProvideReaderOrientedHorizontalInsetsAndPersist() {
        XCTAssertEqual(SettingsManager.PageMargin.compact.points, 16)
        XCTAssertEqual(SettingsManager.PageMargin.normal.points, 24)
        XCTAssertEqual(SettingsManager.PageMargin.comfortable.points, 40)

        let settings = SettingsManager.shared
        let previous = settings.pageMargin
        defer { settings.pageMargin = previous }

        settings.pageMargin = .compact
        XCTAssertEqual(UserDefaults.standard.string(forKey: DefaultsKeys.pageMargin), "Compact")
    }
}

/// Code-block copy: drives PreviewTextView's real hit-testing through an off-screen window.
nonisolated final class CodeBlockCopyTests: XCTestCase {
    @MainActor
    func testRightClickInsideACodeBlockCopiesTheRawSourceNotTheRenderedBorders() throws {
        let scrollView = PreviewTextView.scrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? PreviewTextView)
        // Never ordered front, so nothing appears on screen.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = scrollView
        scrollView.layoutSubtreeIfNeeded()

        // The rendered text is the code itself; the payload carries the clean source.
        let text = NSMutableAttributedString(string: "Intro paragraph\n")
        let blockStart = text.length
        text.append(NSAttributedString(string: "let x = 1\nlet y = 2\n"))
        text.addAttribute(PreviewTextView.codeBlockKey,
                          value: CodeBlockPayload(code: "let x = 1\nlet y = 2"),
                          range: NSRange(location: blockStart, length: text.length - blockStart))
        text.append(NSAttributedString(string: "Outro paragraph\n"))
        textView.textStorage?.setAttributedString(text)

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: container)

        // Private pasteboard: the suite must never clobber the user's real clipboard.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("Hashlight.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        textView.pasteboard = pasteboard

        func rightClick(atCharacter index: Int, xOffset: CGFloat) throws -> NSMenu? {
            let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            let origin = textView.textContainerOrigin
            let pointInView = NSPoint(x: origin.x + xOffset, y: origin.y + rect.midY)
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .rightMouseDown, location: textView.convert(pointInView, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            return textView.menu(for: event)
        }

        // Far to the right of a short code line still counts as "in the block".
        let blockMenu = try XCTUnwrap(try rightClick(atCharacter: blockStart + 4, xOffset: 400))
        let copyItem = try XCTUnwrap(blockMenu.items.first)
        XCTAssertEqual(copyItem.title, "Copy Code Block")
        _ = textView.perform(try XCTUnwrap(copyItem.action), with: copyItem)
        XCTAssertEqual(pasteboard.string(forType: .string), "let x = 1\nlet y = 2")

        // Outside any block: no code item offered.
        let proseMenu = try rightClick(atCharacter: 2, xOffset: 10)
        XCTAssertNotEqual(proseMenu?.items.first?.title, "Copy Code Block")
    }
}

/// The selected document's preview, re-rendered whenever DocumentManager publishes — the way
/// NormalContentView hosts it in the app.
private struct SelectedDocumentPreview: View {
    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        if let document = documentManager.openDocuments.first(where: { $0.id == documentManager.selectedDocumentId }) {
            DocumentViewModeContent(document: document, selectedHeadingId: .constant(nil))
        }
    }
}

/// Hosts the app's real preview (DocumentViewModeContent → MarkdownTextView) for
/// DocumentManager.shared's selected document in a window that is never ordered front.
private final class PreviewHarness {
    let window: NSWindow
    let hostingView: NSView

    init() {
        hostingView = NSHostingView(rootView: SelectedDocumentPreview()
            .environmentObject(DocumentManager.shared)
            .environmentObject(SettingsManager.shared))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                          styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
    }

    var textView: PreviewTextView? { Self.previewTextView(in: hostingView) }

    private static func previewTextView(in view: NSView) -> PreviewTextView? {
        if let textView = view as? PreviewTextView { return textView }
        for subview in view.subviews {
            if let found = previewTextView(in: subview) { return found }
        }
        return nil
    }
}

nonisolated final class PreviewBehaviorTests: XCTestCase {
    /// Returns a closure that puts DocumentManager.shared back the way this test found it.
    @MainActor
    private func preserveDocumentState() -> () -> Void {
        let manager = DocumentManager.shared
        let documents = manager.openDocuments
        let selection = manager.selectedDocumentId
        return {
            manager.endSearch()
            manager.openDocuments = documents
            manager.selectedDocumentId = selection
        }
    }

    /// Turns the frontmatter setting on for the test (the host app's defaults may have it off)
    /// and returns a closure that restores the previous value.
    @MainActor
    private func showFrontmatterForThisTest() -> () -> Void {
        let settings = SettingsManager.shared
        let previous = settings.showsFrontmatter
        settings.showsFrontmatter = true
        return { settings.showsFrontmatter = previous }
    }

    @MainActor
    private func show(_ content: String, at url: URL) -> MarkdownDocument {
        let document = MarkdownDocument(url: url, content: content)
        DocumentManager.shared.openDocuments = [document]
        DocumentManager.shared.selectedDocumentId = document.id
        return document
    }

    /// Polls `condition`, letting SwiftUI push model changes into the hosted preview between
    /// checks.
    @MainActor
    private func waitUntil(_ description: String, in harness: PreviewHarness, timeout: TimeInterval = 4,
                           _ condition: @escaping () -> Bool) {
        let done = expectation(description: description)
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            harness.hostingView.layoutSubtreeIfNeeded()
            if condition() {
                done.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
        wait(for: [done], timeout: timeout + 1)
    }

    @MainActor
    private func spin(_ seconds: TimeInterval) {
        let done = expectation(description: "run loop spins for \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    @MainActor
    func testClickingATaskCheckboxNeverChangesTheDocument() throws {
        let restore = preserveDocumentState()
        defer { restore() }
        let source = "# Plan\n\n- [ ] alpha\n- [x] beta\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-tasks-\(UUID().uuidString).md")
        _ = show(source, at: url)

        let harness = PreviewHarness()
        waitUntil("the task list renders", in: harness) { harness.textView?.string.contains("☐") == true }
        let textView = try XCTUnwrap(harness.textView)
        let rendered = textView.string

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let box = (rendered as NSString).range(of: "☐").location
        let glyph = layoutManager.glyphIndexForCharacter(at: box)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        let origin = textView.textContainerOrigin
        let location = textView.convert(NSPoint(x: origin.x + rect.midX, y: origin.y + rect.midY), to: nil)
        func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: harness.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }

        // NSTextView tracks a click until the button comes up, so queue the release first.
        NSApp.postEvent(try mouse(.leftMouseUp), atStart: true)
        textView.mouseDown(with: try mouse(.leftMouseDown))
        spin(0.3)

        XCTAssertFalse(textView.isEditable)
        XCTAssertEqual(textView.string, rendered, "the rendered checkbox must not flip")
        XCTAssertEqual(DocumentManager.shared.openDocuments.first?.content, source, "the document must not change")
    }

    @MainActor
    func testFrontmatterStartsCollapsedAndOpensFromItsHeader() throws {
        let restore = preserveDocumentState()
        let restoreSetting = showFrontmatterForThisTest()
        defer {
            restoreSetting()
            restore()
        }
        let source = "---\ntitle: \"Rendering check\"\nauthor: Hashlight\n---\n\n# Body\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-frontmatter-\(UUID().uuidString).md")
        _ = show(source, at: url)

        let harness = PreviewHarness()
        waitUntil("the document renders", in: harness) { harness.textView?.string.contains("Body") == true }
        let textView = try XCTUnwrap(harness.textView)

        // Collapsed by default, labelled with the document's title (unquoted); the YAML is
        // hidden.
        let collapsed = FrontmatterFold.collapsedMarker + " Rendering check\n"
        let expanded = FrontmatterFold.expandedMarker + " Rendering check\n"
        XCTAssertTrue(textView.string.contains(collapsed), textView.string)
        XCTAssertFalse(textView.string.contains("Document Info"))
        XCTAssertFalse(textView.string.contains("author"))

        func clickHeader() throws {
            let layoutManager = try XCTUnwrap(textView.layoutManager)
            let container = try XCTUnwrap(textView.textContainer)
            layoutManager.ensureLayout(for: container)
            let header = (textView.string as NSString).range(of: "Rendering check").location
            let glyph = layoutManager.glyphIndexForCharacter(at: header)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let origin = textView.textContainerOrigin
            let location = textView.convert(NSPoint(x: origin.x + rect.midX, y: origin.y + rect.midY), to: nil)
            func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: harness.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            }
            NSApp.postEvent(try mouse(.leftMouseUp), atStart: true)
            textView.mouseDown(with: try mouse(.leftMouseDown))
            spin(0.3)
        }

        // Expanded: the title stays in the header and the YAML follows as written.
        try clickHeader()
        XCTAssertTrue(textView.string.contains(expanded), textView.string)
        XCTAssertTrue(textView.string.contains("title: \"Rendering check\"\nauthor: Hashlight\n"))

        try clickHeader()
        XCTAssertTrue(textView.string.contains(collapsed))
        XCTAssertFalse(textView.string.contains("author"))
        XCTAssertEqual(DocumentManager.shared.openDocuments.first?.content, source, "the document must not change")
    }

    @MainActor
    func testFrontmatterWithoutATitleUsesAGenericLabelAndListsTheKeys() throws {
        let restore = preserveDocumentState()
        let restoreSetting = showFrontmatterForThisTest()
        defer {
            restoreSetting()
            restore()
        }
        let source = "---\nauthor: Hashlight\ntags: a, b\n---\n\n# Body\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-frontmatter-\(UUID().uuidString).md")
        _ = show(source, at: url)

        let harness = PreviewHarness()
        waitUntil("the document renders", in: harness) { harness.textView?.string.contains("Body") == true }
        let textView = try XCTUnwrap(harness.textView)
        XCTAssertTrue(textView.string.contains(FrontmatterFold.collapsedMarker + " Document Info   author, tags\n"), textView.string)
        XCTAssertFalse(textView.string.contains("Hashlight\n"))
    }

    @MainActor
    func testTheFrontmatterSettingRemovesTheBlockEntirely() throws {
        let restore = preserveDocumentState()
        let restoreSetting = showFrontmatterForThisTest()
        defer {
            restoreSetting()
            restore()
        }
        let settings = SettingsManager.shared
        let source = "---\ntitle: Rendering check\nauthor: Hashlight\n---\n\n# Body\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-frontmatter-\(UUID().uuidString).md")
        _ = show(source, at: url)

        let harness = PreviewHarness()
        waitUntil("the document renders", in: harness) { harness.textView?.string.contains("Body") == true }
        let textView = try XCTUnwrap(harness.textView)
        XCTAssertTrue(textView.string.contains(FrontmatterFold.collapsedMarker))

        // Off: no header, no YAML; the document starts at its first element.
        settings.showsFrontmatter = false
        waitUntil("the block disappears", in: harness) { harness.textView?.string.contains(FrontmatterFold.collapsedMarker) == false }
        XCTAssertFalse(textView.string.contains("author"))
        XCTAssertTrue(textView.string.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Body"), textView.string)

        settings.showsFrontmatter = true
        waitUntil("the block returns", in: harness) { harness.textView?.string.contains(FrontmatterFold.collapsedMarker) == true }
    }

    @MainActor
    func testTheTabBarHidesForALoneDocumentOnlyWhenTheSettingIsOn() throws {
        let restore = preserveDocumentState()
        let settings = SettingsManager.shared
        let previous = settings.hidesTabBarForSingleDocument
        defer {
            settings.hidesTabBarForSingleDocument = previous
            restore()
        }
        let manager = DocumentManager.shared
        let one = MarkdownDocument(url: URL(fileURLWithPath: "/tmp/hashlight-tab-one.md"), content: "# One\n")
        let two = MarkdownDocument(url: URL(fileURLWithPath: "/tmp/hashlight-tab-two.md"), content: "# Two\n")
        manager.openDocuments = [one]
        manager.selectedDocumentId = one.id

        let hosting = NSHostingView(rootView: NormalContentView(selectedHeadingId: .constant(nil))
            .environmentObject(manager)
            .environmentObject(settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        // The strip is the only horizontal scroll view in the column; the preview's is vertical.
        // SwiftUI removes a view's AppKit host a run-loop turn after the condition flips.
        func tabBarIsShown() -> Bool {
            hosting.layoutSubtreeIfNeeded()
            let deadline = Date().addingTimeInterval(0.6)
            while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            hosting.layoutSubtreeIfNeeded()
            return Self.horizontalScrollViews(in: hosting).contains { $0.frame.height < 60 && $0.frame.width > 100 }
        }

        settings.hidesTabBarForSingleDocument = false
        XCTAssertTrue(tabBarIsShown(), "default: the bar stays for one document")

        settings.hidesTabBarForSingleDocument = true
        XCTAssertFalse(tabBarIsShown(), "setting on: the bar hides for one document")

        manager.openDocuments = [one, two]
        XCTAssertTrue(tabBarIsShown(), "a second document brings it back")

        manager.openDocuments = [one]
        XCTAssertFalse(tabBarIsShown(), "and closing it hides the bar again")
    }

    @MainActor
    private static func horizontalScrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scrollView = view as? NSScrollView, scrollView.hasHorizontalScroller, !scrollView.hasVerticalScroller {
            found.append(scrollView)
        }
        for subview in view.subviews { found += horizontalScrollViews(in: subview) }
        return found
    }

    func testYAMLScalarsLoseMatchingQuotesOnly() {
        XCTAssertEqual(MarkdownTextView.unquotedYAMLScalar("\"Rendering check\""), "Rendering check")
        XCTAssertEqual(MarkdownTextView.unquotedYAMLScalar("'single'"), "single")
        XCTAssertEqual(MarkdownTextView.unquotedYAMLScalar("  plain  "), "plain")
        XCTAssertEqual(MarkdownTextView.unquotedYAMLScalar("\"mismatched'"), "\"mismatched'")
        XCTAssertEqual(MarkdownTextView.unquotedYAMLScalar("\""), "\"")
    }

    @MainActor
    func testReloadingTheShownDocumentKeepsTheScrollPosition() throws {
        let restore = preserveDocumentState()
        defer { restore() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashlight-scroll-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("long.md")
        let text = (1...300)
            .map { "Paragraph \($0) has enough words in it to wrap across the text column at least once." }
            .joined(separator: "\n\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let document = show(text, at: url)

        let harness = PreviewHarness()
        waitUntil("the long document renders", in: harness) { harness.textView?.string.contains("Paragraph 300") == true }
        // The first render positions the document on the next main-queue turn; let it land.
        spin(0.2)
        let textView = try XCTUnwrap(harness.textView)
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))

        func scroll(to y: CGFloat) {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        // Let one position be remembered for the file, then read on elsewhere: a reload must
        // keep the reader where they are now, not jump back to the remembered position.
        scroll(to: 1500)
        spin(Timing.scrollPositionPersistDebounce + 0.3)
        XCTAssertEqual(DocumentManager.shared.getScrollPosition(for: url), 1500, accuracy: 1)
        scroll(to: 900)

        try (text + "\n\nAppended by another app.").write(to: url, atomically: true, encoding: .utf8)
        DocumentManager.shared.reloadDocument(document)
        waitUntil("the reload renders", in: harness) { harness.textView?.string.contains("Appended by another app.") == true }
        spin(0.2)

        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 900, accuracy: 1)
    }

    /// Shows prose, a 1200 × 900 pt image, and more prose in a harness wide enough for every
    /// Content Width preset. Returns the harness and the image's character index.
    @MainActor
    private func showDocumentWithTallImage(in directory: URL) throws -> (PreviewHarness, Int) {
        let imageURL = directory.appendingPathComponent("tall.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 900, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: imageURL)
        let prose = "This paragraph has enough words in it to wrap across the text column more than once, "
            + "so a narrower or wider column moves everything below it. "
        func paragraphs(_ count: Int) -> String {
            (1...count).map { "\($0). " + prose + prose }.joined(separator: "\n\n")
        }
        let source = "# Image\n\n\(paragraphs(6))\n\n![Tall](\(imageURL.path))\n\n\(paragraphs(14))\n\nClosing paragraph.\n"
        _ = show(source, at: directory.appendingPathComponent("image.md"))

        let harness = PreviewHarness()
        harness.window.setContentSize(NSSize(width: 1400, height: 700))
        waitUntil("the document renders", in: harness) { harness.textView?.string.contains("Closing paragraph") == true }
        // The first render positions the document on the next main-queue turn; let it land.
        spin(0.2)
        let textView = try XCTUnwrap(harness.textView)
        let imageIndex = (textView.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertNotEqual(imageIndex, NSNotFound, "the image renders as an attachment")
        return (harness, imageIndex)
    }

    /// The line fragment holding the image, in the text view's coordinates.
    @MainActor
    private func imageFragment(_ index: Int, in textView: NSTextView) throws -> NSRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        layoutManager.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let origin = textView.textContainerOrigin
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
    }

    @MainActor
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashlight-anchor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Returns a closure that restores the Content Width and Page Margin settings.
    @MainActor
    private func preserveLayoutSettings() -> () -> Void {
        let settings = SettingsManager.shared
        let width = settings.contentWidth
        let margin = settings.pageMargin
        return {
            settings.contentWidth = width
            settings.pageMargin = margin
        }
    }

    /// Letting go of the window's edge keeps the position the reader saw while resizing.
    /// NSTextView scrolls the top of the first line fragment in view back to the top when a live
    /// resize ends; with an image there, the preview jumped up to the image's top.
    @MainActor
    func testEndingALiveResizeInsideAnImageKeepsTheScrollPosition() throws {
        let restore = preserveDocumentState()
        defer { restore() }
        let restoreSettings = preserveLayoutSettings()
        defer { restoreSettings() }
        SettingsManager.shared.contentWidth = .medium
        SettingsManager.shared.pageMargin = .normal
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (harness, imageIndex) = try showDocumentWithTallImage(in: directory)
        let textView = try XCTUnwrap(harness.textView)
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let image = try imageFragment(imageIndex, in: textView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: image.minY + image.height / 2))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        // What a drag on the window's corner sends the view: start, new size, end.
        textView.viewWillStartLiveResize()
        harness.window.setContentSize(NSSize(width: 1000, height: 600))
        harness.hostingView.layoutSubtreeIfNeeded()
        let resized = scrollView.contentView.bounds.origin.y
        XCTAssertGreaterThan(resized, try imageFragment(imageIndex, in: textView).minY + 100,
                             "sanity: the top of the viewport is still inside the image")
        textView.viewDidEndLiveResize()

        XCTAssertEqual(scrollView.contentView.bounds.origin.y, resized, accuracy: 0.5)
    }

    /// A Content Width change reflows the column and rescales images. A reader halfway down an
    /// image stays halfway down it (the preview used to jump to the image's top).
    @MainActor
    func testChangingContentWidthKeepsTheReaderInsideAnImage() throws {
        let restore = preserveDocumentState()
        defer { restore() }
        let restoreSettings = preserveLayoutSettings()
        defer { restoreSettings() }
        let settings = SettingsManager.shared
        settings.contentWidth = .medium
        settings.pageMargin = .normal
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (harness, imageIndex) = try showDocumentWithTallImage(in: directory)
        let textView = try XCTUnwrap(harness.textView)
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let before = try imageFragment(imageIndex, in: textView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: before.minY + before.height / 2))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        settings.contentWidth = .narrow
        waitUntil("the image is rebuilt at the Narrow width", in: harness) {
            ((try? self.imageFragment(imageIndex, in: textView).height) ?? before.height) < before.height - 100
        }
        spin(0.2)

        let after = try imageFragment(imageIndex, in: textView)
        XCTAssertEqual((scrollView.contentView.bounds.origin.y - after.minY) / after.height, 0.5, accuracy: 0.01)
    }

    /// A Page Margin change reflows the column without a rebuild; the reader keeps their place
    /// inside an image.
    @MainActor
    func testChangingPageMarginKeepsTheReaderInsideAnImage() throws {
        let restore = preserveDocumentState()
        defer { restore() }
        let restoreSettings = preserveLayoutSettings()
        defer { restoreSettings() }
        let settings = SettingsManager.shared
        settings.contentWidth = .full
        settings.pageMargin = .normal
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (harness, imageIndex) = try showDocumentWithTallImage(in: directory)
        let textView = try XCTUnwrap(harness.textView)
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let before = try imageFragment(imageIndex, in: textView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: before.minY + 450))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        settings.pageMargin = .comfortable
        waitUntil("the wider margin reaches the preview", in: harness) {
            textView.textContainerInset.width == SettingsManager.PageMargin.comfortable.points
        }
        spin(0.2)

        let after = try imageFragment(imageIndex, in: textView)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y - after.minY, 450, accuracy: 1)
    }

    /// Find searches the rendered text, and a folder-search hit — which comes from the source —
    /// still lands on its own rendered match.
    @MainActor
    func testFindCountsRenderedMatchesAndFolderSearchHitsLandOnTheirMatch() throws {
        let restore = preserveDocumentState()
        defer { restore() }
        let source = "See [docs](http://x.example) first.\n\nUse http for local work.\n\nNever http in prod.\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-find-\(UUID().uuidString).md")
        _ = show(source, at: url)
        let manager = DocumentManager.shared

        let harness = PreviewHarness()
        waitUntil("the document renders", in: harness) { harness.textView?.string.contains("Never http") == true }

        // The occurrence inside the link's URL is not on screen, so it is not counted.
        manager.startSearch()
        manager.searchText = "http"
        waitUntil("the preview counts its matches", in: harness) { manager.renderedMatchCount == 2 }
        XCTAssertEqual(manager.currentMatchIndex, 0)

        let hit = try XCTUnwrap(FolderSearch.hits(for: "http", in: source, url: url, limit: 10)
            .first { $0.snippet.hasPrefix("Never") })
        XCTAssertEqual(hit.occurrenceInFile, 2, "the source also counts the URL")

        // Opened while the find bar already shows this query.
        manager.revealSearchHit(hit, query: "http")
        waitUntil("the hit resolves against the existing matches", in: harness) { manager.currentMatchIndex == 1 }

        // Opened from a closed find bar.
        manager.endSearch()
        waitUntil("the closed find bar reaches the preview", in: harness) { true }
        manager.revealSearchHit(hit, query: "http")
        waitUntil("the hit resolves once the preview has searched", in: harness) {
            manager.renderedMatchCount == 2 && manager.currentMatchIndex == 1
        }
    }
}

/// Folder-wide content search (Quick Open's ">" mode).
nonisolated final class FolderSearchTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/doc.md")

    func testOneHitPerLineWithFindBarCompatibleOccurrenceIndexes() {
        // Occurrences of "cat": line1 ×2 (#0,#1), line3 ×1 (#2), line4 ×1 (#3, different case).
        let text = "cat and cat\nno match here\n  indented cat\nCAT shouting"
        let hits = FolderSearch.hits(for: "cat", in: text, url: url, limit: 50)

        XCTAssertEqual(hits.map(\.lineNumber), [1, 3, 4])
        // The find bar counts EVERY occurrence; a hit must carry the index of its own first
        // occurrence so opening it lands on that exact match, not merely "the Nth line".
        XCTAssertEqual(hits.map(\.occurrenceInFile), [0, 2, 3])
        XCTAssertEqual(hits[1].snippet, "indented cat", "leading whitespace trimmed for display")
    }

    func testHighlightRangeAlwaysCoversTheMatchInsideTheSnippet() {
        let long = String(repeating: "lorem ipsum ", count: 40) + "NEEDLE" + String(repeating: " dolor sit", count: 40)
        for text in ["needle at start", "   padded needle", long] {
            let hit = try? XCTUnwrap(FolderSearch.hits(for: "needle", in: text, url: url, limit: 5).first)
            guard let hit else { return XCTFail("no hit in: \(text.prefix(30))") }
            let chars = Array(hit.snippet)
            XCTAssertLessThanOrEqual(hit.matchStart + hit.matchLength, chars.count)
            let highlighted = String(chars[hit.matchStart..<(hit.matchStart + hit.matchLength)])
            XCTAssertEqual(highlighted.lowercased(), "needle", "highlight drifted off the match")
        }
        // A long line is windowed (ellipsis) rather than shown from column 0.
        XCTAssertTrue(FolderSearch.hits(for: "needle", in: long, url: url, limit: 5)[0].snippet.hasPrefix("…"))
    }

    func testCRLFLineNumbersAndMinimumQueryLength() {
        let hits = FolderSearch.hits(for: "two", in: "one\r\ntwo\r\nthree", url: url, limit: 5)
        XCTAssertEqual(hits.map(\.lineNumber), [2])
        XCTAssertTrue(FolderSearch.search(query: "a", in: [url]).isEmpty, "1-char queries must not walk the folder")
    }

    func testSearchAcrossFilesHonorsTheHitCapAndCancellation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-foldersearch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let matching = dir.appendingPathComponent("a.md")
        let other = dir.appendingPathComponent("b.md")
        let flood = dir.appendingPathComponent("c.md")
        try "alpha\nfind me here\n".write(to: matching, atomically: true, encoding: .utf8)
        try "nothing relevant\n".write(to: other, atomically: true, encoding: .utf8)
        try String(repeating: "find me\n", count: 500).write(to: flood, atomically: true, encoding: .utf8)
        let missing = dir.appendingPathComponent("deleted.md")

        let hits = FolderSearch.search(query: "FIND ME", in: [missing, matching, other])
        XCTAssertEqual(hits.map(\.url), [matching])
        XCTAssertEqual(hits.first?.lineNumber, 2)

        XCTAssertEqual(FolderSearch.search(query: "find me", in: [matching, flood]).count, FolderSearch.maxHits)
        XCTAssertTrue(FolderSearch.search(query: "find me", in: [matching, flood], isCancelled: { true }).isEmpty)
    }
}

/// Fixes from the pre-release code review of the folder-search / Quick Look work.
nonisolated final class ReviewFixTests: XCTestCase {
    // MARK: Rendered-index anchoring

    /// The reviewer's scenario: the query also occurs inside a link URL, which exists in the
    /// SOURCE but not in the rendered text — so a source occurrence index overshoots by one.
    func testRenderedIndexIgnoresOccurrencesThatOnlyExistInMarkup() {
        let source = "See [docs](http://x.example) first.\nUse http for local work.\nNever http in prod."
        let hits = FolderSearch.hits(for: "http", in: source, url: URL(fileURLWithPath: "/tmp/a.md"), limit: 50)
        let chosen = hits[2]                                  // "Never http in prod."
        XCTAssertEqual(chosen.occurrenceInFile, 2, "source counts the URL occurrence")

        let rendered = "See docs first.\nUse http for local work.\nNever http in prod." as NSString
        var ranges: [NSRange] = []
        var search = NSRange(location: 0, length: rendered.length)
        while true {
            let r = rendered.range(of: "http", options: .caseInsensitive, range: search)
            guard r.location != NSNotFound else { break }
            ranges.append(r)
            search = NSRange(location: NSMaxRange(r), length: rendered.length - NSMaxRange(r))
        }
        XCTAssertEqual(ranges.count, 2, "rendered text has only the two prose occurrences")

        let index = FolderSearch.renderedMatchIndex(
            snippet: chosen.snippet, matchStart: chosen.matchStart, matchLength: chosen.matchLength,
            rendered: rendered, matchRanges: ranges, fallback: chosen.occurrenceInFile)
        XCTAssertEqual(index, 1, "must land on 'Never http in prod', not clamp/overshoot")

        // And the first prose hit resolves to rendered match 0 even though its source index is 1.
        let first = hits[1]
        XCTAssertEqual(FolderSearch.renderedMatchIndex(
            snippet: first.snippet, matchStart: first.matchStart, matchLength: first.matchLength,
            rendered: rendered, matchRanges: ranges, fallback: first.occurrenceInFile), 0)
    }

    func testRenderedIndexFallsBackSafelyWithNoContextOrNoMatches() {
        XCTAssertEqual(FolderSearch.renderedMatchIndex(snippet: "x", matchStart: 0, matchLength: 1,
                                                       rendered: "" as NSString, matchRanges: [], fallback: 5), 0)
        let rendered = "zz zz zz" as NSString
        let ranges = [NSRange(location: 0, length: 2), NSRange(location: 3, length: 2), NSRange(location: 6, length: 2)]
        // No usable context agreement → clamped fallback, never out of range.
        XCTAssertEqual(FolderSearch.renderedMatchIndex(snippet: "??", matchStart: 0, matchLength: 2,
                                                       rendered: rendered, matchRanges: ranges, fallback: 99), 2)
    }

    // MARK: Decoder parity

    func testFolderSearchDecodesUTF16AndRepairsATruncatedUTF8Tail() throws {
        let utf16 = try XCTUnwrap("needle in utf16".data(using: .utf16))   // carries a BOM
        XCTAssertEqual(FolderSearch.decode(utf16, truncated: false), "needle in utf16")

        var cut = Data("caf\u{00E9} needle \u{1F600}".utf8)
        cut.removeLast(2)                                     // slice the 4-byte emoji mid-scalar
        let repaired = FolderSearch.decode(cut, truncated: true)
        XCTAssertEqual(repaired, "caf\u{00E9} needle ", "must stay UTF-8, not fall back to CP1252 mojibake")
        // The same bytes from a COMPLETE file genuinely are not UTF-8 → legacy fallback, not nil.
        XCTAssertNotNil(FolderSearch.decode(cut, truncated: false))
        XCTAssertNotEqual(FolderSearch.decode(cut, truncated: false), repaired)
    }

    // MARK: Quick Look truncation notice

    func testTruncationNoticeIsHTMLInsideTheBodyNotMarkdownInsideAnOpenFence() {
        // A file cut inside a fence: everything after the fence opener is code.
        let html = QuickLookHTML.makeOfflineSafe(MarkdownParser.shared.toHTML("```\ncut mid-fence", includeStyles: true))
        let noticed = QuickLookHTML.appendingTruncationNotice(to: html)
        let noticeAt = try? XCTUnwrap(noticed.range(of: "Preview truncated"))
        let bodyEnd = noticed.range(of: "</body>", options: .backwards)
        let lastCodeEnd = noticed.range(of: "</pre>", options: .backwards) ?? noticed.range(of: "</code>", options: .backwards)
        XCTAssertNotNil(noticeAt)
        if let noticeAt, let bodyEnd { XCTAssertLessThan(noticeAt.lowerBound, bodyEnd.lowerBound) }
        if let noticeAt, let lastCodeEnd {
            XCTAssertGreaterThan(noticeAt.lowerBound, lastCodeEnd.lowerBound, "notice must sit OUTSIDE the code block")
        }
    }

    // MARK: revealSearchHit

    @MainActor
    func testRevealRelocatesInTheLoadedTextAndIgnoresUnselectedFiles() throws {
        let manager = DocumentManager.shared
        let saved = (manager.openDocuments, manager.selectedDocumentId, manager.searchText,
                     manager.isSearching, manager.currentMatchIndex)
        defer {
            manager.endSearch()
            (manager.openDocuments, manager.selectedDocumentId, manager.searchText) = (saved.0, saved.1, saved.2)
            (manager.isSearching, manager.currentMatchIndex) = (saved.3, saved.4)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hashlight-reveal-\(UUID().uuidString).md")
        let searched = "cat one\ncat two\n"
        // The file changed after the folder search read it: an occurrence was added above the
        // hit, so its index in the search results (1) is now 2 in the tab's text.
        let loaded = "cat zero\n" + searched
        let id = UUID()
        manager.openDocuments = [MarkdownDocument(id: id, url: url, content: loaded)]
        manager.selectedDocumentId = id

        let hit = FolderSearch.hits(for: "cat", in: searched, url: url, limit: 10)[1]   // "cat two", index 1
        manager.revealSearchHit(hit, query: "cat")
        XCTAssertTrue(manager.isSearching)
        XCTAssertEqual(manager.searchText, "cat")

        // The preview resolves the rendered match from this, by context.
        let pending = try XCTUnwrap(manager.takePendingSearchReveal(documentId: id, query: "cat"))
        XCTAssertEqual(pending.snippet, "cat two")
        XCTAssertEqual(pending.sourceOccurrence, 2, "must follow 'cat two' into the loaded text")
        XCTAssertNil(manager.takePendingSearchReveal(documentId: id, query: "cat"), "handed out once")

        // A hit for a file that is NOT the selected document (e.g. its load failed) is a no-op.
        manager.endSearch()
        let other = FolderSearchHit(url: URL(fileURLWithPath: "/tmp/not-open-\(UUID().uuidString).md"),
                                    lineNumber: 1, snippet: "cat", matchStart: 0, matchLength: 3, occurrenceInFile: 0)
        manager.revealSearchHit(other, query: "cat")
        XCTAssertFalse(manager.isSearching, "must not start a search in whatever document happened to be selected")
    }
}

nonisolated final class MarkdownTableColumnLayoutTests: XCTestCase {
    func testDescriptionsGetMoreWidthThanCompactStatusFields() {
        let rows = [
            ["Interface", "Description", "Admin State", "Operational State", "Speed", "Duplex", "VLAN", "MAC Address"],
            ["ethernet1/1/1", "Uplink toward the aggregation switch with a long explanation that should wrap", "Enabled", "Up", "100 Gbps", "Full", "1234", "aa:bb:cc:dd:ee:ff"]
        ]

        let widths = MarkdownTableColumnLayout.widthPercentages(for: rows)

        XCTAssertEqual(widths.count, 8)
        XCTAssertEqual(widths.reduce(0, +), 100, accuracy: 0.001)
        XCTAssertGreaterThan(widths[1], widths[2], "description should be wider than a status column")
        XCTAssertGreaterThan(widths[3], widths[2], "operational state needs more room for its longer header")
        XCTAssertGreaterThanOrEqual(widths[3], 10, "operational state should not fall to the compact-column minimum")
        XCTAssertGreaterThan(widths[1], widths[6], "description should be wider than a VLAN column")
        XCTAssertGreaterThan(widths[0], widths[6], "interface identifiers should get more room than VLAN")
        XCTAssertGreaterThan(widths[7], widths[6], "MAC addresses should get more room than VLAN")
        XCTAssertTrue(widths.allSatisfy { $0 >= 7 && $0 <= 45 })
    }

    func testWidthsAlwaysFillTheTableAndSupportSingleColumnTables() {
        XCTAssertEqual(MarkdownTableColumnLayout.widthPercentages(for: []), [])
        XCTAssertEqual(MarkdownTableColumnLayout.widthPercentages(for: [["Summary"], ["A full-width summary row"]]), [100])

        let widths = MarkdownTableColumnLayout.widthPercentages(for: [["Key", "Value"], ["Status", "Active"]])
        XCTAssertEqual(widths.reduce(0, +), 100, accuracy: 0.001)
    }

    func testLongTechnicalHeadersDoNotCollapseToCompactWidths() {
        let headers = [
            "Interface", "Description", "Admin State", "Operational State", "Speed",
            "Duplex", "VLAN", "MAC Address", "IPv4 Address", "Documentation"
        ]

        let widths = MarkdownTableColumnLayout.widthPercentages(for: [headers])

        XCTAssertEqual(widths.count, headers.count)
        XCTAssertGreaterThanOrEqual(widths[3], 10, "Operational State should stay readable in a wide table")
        XCTAssertGreaterThanOrEqual(widths[9], 10, "Documentation should stay readable in a wide table")
    }

    func testDefaultCategoriesPreserveCurrentWordsWeightsAndPriority() {
        let categories = MarkdownTableColumnCategory.defaults

        XCTAssertEqual(categories.map(\.name), [
            "Descriptive", "Operational / Documentation", "Compact", "Identifier", "Other"
        ])
        XCTAssertEqual(categories.map(\.weight), [2.4, 1.5, 0.65, 1.3, 1.0])
        XCTAssertEqual(categories[0].words, [
            "comment", "comments", "description", "details", "message", "notes",
            "purpose", "reason", "remarks", "summary"
        ])
        XCTAssertEqual(categories[1].words, ["operational", "documentation"])
        XCTAssertEqual(categories[2].words, [
            "admin", "enabled", "flag", "id", "link", "mode", "mtu", "operational",
            "priority", "speed", "state", "status", "type", "vlan", "duplex", "count"
        ])
        XCTAssertEqual(categories[3].words, [
            "address", "gateway", "host", "interface", "ip", "mac", "name", "prefix", "url"
        ])
        XCTAssertTrue(categories[4].words.isEmpty)
        XCTAssertTrue(categories[0...3].allSatisfy { !$0.canBeRemoved })
        XCTAssertTrue(categories[4].canBeRemoved)
    }

    func testWholeWordMatchingAndFirstCategoryPriority() {
        let custom = MarkdownTableColumnCategory(id: "custom", name: "Custom", weight: 3.0, words: ["ip"])
        let defaults = MarkdownTableColumnConfiguration.defaults
        var configuration = MarkdownTableColumnConfiguration(categories: [custom] + defaults.categories)

        // "ip" inside "shipping" is not a token match, so Status falls through to Compact.
        XCTAssertEqual(MarkdownTableColumnLayout.weight(for: "Shipping Status", configuration: configuration), 0.65)

        let first = MarkdownTableColumnCategory(id: "first", name: "First", weight: 0.4, words: ["state"])
        let second = MarkdownTableColumnCategory(id: "second", name: "Second", weight: 4.0, words: ["state"])
        configuration.categories = [first, second] + defaults.categories
        XCTAssertEqual(MarkdownTableColumnLayout.weight(for: "Operational State", configuration: configuration), 0.4)

        configuration.categories.swapAt(0, 1)
        XCTAssertEqual(MarkdownTableColumnLayout.weight(for: "Operational State", configuration: configuration), 4.0)
    }

    func testOtherWeightAndImplicitFallbackWhenOtherIsRemoved() {
        var configuration = MarkdownTableColumnConfiguration.defaults
        configuration.categories[4].weight = 0.6
        XCTAssertEqual(MarkdownTableColumnLayout.weight(for: "Unmatched Header", configuration: configuration), 0.6)

        configuration.categories.removeAll { $0.id == "other" }
        XCTAssertEqual(MarkdownTableColumnLayout.weight(for: "Unmatched Header", configuration: configuration), 1.0)
    }

    func testConfigurationSnapshotAndPreferencesRoundTrip() throws {
        var configuration = MarkdownTableColumnConfiguration.defaults
        configuration.categories[0].words.append("purposeful")
        configuration.categories[0].weight = 2.75
        configuration.categories.reverse()

        let encoded = try XCTUnwrap(configuration.encodedSnapshot())
        XCTAssertEqual(MarkdownTableColumnConfiguration.decodeSnapshot(encoded), configuration)
        XCTAssertNil(MarkdownTableColumnConfiguration.decodeSnapshot(Data("not json".utf8)))

        let suffix = UUID().uuidString
        let appDomain = "io.github.ib0ndar.hashlight.tests.app.\(suffix)"
        let quickLookDomain = "io.github.ib0ndar.hashlight.tests.ql.\(suffix)"
        let appDefaults = try XCTUnwrap(UserDefaults(suiteName: appDomain))
        let quickLookDefaults = try XCTUnwrap(UserDefaults(suiteName: quickLookDomain))
        defer {
            appDefaults.removePersistentDomain(forName: appDomain)
            quickLookDefaults.removePersistentDomain(forName: quickLookDomain)
        }

        MarkdownTableColumnPreferences.persist(
            configuration,
            appDefaults: appDefaults,
            sharedPreferences: quickLookDefaults
        )
        XCTAssertEqual(
            MarkdownTableColumnPreferences.load(from: appDefaults, key: MarkdownTableColumnPreferences.appKey),
            configuration
        )
        XCTAssertEqual(
            MarkdownTableColumnPreferences.load(from: quickLookDefaults, key: MarkdownTableColumnPreferences.sharedKey),
            configuration
        )
    }

    func testInvalidWeightsAreRejectedBeforePersistence() {
        let invalid = MarkdownTableColumnCategory(id: "bad", name: "Bad", weight: .infinity, words: [])
        XCTAssertFalse(MarkdownTableColumnConfiguration.isValid([invalid]))
        XCTAssertFalse(MarkdownTableColumnConfiguration.isValid([
            .init(id: "duplicate", name: "One", weight: 1, words: []),
            .init(id: "duplicate", name: "Two", weight: 1, words: [])
        ]))
    }

    func testContentSizedColumnsTakeTheirNaturalWidthWhenTheyFit() {
        let widths = MarkdownTableColumnLayout.fittedWidths(natural: [60, 120, 90], words: [40, 80, 60], minimum: 64, available: 700)
        XCTAssertEqual(widths, [64, 120, 90], "a column is never narrower than the minimum, and the table shrinks to its content")
    }

    func testColumnsThatDoNotFitShareTheRestEqually() {
        // Xcode 27's own measurements of fixtures/reader-layout.md (natural widths in points,
        // its 4em minimum, 1074 pt available) and the widths it draws: 131 132 95 129 98 62 54 131 131 120.
        let natural: [CGFloat] = [130, 700, 95, 129, 98, 61, 54, 135, 134, 120]
        let widths = MarkdownTableColumnLayout.fittedWidths(natural: natural, words: Array(repeating: 0, count: 10), minimum: 52, available: 1074)
        XCTAssertEqual(widths.reduce(0, +), 1074, accuracy: 0.01)
        for (index, expected) in [129.25, 129.25, 95, 129, 98, 61, 54, 129.25, 129.25, 120].enumerated() {
            XCTAssertEqual(widths[index], CGFloat(expected), accuracy: 0.01, "column \(index)")
        }
    }

    func testAWordIsKeptWholeWithRoomFromColumnsThatWrapAnyway() {
        // Two prose columns (longest word 80) and an address column whose one token needs 140.
        // The shared level alone gives each 100 and splits the address; the prose gives way.
        let widths = MarkdownTableColumnLayout.fittedWidths(natural: [900, 140, 900], words: [80, 140, 80], minimum: 64, available: 300)
        XCTAssertEqual(widths[0], 80, accuracy: 0.01)
        XCTAssertEqual(widths[1], 140, accuracy: 0.01)
        XCTAssertEqual(widths[2], 80, accuracy: 0.01)

        // Not enough room to keep the token whole: the shared widths stay.
        let shared = MarkdownTableColumnLayout.fittedWidths(natural: [900, 900], words: [64, 500], minimum: 64, available: 400)
        XCTAssertEqual(shared[0], 200, accuracy: 0.01)
        XCTAssertEqual(shared[1], 200, accuracy: 0.01)
    }

    func testWordsAreKeptWholeSmallestShortfallFirst() {
        // Shared level 125. Column 2 (needs 160) is repaired from the prose columns; column 3
        // (needs 170) only if room is left, which it is: column 1's short words let it narrow.
        let widths = MarkdownTableColumnLayout.fittedWidths(natural: [900, 300, 160, 170], words: [100, 64, 160, 170], minimum: 64, available: 500)
        XCTAssertEqual(widths[0], 100, accuracy: 0.01)
        XCTAssertEqual(widths[1], 70, accuracy: 0.01)
        XCTAssertEqual(widths[2], 160, accuracy: 0.01)
        XCTAssertEqual(widths[3], 170, accuracy: 0.01)

        // A column that fits on one line is never narrowed to save a word elsewhere.
        let kept = MarkdownTableColumnLayout.fittedWidths(natural: [90, 300], words: [40, 300], minimum: 64, available: 300)
        XCTAssertEqual(kept[0], 90, accuracy: 0.01)
        XCTAssertEqual(kept[1], 210, accuracy: 0.01)
    }

    func testTooManyColumnsShareTheWidthAndNeverOverflow() {
        let widths = MarkdownTableColumnLayout.fittedWidths(
            natural: Array(repeating: 90, count: 24),
            words: Array(repeating: 70, count: 24),
            minimum: 64,
            available: 690
        )
        XCTAssertEqual(widths.reduce(0, +), 690, accuracy: 0.01)
        XCTAssertTrue(widths.allSatisfy { abs($0 - 690.0 / 24) < 0.01 })
    }

    func testASpanningRowWidensANarrowTableUpToTheAvailableWidth() {
        XCTAssertEqual(
            MarkdownTableColumnLayout.fittedWidths(natural: [100, 100], words: [50, 50], minimum: 64, spanning: 300, available: 700),
            [150, 150]
        )
        let capped = MarkdownTableColumnLayout.fittedWidths(natural: [100, 100], words: [50, 50], minimum: 64, spanning: 900, available: 700)
        XCTAssertEqual(capped.reduce(0, +), 700, accuracy: 0.01)
        XCTAssertEqual(
            MarkdownTableColumnLayout.fittedWidths(natural: [100, 100], words: [50, 50], minimum: 64, spanning: 150, available: 700),
            [100, 100]
        )
    }

    @MainActor
    func testColumnWeightingIsOffUntilTurnedOnAndReachesQuickLook() throws {
        XCTAssertEqual(DefaultsKeys.tableColumnWeightsEnabled, "markdownTableColumnWeightsEnabled")
        XCTAssertEqual(MarkdownTableColumnPreferences.sharedEnabledKey, "weights-enabled")

        let suffix = UUID().uuidString
        let appDomain = "io.github.ib0ndar.hashlight.tests.app.\(suffix)"
        let quickLookDomain = "io.github.ib0ndar.hashlight.tests.ql.\(suffix)"
        let appDefaults = try XCTUnwrap(UserDefaults(suiteName: appDomain))
        let quickLookDefaults = try XCTUnwrap(UserDefaults(suiteName: quickLookDomain))
        defer {
            appDefaults.removePersistentDomain(forName: appDomain)
            quickLookDefaults.removePersistentDomain(forName: quickLookDomain)
        }

        XCTAssertFalse(MarkdownTableColumnPreferences.isEnabled(in: appDefaults, key: MarkdownTableColumnPreferences.appEnabledKey), "off by default")
        XCTAssertNil(MarkdownTableColumnPreferences.enabledConfiguration(from: quickLookDefaults))

        var configuration = MarkdownTableColumnConfiguration.defaults
        configuration.categories[0].weight = 3
        MarkdownTableColumnPreferences.persist(configuration, appDefaults: appDefaults, sharedPreferences: quickLookDefaults)
        XCTAssertNil(MarkdownTableColumnPreferences.enabledConfiguration(from: quickLookDefaults), "saved categories alone do not turn weighting on")

        MarkdownTableColumnPreferences.persistEnabled(true, appDefaults: appDefaults, sharedPreferences: quickLookDefaults)
        XCTAssertTrue(MarkdownTableColumnPreferences.isEnabled(in: appDefaults, key: MarkdownTableColumnPreferences.appEnabledKey))
        XCTAssertEqual(MarkdownTableColumnPreferences.enabledConfiguration(from: quickLookDefaults), configuration)

        MarkdownTableColumnPreferences.persistEnabled(false, appDefaults: appDefaults, sharedPreferences: quickLookDefaults)
        XCTAssertNil(MarkdownTableColumnPreferences.enabledConfiguration(from: quickLookDefaults))

        quickLookDefaults.set("yes", forKey: MarkdownTableColumnPreferences.sharedEnabledKey)
        XCTAssertNil(MarkdownTableColumnPreferences.enabledConfiguration(from: quickLookDefaults), "a value of the wrong type counts as off")
    }

    @MainActor
    func testThePreviewAppliesCategoriesOnlyWhileWeightingIsOn() {
        let settings = SettingsManager.shared
        let previous = settings.tableColumnWeightsEnabled
        defer { settings.tableColumnWeightsEnabled = previous }

        settings.tableColumnWeightsEnabled = false
        XCTAssertNil(settings.activeTableColumnConfiguration)
        XCTAssertEqual(UserDefaults.standard.object(forKey: DefaultsKeys.tableColumnWeightsEnabled) as? Bool, false)

        settings.tableColumnWeightsEnabled = true
        XCTAssertEqual(settings.activeTableColumnConfiguration, settings.tableColumnConfiguration)
        XCTAssertEqual(UserDefaults.standard.object(forKey: DefaultsKeys.tableColumnWeightsEnabled) as? Bool, true)
    }
}
