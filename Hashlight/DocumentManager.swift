import SwiftUI
import UniformTypeIdentifiers

class DocumentManager: ObservableObject {
    static let shared = DocumentManager()

    /// Supplied by the main SwiftUI window so file-opening events can recreate it after
    /// the user closes the last window while keeping the app running.
    private var openMainWindowAction: (() -> Void)?
    private var closeMainWindowAction: (() -> Void)?

    func registerMainWindowOpener(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func registerMainWindowCloser(_ action: @escaping () -> Void) {
        closeMainWindowAction = action
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openMainWindowAction?()
    }

    func closeMainWindow() {
        closeMainWindowAction?()
    }

    @Published var openDocuments: [MarkdownDocument] = []
    @Published var selectedDocumentId: UUID?
    @Published var recentFileURLs: [URL] = []

    // Tab drag-reorder
    @Published var draggingDocumentId: UUID?

    // Focus mode
    @Published var isFocusModeActive: Bool = false

    // Bumped by MarkdownTextView.Coordinator after the diagram-render coalesce timer fires,
    // keyed by the document whose diagram/math just rendered. Forces SwiftUI to re-evaluate
    // the view body so updateNSView runs and rebuilds the attributed string from cache (now
    // containing the rendered Mermaid/KaTeX images). Without this, math/diagrams stay as the
    // purple placeholder text on static docs.
    // Per-document (Plan 003): was previously a single shared Int. The coordinator-side
    // notification handler now filters by document id before this is ever touched, so only
    // the originating document's entry is bumped; other open panes' coordinators return early
    // and never reach this. Entries are not removed when a document closes — the map holds
    // one small Int per document ever opened this session, which is negligible.
    @Published var diagramRenderTicks: [UUID: Int] = [:]

    // Search state. The find bar searches the rendered preview: MarkdownTextView computes the
    // matches and reports their count through setRenderedMatchCount.
    @Published var isSearching: Bool = false
    @Published var searchText: String = ""
    @Published var currentMatchIndex: Int = 0
    @Published var renderedMatchCount: Int = 0

    // Folder-search hit reveal (stored here: the search code lives in an extension).
    /// A hit the PREVIEW still has to locate in its rendered text — see revealSearchHit.
    fileprivate(set) var pendingSearchReveal: PendingSearchReveal?

    // File watching
    private var fileWatchers: [UUID: FileWatcher] = [:]

    // Reading position memory
    private var scrollPositions: [String: CGFloat] = [:]
    // Per-path access timestamps so eviction can be LRU rather than random. Without this,
    // `Dictionary.keys.prefix(excess)` returned in unspecified order and could drop the user's
    // currently-open doc when the cap was hit (M9).
    private var scrollPositionTouched: [String: Date] = [:]
    private let scrollPositionsKey = DefaultsKeys.scrollPositions

    // Key aliases — centralized in DefaultsKeys so key strings live in a single place.
    private let maxRecentFiles = Cache.recentFilesLimit
    private let recentFilesKey = DefaultsKeys.recentFiles
    private let alertManager = AlertManager.shared

    /// Decode file data trying multiple encodings, returns content and encoding name.
    /// Order: BOM sniff → strict UTF-8 → CP1252 heuristic → Mac Roman → ISO-8859-1 catch-all.
    /// L5 note: CP1252 *almost* decodes any byte sequence — Foundation rejects 5 undefined
    /// positions (0x81, 0x8D, 0x8F, 0x90, 0x9D). When CP1252 fails on those, the chain falls
    /// through to Mac Roman / ISO-8859-1 (latter has no undefined positions). Either way the
    /// strict UTF-8 + BOM checks must come first or UTF-encoded files get misclassified.
    private func decodeFileData(_ data: Data) -> (content: String, encoding: String) {
        // 1) BOM sniff — most reliable discrimination.
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF,
           let str = String(data: data, encoding: .utf8) {
            return (str, "UTF-8")
        }
        if data.count >= 4, data[0] == 0xFF, data[1] == 0xFE, data[2] == 0x00, data[3] == 0x00,
           let str = String(data: data, encoding: .utf32LittleEndian) {
            return (str, "UTF-32")
        }
        if data.count >= 4, data[0] == 0x00, data[1] == 0x00, data[2] == 0xFE, data[3] == 0xFF,
           let str = String(data: data, encoding: .utf32BigEndian) {
            return (str, "UTF-32")
        }
        if data.count >= 2, (data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF),
           let str = String(data: data, encoding: .utf16) {
            return (str, "UTF-16")
        }

        // 2) Strict UTF-8 (returns nil on invalid byte sequences).
        if let str = String(data: data, encoding: .utf8) {
            return (str, "UTF-8")
        }
        // 3) CP1252 — heuristic fallback; decodes any byte sequence.
        if let str = String(data: data, encoding: .windowsCP1252) {
            return (str, "CP1252")
        }
        // 4) Mac Roman.
        if let str = String(data: data, encoding: .macOSRoman) {
            return (str, "Mac Roman")
        }
        // 5) ISO-8859-1 as final catch-all (every byte maps to a code point).
        if let str = String(data: data, encoding: .isoLatin1) {
            return (str, "ISO-8859-1")
        }
        return (String(decoding: data, as: UTF8.self), "UTF-8")
    }

    init() {
        loadRecentFiles()
        loadScrollPositions()
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown")].compactMap { $0 }

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    // Save directory bookmark while NSOpenPanel grants access
                    let parentDir = url.deletingLastPathComponent()
                    let dirBookmark = try? parentDir.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    self.loadDocument(from: url, directoryBookmark: dirBookmark)
                }
            }
        }
    }

    func loadDocument(from url: URL, directoryBookmark: Data? = nil) {
        let key = Self.canonicalKey(for: url)

        // Check if already open. Use the same canonical path key as Open Recent so symlinks,
        // standardized paths, and case variants focus the existing tab instead of duplicating it.
        if let doc = openDocuments.first(where: { Self.canonicalKey(for: $0.url) == key }) {
            selectedDocumentId = doc.id
            showMainWindow()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let (fileContent, encoding) = decodeFileData(data)

            var document = MarkdownDocument(url: url, content: fileContent)
            document.detectedEncoding = encoding
            document.directoryBookmarkData = directoryBookmark
            openDocuments.append(document)
            selectedDocumentId = document.id

            // Start file watching
            startWatchingFile(for: document)

            // Add to recent files
            addToRecentFiles(url: url)
            showMainWindow()
        } catch {
            alertManager.showFileLoadError(url: url, error: error)
        }
    }

    // MARK: - File Watching

    private func startWatchingFile(for document: MarkdownDocument) {
        let watcher = FileWatcher(url: document.url)
        watcher.delegate = self
        watcher.startWatching()
        fileWatchers[document.id] = watcher
    }

    private func stopWatchingFile(for document: MarkdownDocument) {
        fileWatchers[document.id]?.stopWatching()
        fileWatchers.removeValue(forKey: document.id)
    }

    func reloadDocument(_ document: MarkdownDocument) {
        guard let data = try? Data(contentsOf: document.url) else {
            alertManager.showFileLoadError(url: document.url, error: NSError(domain: "DocumentManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read file"]))
            return
        }

        let (fileContent, encoding) = decodeFileData(data)

        if let index = openDocuments.firstIndex(where: { $0.id == document.id }) {
            // C8: mutate in place so directoryBookmarkData — which MarkdownTextView uses for
            // relative-image access — survives the reload.
            openDocuments[index].content = fileContent
            openDocuments[index].detectedEncoding = encoding
        }
    }

    // MARK: - Recent Files Management

    /// Canonical path used for case-insensitive dedup on macOS's default HFS+/APFS filesystem.
    private static func canonicalKey(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }

    private func loadRecentFiles() {
        guard let bookmarksData = UserDefaults.standard.array(forKey: recentFilesKey) as? [Data] else { return }

        var urls: [URL] = []
        var rewroteAny = false
        var rewrittenBookmarks: [Data] = []

        for data in bookmarksData {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                // Resolution failed — drop this bookmark (file deleted / volume gone).
                rewroteAny = true
                continue
            }

            // Dedup against earlier entries by canonical path (case-insensitive on macOS).
            if urls.contains(where: { Self.canonicalKey(for: $0) == Self.canonicalKey(for: url) }) {
                rewroteAny = true
                continue
            }

            if isStale {
                // Bookmark is stale (file moved) — regenerate so it resolves next launch.
                if let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    rewrittenBookmarks.append(fresh)
                    rewroteAny = true
                } else {
                    rewrittenBookmarks.append(data)
                }
            } else {
                rewrittenBookmarks.append(data)
            }
            urls.append(url)
        }

        recentFileURLs = urls
        if rewroteAny {
            UserDefaults.standard.set(rewrittenBookmarks, forKey: recentFilesKey)
        }
    }

    private func saveRecentFiles() {
        let bookmarksData = recentFileURLs.compactMap { url -> Data? in
            try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarksData, forKey: recentFilesKey)
    }

    private func addToRecentFiles(url: URL) {
        // Remove any existing entry for this file — canonical compare so /Users/Z/file.md
        // and /users/z/file.md do not both appear on a case-insensitive volume.
        let key = Self.canonicalKey(for: url)
        recentFileURLs.removeAll { Self.canonicalKey(for: $0) == key }

        // Add to beginning
        recentFileURLs.insert(url, at: 0)

        // Limit to max count
        if recentFileURLs.count > maxRecentFiles {
            recentFileURLs = Array(recentFileURLs.prefix(maxRecentFiles))
        }

        saveRecentFiles()
    }

    func clearRecentFiles() {
        recentFileURLs.removeAll()
        saveRecentFiles()
    }

    // MARK: - Scroll Position Memory

    private func loadScrollPositions() {
        if let data = UserDefaults.standard.dictionary(forKey: scrollPositionsKey) as? [String: Double] {
            scrollPositions = data.mapValues { CGFloat($0) }
        }
    }

    private func saveScrollPositions() {
        let data = scrollPositions.mapValues { Double($0) }
        UserDefaults.standard.set(data, forKey: scrollPositionsKey)
    }

    func getScrollPosition(for url: URL) -> CGFloat {
        return scrollPositions[url.path] ?? 0
    }

    private let maxScrollPositions = Cache.scrollPositionLimit

    func setScrollPosition(_ position: CGFloat, for url: URL) {
        scrollPositions[url.path] = position
        scrollPositionTouched[url.path] = Date()

        // Prune if exceeding limit. First drop stale entries (files no longer on disk); if still
        // over cap, evict the LRU entries by access timestamp.
        if scrollPositions.count > maxScrollPositions {
            let existingPaths = scrollPositions.keys.filter { FileManager.default.fileExists(atPath: $0) }
            let stalePaths = Set(scrollPositions.keys).subtracting(existingPaths)
            for path in stalePaths {
                scrollPositions.removeValue(forKey: path)
                scrollPositionTouched.removeValue(forKey: path)
            }
            if scrollPositions.count > maxScrollPositions {
                let excess = scrollPositions.count - maxScrollPositions
                let lruKeys = scrollPositionTouched
                    .sorted { $0.value < $1.value }
                    .prefix(excess)
                    .map(\.key)
                for key in lruKeys {
                    scrollPositions.removeValue(forKey: key)
                    scrollPositionTouched.removeValue(forKey: key)
                }
            }
        }

        saveScrollPositions()
    }

    // MARK: - Refresh/Reload

    func refreshCurrentDocument() {
        guard let selectedId = selectedDocumentId,
              let document = openDocuments.first(where: { $0.id == selectedId }) else {
            return
        }
        reloadDocument(document)
    }

    // MARK: - Tab Reorder

    func moveDocument(withId id: UUID, toIndex: Int) {
        guard let fromIndex = openDocuments.firstIndex(where: { $0.id == id }),
              fromIndex != toIndex, toIndex >= 0, toIndex < openDocuments.count else { return }
        let doc = openDocuments.remove(at: fromIndex)
        openDocuments.insert(doc, at: toIndex)
    }

    // MARK: - Closing

    /// A viewer holds no unsaved state, so closing never asks for confirmation.
    func closeDocument(_ document: MarkdownDocument) {
        closeDocument(id: document.id)
    }

    private func closeDocument(id documentId: UUID, closeWindowWhenEmpty: Bool = true) {
        if let index = openDocuments.firstIndex(where: { $0.id == documentId }) {
            let document = openDocuments[index]

            // Clear search state if closing the document being searched
            if document.id == selectedDocumentId && isSearching {
                endSearch()
            }

            // Stop file watching
            stopWatchingFile(for: document)

            openDocuments.remove(at: index)

            // Clear dragging state if this was the dragged doc
            if draggingDocumentId == document.id {
                draggingDocumentId = nil
            }

            // Select another document if available
            if !openDocuments.isEmpty && selectedDocumentId == document.id {
                selectedDocumentId = openDocuments.last?.id
            } else if openDocuments.isEmpty {
                selectedDocumentId = nil
            }

            if closeWindowWhenEmpty && openDocuments.isEmpty {
                WindowCloseDelegate.shared.closeWindowWhenEmpty()
            }
        }
    }

    /// Closes every tab at once, for the window's close button. The window is already closing,
    /// so this does not ask it to close again when the last tab goes.
    func closeAllDocuments() {
        for id in openDocuments.map(\.id) {
            closeDocument(id: id, closeWindowWhenEmpty: false)
        }
    }

    func closeOtherDocuments(except document: MarkdownDocument) {
        // Clear search when closing multiple tabs
        if isSearching {
            endSearch()
        }

        // Stop file watching for closed documents
        for doc in openDocuments where doc.id != document.id {
            stopWatchingFile(for: doc)
        }

        openDocuments.removeAll(where: { $0.id != document.id })
        selectedDocumentId = document.id
    }

    func selectNextTab() {
        guard !openDocuments.isEmpty else { return }

        if let currentId = selectedDocumentId,
           let currentIndex = openDocuments.firstIndex(where: { $0.id == currentId }) {
            let nextIndex = (currentIndex + 1) % openDocuments.count
            selectedDocumentId = openDocuments[nextIndex].id
        } else {
            selectedDocumentId = openDocuments.first?.id
        }
    }

    func selectPreviousTab() {
        guard !openDocuments.isEmpty else { return }

        if let currentId = selectedDocumentId,
           let currentIndex = openDocuments.firstIndex(where: { $0.id == currentId }) {
            let previousIndex = (currentIndex - 1 + openDocuments.count) % openDocuments.count
            selectedDocumentId = openDocuments[previousIndex].id
        } else {
            selectedDocumentId = openDocuments.last?.id
        }
    }

    // MARK: - File Management Operations

    func revealInFinder(document: MarkdownDocument) {
        NSWorkspace.shared.activateFileViewerSelecting([document.url])
    }
}

struct MarkdownDocument: Identifiable {
    let id: UUID
    var url: URL
    var content: String
    var directoryBookmarkData: Data?
    var detectedEncoding: String = "UTF-8"

    /// Single initializer. Defaults match the member defaults so all call sites can construct
    /// with just `url:` and `content:`.
    init(id: UUID = UUID(),
         url: URL,
         content: String,
         directoryBookmarkData: Data? = nil,
         detectedEncoding: String = "UTF-8") {
        self.id = id
        self.url = url
        self.content = content
        self.directoryBookmarkData = directoryBookmarkData
        self.detectedEncoding = detectedEncoding
    }

    var name: String {
        url.lastPathComponent
    }
}

extension DocumentManager {
    /// The document in the selected tab.
    var selectedDocument: MarkdownDocument? {
        guard let selectedDocumentId else { return nil }
        return openDocuments.first(where: { $0.id == selectedDocumentId })
    }

    func startSearch() {
        isSearching = true
        searchText = ""
        currentMatchIndex = 0
        renderedMatchCount = 0
    }

    func endSearch() {
        pendingSearchReveal = nil
        isSearching = false
        searchText = ""
        currentMatchIndex = 0
        renderedMatchCount = 0
    }

    // MARK: Folder-search hit reveal

    /// A folder-search hit the PREVIEW still has to locate in its rendered text. Consumed by
    /// MarkdownTextView's coordinator right after it computes match ranges for `query`.
    struct PendingSearchReveal {
        let documentId: UUID
        let query: String
        let snippet: String
        let matchStart: Int
        let matchLength: Int
        let sourceOccurrence: Int
    }
    func takePendingSearchReveal(documentId: UUID?, query: String) -> PendingSearchReveal? {
        guard let pending = pendingSearchReveal,
              pending.documentId == documentId, pending.query == query else { return nil }
        pendingSearchReveal = nil
        return pending
    }

    /// After opening a folder-search hit: put the find bar on THAT occurrence.
    func revealSearchHit(_ hit: FolderSearchHit, query: String) {
        // The hit's file must actually be the selected document. If loadDocument failed (error
        // alert), the previously selected document is still selected — starting a search in
        // IT would be wrong, so do nothing.
        guard let selectedId = selectedDocumentId,
              let document = openDocuments.first(where: { $0.id == selectedId }),
              Self.canonicalKey(for: document.url) == Self.canonicalKey(for: hit.url) else { return }

        // The hit was computed from the file on disk, which may have changed since the tab
        // loaded it (or since the search ran). Re-locate the hit in the loaded text: same
        // line + text, else the same text nearest that line, else the nearest line.
        let liveHits = FolderSearch.hits(for: query, in: document.content, url: document.url, limit: Int.max)
        func distance(_ candidate: FolderSearchHit) -> Int { abs(candidate.lineNumber - hit.lineNumber) }
        let live = liveHits.first { $0.lineNumber == hit.lineNumber && $0.snippet == hit.snippet }
            ?? liveHits.filter { $0.snippet == hit.snippet }.min { distance($0) < distance($1) }
            ?? liveHits.min { distance($0) < distance($1) }

        searchText = query
        isSearching = true
        currentMatchIndex = 0

        // The find bar indexes matches in the RENDERED text, which drops markup (a query inside
        // a link URL exists in the source but not on screen), and its match count arrives
        // asynchronously — a stale count for a previous query can even reset the index in
        // between. So the preview resolves the index itself, by context, once it has computed
        // ranges for this query; it gets the last word.
        guard let live else { return }
        pendingSearchReveal = PendingSearchReveal(
            documentId: selectedId, query: query, snippet: live.snippet,
            matchStart: live.matchStart, matchLength: live.matchLength,
            sourceOccurrence: live.occurrenceInFile
        )
    }

    func nextMatch() {
        let count = renderedMatchCount
        guard count > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % count
    }

    func previousMatch() {
        let count = renderedMatchCount
        guard count > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + count) % count
    }

    func setRenderedMatchCount(_ count: Int) {
        renderedMatchCount = count
        // Reset index if it's out of bounds
        if currentMatchIndex >= count {
            currentMatchIndex = 0
        }
    }
}

// MARK: - File Watcher Delegate

extension DocumentManager: FileWatcherDelegate {
    /// There are no local edits to lose, so an external change reloads the tab without asking.
    /// The preview keeps its scroll position across the reload.
    func fileWatcher(_ watcher: FileWatcher, fileDidChange url: URL) {
        guard let document = openDocuments.first(where: { $0.url == url }) else { return }
        reloadDocument(document)
    }

    func fileWatcher(_ watcher: FileWatcher, fileWasDeleted url: URL) {
        // Find the document that corresponds to this URL
        guard let document = openDocuments.first(where: { $0.url == url }) else { return }

        // Show warning that file was deleted
        let shouldClose = alertManager.showConfirmation(
            title: "File Deleted",
            message: "\"\(url.lastPathComponent)\" has been deleted. Do you want to close this tab?",
            confirmButton: "Close Tab",
            cancelButton: "Keep Open"
        )

        if shouldClose {
            closeDocument(document)
        }
    }
}
