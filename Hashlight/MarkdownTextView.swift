import SwiftUI
import AppKit
import CoreText

/// NSTextView-based markdown renderer with full text selection support
struct MarkdownTextView: NSViewRepresentable {
    let content: String
    let baseURL: URL?
    let directoryBookmark: Data?
    /// Identifies which open document this pane is currently displaying. Threaded through to
    /// the Coordinator and stamped on every posted `.diagramRendered` notification so a
    /// diagram/math render completing in one pane cannot invalidate another pane's cache
    /// (Plan 003 — was previously a global, unscoped notification).
    let documentId: UUID
    @Binding var scrollToHeadingId: String?
    let searchText: String
    let currentMatchIndex: Int
    let mainFontID: String
    let fixedFontID: String
    /// Body text and code-block sizes at 100 % zoom (Settings → Viewing → Fonts). Every size in
    /// the build is written for the defaults and scaled by `PreviewRenderer`.
    let mainFontSize: CGFloat
    let fixedFontSize: CGFloat
    let theme: PreviewTheme
    let zoomLevel: CGFloat
    /// Whether a leading YAML block is rendered (as a folded card) or left out entirely.
    let showsFrontmatter: Bool
    let initialScrollPosition: CGFloat
    let onScrollPositionChanged: ((CGFloat) -> Void)?
    let onMatchCountChanged: ((Int) -> Void)?
    /// Horizontal placement of the text column within the pane (Settings → Appearance and the
    /// status bar). Pure positioning — it never touches the attributed string, so changing it
    /// costs a redraw, not a rebuild.
    let contentAlignment: SettingsManager.ContentAlignment
    /// Maximum width of the text column. Unlike alignment this DOES affect the build: images
    /// and diagrams are sized once at build time, so it is part of the element-cache key.
    let contentWidth: SettingsManager.ContentWidth
    /// Horizontal page inset. Applied as view layout so changing it does not rebuild Markdown.
    let pageMargin: SettingsManager.PageMargin
    /// Header-category column sizing; nil (column weighting off) sizes columns to their content.
    let tableColumnConfiguration: MarkdownTableColumnConfiguration?
    /// Space above and below the text (the update window's release notes use less).
    let verticalInset: CGFloat
    private var imageResources: PreviewImageResources?

    init(content: String, baseURL: URL?, directoryBookmark: Data? = nil, documentId: UUID, scrollToHeadingId: Binding<String?>, searchText: String, currentMatchIndex: Int, mainFontID: String, fixedFontID: String, mainFontSize: CGFloat = CGFloat(PreviewFontCatalog.defaultMainSize), fixedFontSize: CGFloat = CGFloat(PreviewFontCatalog.defaultFixedSize), theme: PreviewTheme, zoomLevel: CGFloat = 1.0, initialScrollPosition: CGFloat = 0, onScrollPositionChanged: ((CGFloat) -> Void)? = nil, onMatchCountChanged: ((Int) -> Void)? = nil, contentAlignment: SettingsManager.ContentAlignment = .left, contentWidth: SettingsManager.ContentWidth = .medium, pageMargin: SettingsManager.PageMargin = .normal, tableColumnConfiguration: MarkdownTableColumnConfiguration? = nil, showsFrontmatter: Bool = true, verticalInset: CGFloat = 40) {
        self.content = content
        self.baseURL = baseURL
        self.directoryBookmark = directoryBookmark
        self.documentId = documentId
        self._scrollToHeadingId = scrollToHeadingId
        self.searchText = searchText
        self.currentMatchIndex = currentMatchIndex
        self.mainFontID = mainFontID
        self.fixedFontID = fixedFontID
        self.mainFontSize = mainFontSize
        self.fixedFontSize = fixedFontSize
        self.theme = theme
        self.zoomLevel = zoomLevel
        self.initialScrollPosition = initialScrollPosition
        self.onScrollPositionChanged = onScrollPositionChanged
        self.onMatchCountChanged = onMatchCountChanged
        self.contentAlignment = contentAlignment
        self.contentWidth = contentWidth
        self.pageMargin = pageMargin
        self.tableColumnConfiguration = tableColumnConfiguration
        self.showsFrontmatter = showsFrontmatter
        self.verticalInset = verticalInset
    }

    /// Everything besides content + zoom that changes what gets built.
    private var styleKey: String {
        "\(mainFontID)-\(fixedFontID)-\(mainFontSize)-\(fixedFontSize)-\(contentWidth.rawValue)-\(theme.cacheKey)-\(tableColumnConfiguration?.cacheKey ?? "content-sized")-\(showsFrontmatter ? "fm" : "nofm")"
    }

    func makeNSView(context: Context) -> NSScrollView {
        // PreviewTextView (PreviewTextView.swift) so the text column can be positioned
        // left/center/right.
        let (scrollView, textView) = PreviewTextView.makeScrollView(
            theme: theme,
            contentAlignment: contentAlignment,
            contentWidth: contentWidth,
            pageMargin: pageMargin,
            verticalInset: verticalInset
        )
        context.coordinator.lastStyleKey = styleKey

        // Enable link clicking
        textView.delegate = context.coordinator

        // Store reference for coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.lastParent = self
        textView.onFrontmatterToggle = { [weak coordinator = context.coordinator, weak textView, weak scrollView] in
            guard let coordinator, let textView, let scrollView else { return }
            coordinator.toggleFrontmatter(textView: textView, scrollView: scrollView)
        }
        context.coordinator.baseURL = baseURL
        context.coordinator.documentId = documentId
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged
        context.coordinator.onMatchCountChanged = onMatchCountChanged

        // Set up scroll notification
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Listen for diagram render completions. Registered with object: nil (rather than
        // filtering here via NotificationCenter's own object-equality matching) because the
        // poster's object is a UUID value type — NotificationCenter's object filter is not
        // documented/reliable for value-type identity, so filtering happens explicitly inside
        // diagramDidRender(_:) instead (Plan 003).
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.diagramDidRender(_:)),
            name: .diagramRendered,
            object: nil
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        textView.appearance = theme.appearance
        textView.backgroundColor = theme.backgroundColor
        scrollView.appearance = theme.appearance
        scrollView.backgroundColor = theme.backgroundColor

        let desiredInsets = NSSize(width: pageMargin.points, height: verticalInset)
        if textView.textContainerInset != desiredInsets {
            if let preview = textView as? PreviewTextView {
                preview.setTextContainerInsetKeepingReadingPosition(desiredInsets)
            } else {
                textView.textContainerInset = desiredInsets
            }
        }

        // Cheap: the setter no-ops when unchanged, and a change only invalidates the container
        // origin + redraws (no rebuild — alignment isn't part of the attributed string).
        (textView as? PreviewTextView)?.contentAlignment = contentAlignment
        (textView as? PreviewTextView)?.preferredColumnWidth = contentWidth.points

        // Captured BEFORE the reassignment below so we can tell a tab/document switch apart
        // from a reload of the same document (Plan 009) — the coordinator is reused across
        // document switches within a pane (see comment below), so `documentId` itself always
        // reads as "current" by the time the debounce decision is made unless we snapshot the
        // prior value first.
        let previousDocumentId = context.coordinator.documentId

        // Coordinator instances are reused across document switches within the same pane
        // (same view identity, new `content`/`documentId` params) — refresh this on every
        // pass so the diagram-render filter always reflects what's CURRENTLY displayed, not
        // whichever document this pane showed when the NSView was first created (Plan 003).
        context.coordinator.documentId = documentId
        context.coordinator.lastParent = self

        // Check if content changed
        let contentChanged = context.coordinator.lastContent != content
        let searchChanged = context.coordinator.lastSearchText != searchText
        let matchIndexChanged = context.coordinator.lastMatchIndex != currentMatchIndex
        let zoomChanged = context.coordinator.lastZoomLevel != zoomLevel
        // Font style and content width both change what gets BUILT (fonts; image/diagram
        // caps) without changing content or zoom. Font style previously had no trigger at
        // all — switching it in Settings left the preview stale until the next edit or zoom.
        let styleChanged = context.coordinator.lastStyleKey != styleKey
        let documentSwitched = previousDocumentId != documentId
        // `lastContent == nil` covers both "first render of a fresh/reused Coordinator" and
        // "diagram-render-forced rebuild" (diagramDidRender resets `lastContent` to nil to force
        // a rebuild, Plan 003) — neither is a reload, so both must rebuild immediately rather
        // than ride the reload debounce below.
        let isFreshOrForcedRebuild = context.coordinator.lastContent == nil

        // Full rebuild when content or zoom changes. Debounce ONLY a same-document content
        // change (the file was reloaded from disk; a tool rewriting it in bursts coalesces into
        // one rebuild) with no zoom change — everything else (zoom, tab/document switch, first
        // render, diagram-render-forced rebuild) rebuilds with zero delay (Plan 009).
        if contentChanged || zoomChanged || styleChanged {
            context.coordinator.lastZoomLevel = zoomLevel
            context.coordinator.lastStyleKey = styleKey
            let isReload = contentChanged && !zoomChanged && !styleChanged && !documentSwitched && !isFreshOrForcedRebuild
            context.coordinator.scheduleRebuild(
                for: self,
                textView: textView,
                scrollView: scrollView,
                contentChanged: contentChanged,
                isReload: isReload
            )
        }
        // Lightweight search update — no full rebuild needed
        else if searchChanged {
            context.coordinator.lastSearchText = searchText

            // Clear only the ranges we previously painted — as TEMPORARY attributes, matching
            // how updateMatchHighlighting paints them. (A storage-level removeAttribute here
            // would clear nothing — the highlights aren't in the storage — while still wiping
            // the tracking list, orphaning the painted ranges forever. That was exactly the
            // stuck-highlight-after-clearing-the-query bug.)
            if let layoutManager = textView.layoutManager, let storage = textView.textStorage {
                for r in context.coordinator.searchHighlightRanges where r.location + r.length <= storage.length {
                    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
                    layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: r)
                }
                context.coordinator.searchHighlightRanges.removeAll(keepingCapacity: true)
            }

            if !searchText.isEmpty {
                context.coordinator.findMatchRanges(for: searchText, in: textView)
                context.coordinator.updateMatchHighlighting(currentIndex: currentMatchIndex, in: textView, searchText: searchText)
                if !context.coordinator.matchRanges.isEmpty {
                    DispatchQueue.main.async {
                        context.coordinator.scrollToMatch(at: currentMatchIndex, in: textView)
                    }
                }
            } else {
                context.coordinator.matchRanges = []
                context.coordinator.reportMatchCount(0)
            }
        }
        // Same query, same text: a folder-search hit opened in the document already showing
        // this query still needs resolving against the existing matches.
        else if !searchText.isEmpty {
            context.coordinator.resolvePendingSearchReveal(for: searchText, in: textView)
        }

        // Handle match navigation (scroll and update highlight)
        if matchIndexChanged && !searchText.isEmpty {
            context.coordinator.lastMatchIndex = currentMatchIndex
            context.coordinator.updateMatchHighlighting(currentIndex: currentMatchIndex, in: textView, searchText: searchText)
            context.coordinator.scrollToMatch(at: currentMatchIndex, in: textView)
        }

        // Handle scroll to heading
        if let headingId = scrollToHeadingId {
            DispatchQueue.main.async {
                context.coordinator.scrollToHeading(id: headingId, in: textView)
                scrollToHeadingId = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var scrollView: NSScrollView?
        var baseURL: URL?
        // Which open document this pane is CURRENTLY displaying — refreshed on every
        // updateNSView pass (see comment there). Used to filter incoming .diagramRendered
        // notifications so a render belonging to a different document/pane is ignored (Plan 003).
        var documentId: UUID?
        var headingRanges: [String: NSRange] = [:]
        var lastContent: String?
        private var renderedDocumentId: UUID?
        var lastSearchText: String?
        var lastZoomLevel: CGFloat = 1.0
        var lastStyleKey: String = ""
        var lastMatchIndex: Int = -1
        var matchRanges: [NSRange] = []
        // Ranges currently painted with a search highlight. Tracked separately so we can clear
        // only those backgrounds — previously the lightweight search-update path called
        // `removeAttribute(.backgroundColor, range: 0..<storage.length)` and wiped legitimate
        // backgrounds from inline-code spans, code blocks, and table cells. After H3 the only
        // backgrounds removed are the ones search itself painted.
        var searchHighlightRanges: [NSRange] = []
        var onScrollPositionChanged: ((CGFloat) -> Void)?
        var onMatchCountChanged: ((Int) -> Void)?
        // nonisolated(unsafe) on the timers: all live access is on the main actor; the
        // annotation exists solely so nonisolated deinit can invalidate them (deinit has
        // exclusive access).
        nonisolated(unsafe) private var scrollDebounceTimer: Timer?
        // Coalesces the rebuild (full re-parse + NSAttributedString build) when the shown
        // document reloads from disk, so a tool rewriting the file in bursts costs one rebuild
        // instead of one per write (Plan 009).
        nonisolated(unsafe) private var rebuildDebounceTimer: Timer?
        nonisolated(unsafe) private var interruptibleScrollTimer: Timer?
        // Image cache shared across renders
        static var imageCache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = Cache.imageCountLimit
            cache.totalCostLimit = Cache.imageByteLimit
            return cache
        }()
        static var remoteImageInFlight: Set<String> = []
        static var remoteImageFailures: Set<String> = []
        // Diagram/math cache — uses the diagram-specific limits, which are much higher than
        // the image limits because math images are tiny but appear in large numbers in
        // technical docs (~300+ inline spans is common). Old shared image limit (100) thrashed.
        static var diagramCache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = Cache.diagramCountLimit
            cache.totalCostLimit = Cache.diagramByteLimit
            return cache
        }()
        // Element-level rendering cache for incremental updates
        var elementCache: [String: NSAttributedString] = [:]
        var lastZoomKey: String = ""
        let imageResources = PreviewImageResources()
        /// Documents whose frontmatter block is open; the default is collapsed.
        var expandedFrontmatterDocuments: Set<UUID> = []
        /// The representable as of the last update, for rebuilds the view asks for itself.
        var lastParent: MarkdownTextView?

        // Scroll Y captured at the moment a diagram-render notification arrived. After the
        // rebuild lands, updateNSView restores to this exact Y — preserving the user's scroll
        // position rather than letting setAttributedString reset to 0 or anchor-based restore
        // visibly shift it. The visible content at that Y may be slightly different post-rebuild
        // (math images replaced text placeholders) but the viewport doesn't jump.
        var pendingDiagramScrollY: CGFloat?

        // MARK: - Preview Rebuild (debounced on reload, Plan 009)

        /// Entry point `updateNSView` routes every full-rebuild trigger through. `isReload`
        /// marks a new version of the document already on screen: it is debounced 150ms
        /// (coalescing a burst of writes into one rebuild) and keeps the reader's scroll
        /// position. Everything else — zoom changes, tab/document switches, first render, and
        /// diagram-render-forced rebuilds (Plan 003) — lands with zero delay. `parent` is
        /// captured as a value-type snapshot at the moment of the call, so a debounced timer
        /// firing later always rebuilds against the content that was current when it was
        /// (re)scheduled — each reload reschedules with the latest snapshot, so the final
        /// version is never dropped.
        /// Opens or closes the current document's frontmatter block and rebuilds in place,
        /// keeping the reader's scroll position.
        func toggleFrontmatter(textView: NSTextView, scrollView: NSScrollView) {
            guard let documentId, let parent = lastParent else { return }
            if expandedFrontmatterDocuments.contains(documentId) {
                expandedFrontmatterDocuments.remove(documentId)
            } else {
                expandedFrontmatterDocuments.insert(documentId)
            }
            performRebuild(for: parent, textView: textView, scrollView: scrollView, contentChanged: true, keepScrollPosition: true)
        }

        func scheduleRebuild(for parent: MarkdownTextView, textView: NSTextView, scrollView: NSScrollView, contentChanged: Bool, isReload: Bool) {
            guard isReload else {
                rebuildDebounceTimer?.invalidate()
                rebuildDebounceTimer = nil
                performRebuild(for: parent, textView: textView, scrollView: scrollView, contentChanged: contentChanged, keepScrollPosition: false)
                return
            }
            rebuildDebounceTimer?.invalidate()
            rebuildDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildDebounceTimer = nil
                    self?.performRebuild(
                        for: parent,
                        textView: textView,
                        scrollView: scrollView,
                        contentChanged: contentChanged,
                        keepScrollPosition: true
                    )
                }
            }
        }

        /// Does the actual re-parse + NSAttributedString rebuild, plus every side effect that
        /// used to sit directly in `updateNSView`'s `if contentChanged || zoomChanged` block
        /// (search-match repopulation/highlighting, scroll-position restore, scroll-to-match) —
        /// moved here so they run against the freshly rebuilt text storage regardless of whether
        /// this was reached immediately or after the debounce delay.
        private func performRebuild(for parent: MarkdownTextView, textView: NSTextView, scrollView: NSScrollView, contentChanged: Bool, keepScrollPosition: Bool) {
            // Read at rebuild time, not when the reload was scheduled: the reader may have
            // scrolled during the debounce.
            let keptScrollY = keepScrollPosition ? scrollView.contentView.bounds.origin.y : nil
            let selection = renderedDocumentId == parent.documentId ? textView.selectedRanges : []
            let (attributedString, headingRanges) = parent.buildAttributedString(coordinator: self)
            textView.showPreview(attributedString)
            if !selection.isEmpty, let storage = textView.textStorage {
                textView.selectedRanges = selection.map { value in
                    let range = value.rangeValue
                    let location = min(range.location, storage.length)
                    return NSValue(range: NSRange(location: location, length: min(range.length, storage.length - location)))
                }
            }
            renderedDocumentId = parent.documentId
            self.headingRanges = headingRanges
            self.lastContent = parent.content
            self.lastSearchText = parent.searchText

            // Find and store all match ranges in the rendered text
            if !parent.searchText.isEmpty {
                findMatchRanges(for: parent.searchText, in: textView)
            } else {
                matchRanges = []
            }
            // C6: paint the match ranges onto the freshly rebuilt storage.
            updateMatchHighlighting(currentIndex: parent.currentMatchIndex, in: textView, searchText: parent.searchText)

            // Restore scroll position after content is set (only on content change, not zoom)
            if contentChanged {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let pinY = self.pendingDiagramScrollY {
                        // Diagram-render rebuild: clamp scroll back to the exact Y the user
                        // was at before the rebuild.
                        self.pendingDiagramScrollY = nil
                        self.restoreScrollPosition(pinY, in: scrollView)
                    } else if let keptScrollY {
                        // Reload of the document on screen: stay where the reader is.
                        self.restoreScrollPosition(keptScrollY, in: scrollView)
                    } else if parent.initialScrollPosition > 10 && parent.searchText.isEmpty {
                        self.restoreScrollPosition(parent.initialScrollPosition, in: scrollView)
                    } else if parent.searchText.isEmpty {
                        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                    }
                }
            }

            // Scroll to the current match if searching — except on a reload, which keeps the
            // reader's position.
            if !parent.searchText.isEmpty && !matchRanges.isEmpty && keptScrollY == nil {
                DispatchQueue.main.async { [weak self] in
                    self?.scrollToMatch(at: parent.currentMatchIndex, in: textView)
                }
            }
        }

        func scrollToHeading(id: String, in textView: NSTextView) {
            guard let range = headingRanges[id],
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }

            // Calculate target position
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let headingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let inset = textView.textContainerInset
            let targetY = headingRect.origin.y + inset.height - 20 // 20px above heading
            let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
            let clampedY = min(max(0, targetY), maxY)

            // Interruptible scroll — replaces the NSAnimationContext.animator() tween, which
            // could not be grabbed: a wheel/trackpad scroll during the 0.3s flight fought the
            // animation instead of cancelling it. The driver below yields to user input on
            // the next frame (see startInterruptibleScroll).
            startInterruptibleScroll(to: clampedY, in: scrollView, duration: Motion.reduceMotion ? 0 : 0.3)

            // Briefly highlight the heading. The text storage can be rebuilt while the delayed
            // clear is pending, so validate the captured range before touching the selection.
            let storageLength = textView.textStorage?.length ?? textView.string.utf16.count
            guard NSMaxRange(range) <= storageLength else { return }
            textView.setSelectedRange(range)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let currentLength = textView.textStorage?.length ?? textView.string.utf16.count
                guard range.location <= currentLength else { return }
                textView.setSelectedRange(NSRange(location: range.location, length: 0))
            }
        }

        func restoreScrollPosition(_ position: CGFloat, in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else { return }
            let maxScroll = max(0, documentView.frame.height - scrollView.contentView.bounds.height)
            let clampedPosition = min(position, maxScroll)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedPosition))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        // MARK: - Link Handling

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            if let linkURL = link as? URL {
                url = linkURL
            } else if let linkString = link as? String {
                url = URL(string: linkString)
            } else {
                return false
            }

            guard let url = url else { return false }

            // Handle relative .md links by opening as a new tab
            if ["md", "markdown"].contains(url.pathExtension.lowercased()),
               let base = baseURL?.deletingLastPathComponent() {
                let resolved = base.appendingPathComponent(url.relativeString).standardizedFileURL
                // S3: confine the resolved path to the document's directory subtree. Without this,
                // a crafted link like [x](../../../../private.md) resolves outside the folder and
                // would be opened. The trailing-slash form prevents a sibling-prefix false match
                // (e.g. base "/a/notes" vs "/a/notes-secret/x.md").
                let baseDir = base.standardizedFileURL
                let basePrefix = baseDir.path.hasSuffix("/") ? baseDir.path : baseDir.path + "/"
                guard resolved.path == baseDir.path || resolved.path.hasPrefix(basePrefix) else {
                    return false
                }
                if FileManager.default.fileExists(atPath: resolved.path) {
                    DocumentManager.shared.loadDocument(from: resolved)
                    return true
                }
            }

            // Open external URLs in default browser
            if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                NSWorkspace.shared.open(url)
                return true
            }

            return false
        }

        // MARK: - Interruptible programmatic scroll

        /// Frame-driven eased scroll that the USER can grab: each tick checks whether the clip
        /// view is still where the previous tick left it — if not, the user scrolled mid-flight
        /// and the driver yields immediately (their input wins, no fighting, no completion
        /// hand-back). NSAnimationContext.animator() could not do this: nothing cancels a
        /// Core-Animation-driven bounds change when wheel deltas arrive.
        private struct InterruptibleScrollState {
            let startY: CGFloat
            let targetY: CGFloat
            let startTime: Date
            let duration: TimeInterval
        }
        private var interruptibleScrollState: InterruptibleScrollState?
        private var interruptibleScrollLastAppliedY: CGFloat = -1

        func startInterruptibleScroll(to targetY: CGFloat, in scrollView: NSScrollView, duration: TimeInterval) {
            cancelInterruptibleScroll()
            guard duration > 0 else {
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                return
            }
            let startY = scrollView.contentView.bounds.origin.y
            interruptibleScrollState = InterruptibleScrollState(
                startY: startY, targetY: targetY, startTime: Date.now, duration: duration
            )
            interruptibleScrollLastAppliedY = startY
            interruptibleScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak scrollView] _ in
                Task { @MainActor [weak self, weak scrollView] in
                    guard let scrollView else {
                        self?.cancelInterruptibleScroll()
                        return
                    }
                    self?.interruptibleScrollTick(scrollView)
                }
            }
        }

        private func interruptibleScrollTick(_ scrollView: NSScrollView) {
            guard let state = interruptibleScrollState else {
                cancelInterruptibleScroll()
                return
            }
            let currentY = scrollView.contentView.bounds.origin.y
            // The clip view moved between our frames — that's user input. Yield.
            if abs(currentY - interruptibleScrollLastAppliedY) > 0.5 {
                cancelInterruptibleScroll()
                return
            }
            let t = min(1.0, Date.now.timeIntervalSince(state.startTime) / state.duration)
            // easeInOut, matching the curve the old NSAnimationContext used.
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let y = state.startY + (state.targetY - state.startY) * eased
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            interruptibleScrollLastAppliedY = scrollView.contentView.bounds.origin.y
            if t >= 1.0 {
                cancelInterruptibleScroll()
            }
        }

        private func cancelInterruptibleScroll() {
            interruptibleScrollTimer?.invalidate()
            interruptibleScrollTimer = nil
            interruptibleScrollState = nil
        }

        // MARK: - Search Methods

        /// Deliver the match count on the next runloop turn. All callers run inside
        /// updateNSView — i.e. during the SwiftUI update pass — and the callback writes a
        /// @Published property on DocumentManager; publishing synchronously from within a view
        /// update is undefined behavior (dropped updates, runtime warning).
        func reportMatchCount(_ count: Int) {
            let cb = onMatchCountChanged
            DispatchQueue.main.async { cb?(count) }
        }

        /// Literal, case-insensitive matches of `searchText` in the rendered text — the same
        /// matching folder search uses, so a folder-search hit always has a rendered match.
        func findMatchRanges(for searchText: String, in textView: NSTextView) {
            matchRanges = []
            guard let storage = textView.textStorage, !searchText.isEmpty else {
                reportMatchCount(0)
                return
            }

            let string = storage.string as NSString
            var searchRange = NSRange(location: 0, length: string.length)
            while searchRange.location < string.length {
                let range = string.range(of: searchText, options: .caseInsensitive, range: searchRange)
                guard range.location != NSNotFound else { break }
                matchRanges.append(range)
                // Advance by at least one character to avoid infinite loops on zero-length matches.
                let advance = max(1, range.length)
                searchRange.location = range.location + advance
                searchRange.length = max(0, string.length - searchRange.location)
            }

            // Report match count back (deferred — see reportMatchCount)
            reportMatchCount(matchRanges.count)

            // Queued AFTER the count report on the same FIFO main queue, so it lands after
            // setRenderedMatchCount's clamp — and after any stale count for a previous query —
            // and therefore has the last word on the index.
            resolvePendingSearchReveal(for: searchText, in: textView)
        }

        /// A folder-search hit waiting to be located in THIS rendered text: pick the rendered
        /// match that corresponds to it and make it the current match.
        func resolvePendingSearchReveal(for searchText: String, in textView: NSTextView) {
            // A reload is about to replace the text; the rebuild resolves it against the new matches.
            guard rebuildDebounceTimer == nil,
                  let storage = textView.textStorage,
                  let reveal = DocumentManager.shared.takePendingSearchReveal(documentId: documentId, query: searchText)
            else { return }
            let index = FolderSearch.renderedMatchIndex(
                snippet: reveal.snippet, matchStart: reveal.matchStart, matchLength: reveal.matchLength,
                rendered: storage.string as NSString, matchRanges: matchRanges, fallback: reveal.sourceOccurrence
            )
            DispatchQueue.main.async {
                DocumentManager.shared.currentMatchIndex = index
            }
        }

        func scrollToMatch(at index: Int, in textView: NSTextView) {
            guard index >= 0 && index < matchRanges.count else { return }
            let range = matchRanges[index]

            // Clear any selection so it doesn't override the yellow highlight
            textView.setSelectedRange(NSRange(location: range.location, length: 0))

            // Get the rect for this text range
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                textView.scrollRangeToVisible(range)
                return
            }

            // Get the bounding rect for the match
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let matchRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // Adjust for the text container's position. textContainerOrigin, not
            // textContainerInset: with center/right content alignment the container's x is no
            // longer the inset width.
            let containerOrigin = textView.textContainerOrigin
            let adjustedRect = NSRect(
                x: matchRect.origin.x + containerOrigin.x,
                y: matchRect.origin.y + containerOrigin.y,
                width: matchRect.width,
                height: matchRect.height
            )

            // Get the scroll view and its visible height
            guard let scrollView = textView.enclosingScrollView else {
                textView.scrollRangeToVisible(range)
                return
            }

            let visibleHeight = scrollView.contentView.bounds.height

            // Calculate scroll position to center the match vertically
            let targetY = adjustedRect.origin.y - (visibleHeight / 2) + (adjustedRect.height / 2)
            let maxY = max(0, textView.frame.height - visibleHeight)
            let clampedY = min(max(0, targetY), maxY)

            // Scroll to center the match
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func updateMatchHighlighting(currentIndex: Int, in textView: NSTextView, searchText: String) {
            guard let layoutManager = textView.layoutManager,
                  let storage = textView.textStorage else { return }

            // Paint search highlights as the layout manager's TEMPORARY attributes, never
            // into the text storage. Storage-level painting caused a visible bug: the black
            // .foregroundColor forced onto matches could not be reliably cleared (the
            // original token color is unknown at clear time), so every character that
            // matched an earlier prefix of the query ("h", "hi", …) stayed permanently
            // black — invisible in dark mode — until the next full rebuild. Temporary
            // attributes are render-only overlays; removing them restores the underlying
            // storage attributes exactly, with no bookkeeping of original colors needed.
            for r in searchHighlightRanges where r.location + r.length <= storage.length {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: r)
            }
            searchHighlightRanges.removeAll(keepingCapacity: true)

            // Re-apply highlighting to all matches
            for (index, range) in matchRanges.enumerated() {
                guard range.location + range.length <= storage.length else { continue }
                let isCurrent = index == currentIndex
                let bgColor = isCurrent ? NSColor.systemOrange : NSColor.systemYellow.withAlphaComponent(0.5)
                layoutManager.addTemporaryAttributes([
                    .backgroundColor: bgColor,
                    .foregroundColor: NSColor.black
                ], forCharacterRange: range)
                searchHighlightRanges.append(range)
            }
        }

        // Debounce diagram-render notifications so a doc with N Mermaid/KaTeX blocks doesn't
        // force N full rebuilds during initial open (M2). 100ms is below the perceptible-flicker
        // threshold and comfortably groups the burst from a normal multi-diagram doc.
        nonisolated(unsafe) private var diagramCoalesceTimer: Timer?

        // Plan 003: every open pane's coordinator registers for this notification (object: nil
        // — see registration comment in makeNSView), so without filtering, a diagram/math
        // render completing in ANY tab/pane would clear every OTHER open pane's elementCache
        // and force a full re-parse, even for documents with no diagrams at all. Filter to only
        // the document this pane is currently displaying.
        @objc func diagramDidRender(_ notification: Notification) {
            guard let renderedDocumentId = notification.object as? UUID,
                  let myDocumentId = self.documentId,
                  renderedDocumentId == myDocumentId else { return }
            diagramCoalesceTimer?.invalidate()
            diagramCoalesceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Re-check identity at fire time, not just at notification-arrival time.
                    guard self.documentId == myDocumentId else { return }
                    // Snapshot scroll Y so the post-rebuild restore pins to the user's current
                    // scroll position (not initialScrollPosition, and not an anchor-char position
                    // that visibly shifts when math attachments arrive above the viewport).
                    if let scrollView = self.scrollView {
                        self.pendingDiagramScrollY = scrollView.contentView.bounds.origin.y
                    }
                    self.lastContent = nil
                    self.elementCache.removeAll()
                    // Force SwiftUI to re-evaluate the view body so updateNSView fires and
                    // rebuilds with the now-cached image. Without this, the math/Mermaid
                    // placeholder text stays on screen until the user scrolls/types/resizes
                    // (regression introduced when adding the 100ms coalesce in Phase 5).
                    // Keyed per-document (Plan 003) so this bump only invalidates this document's
                    // own tick, not a shared counter every open pane's ObservableObject subscriber
                    // would otherwise treat as "something changed, re-render everything".
                    DocumentManager.shared.diagramRenderTicks[myDocumentId, default: 0] &+= 1
                }
            }
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }

            // Debounce scroll position saving
            scrollDebounceTimer?.invalidate()
            scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: Timing.scrollPositionPersistDebounce, repeats: false) { [weak self, weak clipView] _ in
                Task { @MainActor [weak self, weak clipView] in
                    guard let clipView else { return }
                    self?.onScrollPositionChanged?(clipView.bounds.origin.y)
                }
            }
        }

        deinit {
            // No assumeIsolated (traps if the last release happens off-main); deinit has
            // exclusive property access, and Timer.invalidate / removeObserver are
            // nonisolated APIs.
            scrollDebounceTimer?.invalidate()
            diagramCoalesceTimer?.invalidate()
            rebuildDebounceTimer?.invalidate()
            interruptibleScrollTimer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }

    // MARK: - Build Attributed String

    private func buildAttributedString(coordinator: Coordinator) -> (NSAttributedString, [String: NSRange]) {
        let parser = MarkdownParser.shared
        let elements = parser.parse(content)
        let headings = parser.extractHeadings(content)
        let result = NSMutableAttributedString()
        var headingRanges: [String: NSRange] = [:]
        // P6: collect the ids actually present in this build so stale cache entries can be swept
        // afterward. Keys are content-addressed, so without a sweep every edit leaves the previous
        // version of the edited element behind, growing elementCache unboundedly for the session.
        var liveKeys = Set<String>()

        // Pair headings to slug IDs as we encounter them in the parsed element stream.
        // Previously this used a positional index into `headings`, which drifted whenever
        // `extractHeadings` returned an entry that `parse()` did not (e.g., a `#` line inside a
        // fenced code block). Now `extractHeadings` skips fenced/frontmatter, so both sequences
        // are aligned — but we also track slug-counts here to handle duplicates defensively.
        var parsedHeadingIndex = 0

        // Collapsed by default; the reader opens it from its header row (see appendFrontmatter).
        let frontmatterExpanded = coordinator.documentId.map { coordinator.expandedFrontmatterDocuments.contains($0) } ?? false

        // Manage element cache — invalidate on zoom, font, width, or preview theme. Several
        // renderers bake resolved RGB into cached fragments, so the selected palette belongs in
        // the cache key even when the Markdown content itself did not change.
        let zoomKey = "\(zoomLevel)-\(styleKey)"
        coordinator.imageResources.prepare(documentId: documentId, content: content, style: zoomKey)
        var resources = self
        resources.imageResources = coordinator.imageResources
        let renderer = PreviewRenderer(
            mainFontID: mainFontID,
            fixedFontID: fixedFontID,
            mainFontSize: mainFontSize,
            fixedFontSize: fixedFontSize,
            theme: theme,
            zoomLevel: zoomLevel,
            contentWidth: contentWidth,
            tableColumnConfiguration: tableColumnConfiguration,
            baseURL: baseURL,
            resources: resources
        )
        let cacheValid = coordinator.lastZoomKey == zoomKey
        if !cacheValid {
            coordinator.elementCache.removeAll()
            coordinator.lastZoomKey = zoomKey
        }

        for element in elements {
            // With frontmatter off the document starts at its first content element.
            if case .frontmatter = element, !showsFrontmatter { continue }

            let startPos = result.length

            // Elements whose appearance depends on an out-of-band async resource (remote images,
            // Mermaid/LaTeX diagrams rendered by WebRenderer, HTML blocks converted via WebKit) must
            // NOT be cached by content id: their first render inserts a "[Image: alt]" / "[Rendering…]"
            // placeholder, and caching that placeholder freezes the wrong visual even after the
            // diagramDidRender notification clears `elementCache`.
            // Frontmatter is skipped too: its rendering depends on the toggle state, not only
            // on its content.
            let skipCache: Bool
            switch element {
            case .image, .mermaidBlock, .displayMath, .htmlBlock, .frontmatter:
                skipCache = true
            default:
                skipCache = false
            }
            if !skipCache { liveKeys.insert(element.id) }

            if !skipCache, cacheValid, let cached = coordinator.elementCache[element.id] {
                result.append(cached)
            } else {
                renderer.render(element, to: result, frontmatterExpanded: frontmatterExpanded)
                let endPos = result.length
                if !skipCache, endPos > startPos {
                    let fragment = result.attributedSubstring(from: NSRange(location: startPos, length: endPos - startPos))
                    coordinator.elementCache[element.id] = fragment
                }
            }

            // Track heading ranges for outline navigation. extractHeadings now skips
            // lines inside fenced code blocks, so the parsed-element heading order and the
            // outline heading order align 1:1.
            if element.isHeading, parsedHeadingIndex < headings.count {
                headingRanges[headings[parsedHeadingIndex].id] = NSRange(location: startPos, length: result.length - startPos)
                parsedHeadingIndex += 1
            }
        }

        // P6: evict cache entries whose elements are no longer in the document (e.g. the previous
        // content of an edited element), keeping the cache bounded to the current element stream.
        if coordinator.elementCache.count > liveKeys.count {
            coordinator.elementCache = coordinator.elementCache.filter { liveKeys.contains($0.key) }
        }

        // C6: search highlighting is applied after the rebuild via updateMatchHighlighting (which
        // paints the ranges from findMatchRanges, honoring regex and case-sensitive mode), not here
        // with a literal case-insensitive search that ignored those flags.

        return (result, headingRanges)
    }
}

// MARK: - Pictures, diagrams, and math

/// The preview's resources: pictures load from disk or the network, Mermaid and KaTeX render in
/// `WebRenderer`. A missing one is requested and nil returned (the renderer shows a placeholder);
/// when it lands, `.diagramRendered` makes this document's preview rebuild.
extension MarkdownTextView: PreviewResourceSource {
    func mermaidDiagram(_ code: String) -> NSImage? {
        let cacheKey = "mermaid-\(theme.cacheKey)-" + code
        if let cached = imageResources?.image(forKey: cacheKey, cache: Coordinator.diagramCache) {
            return cached
        }
        // Captured locally so the notification carries the document this diagram belongs
        // to — a different pane's coordinator ignores it (Plan 003).
        let docId = documentId
        let theme = theme
        let resources = imageResources
        let generation = resources?.generation ?? 0
        Task { @MainActor [weak resources] in
            WebRenderer.shared.renderMermaid(code, theme: theme) { image in
                guard let image = image else { return }
                Coordinator.diagramCache.setObject(image, forKey: cacheKey as NSString, cost: PreviewImage.decodedByteCost(image))
                resources?.insert(image, forKey: cacheKey, generation: generation)
                NotificationCenter.default.post(name: .diagramRendered, object: docId)
            }
        }
        return nil
    }

    func math(_ latex: String, displayMode: Bool) -> NSImage? {
        let cacheKey = "math-\(displayMode ? "display" : "inline")-\(theme.cacheKey)-" + latex
        if let cached = imageResources?.image(forKey: cacheKey, cache: Coordinator.diagramCache) {
            return cached
        }
        // Captured locally so the notification carries the document this math belongs to — a
        // different pane's coordinator ignores it (Plan 003).
        let docId = documentId
        let foreground = theme.textHex
        let resources = imageResources
        let generation = resources?.generation ?? 0
        Task { @MainActor [weak resources] in
            WebRenderer.shared.renderMath(latex, displayMode: displayMode, foregroundHex: foreground) { image in
                guard let image = image else { return }
                Coordinator.diagramCache.setObject(image, forKey: cacheKey as NSString, cost: PreviewImage.decodedByteCost(image))
                resources?.insert(image, forKey: cacheKey, generation: generation)
                NotificationCenter.default.post(name: .diagramRendered, object: docId)
            }
        }
        return nil
    }

    func image(path: String) -> NSImage? {
        // Decode for a 2x display using the capped column width, stable across window resizes.
        // Cache by resolution so wider presets never reuse an undersized thumbnail.
        let pixelWidth = contentWidth.attachmentMaxWidth.map { Int(ceil($0 * 2)) }
        // Local paths are relative to their document; remote URLs already identify a resource.
        let cacheKey: String = {
            let location = path.hasPrefix("http://") || path.hasPrefix("https://")
                ? path : (baseURL?.deletingLastPathComponent().path ?? "") + "\u{1F}" + path
            return "image-\(pixelWidth ?? 0)\u{1F}" + location
        }()
        if let cached = imageResources?.image(forKey: cacheKey, cache: Coordinator.imageCache) {
            return cached
        }

        // Remote URL — return nil (placeholder) and load asynchronously.
        // Posts .diagramRendered when the image lands so the preview rebuilds and the placeholder
        // text gets replaced with the actual image. (Piggybacks on the existing diagram refresh hook.)
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            guard !Coordinator.remoteImageFailures.contains(cacheKey),
                  !Coordinator.remoteImageInFlight.contains(cacheKey),
                  let url = URL(string: path) else {
                return nil
            }

            Coordinator.remoteImageInFlight.insert(cacheKey)
            // Captured locally (not via implicit `self`) so the notification carries the
            // document this image load belongs to — a different pane's coordinator ignores it
            // (Plan 003).
            let docId = documentId
            let resources = imageResources
            let generation = resources?.generation ?? 0
            // URLSession instead of the old synchronous NSImage(contentsOf:) on a global queue —
            // that path had no timeout, so a hung server pinned a dispatch thread indefinitely.
            Task { [weak resources] in
                let image: NSImage?
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    image = PreviewImage.load(data: data, maximumPixelWidth: pixelWidth)
                } else {
                    image = nil
                }
                await MainActor.run {
                    Coordinator.remoteImageInFlight.remove(cacheKey)
                    guard let image = image else {
                        Coordinator.remoteImageFailures.insert(cacheKey)
                        return
                    }

                    Coordinator.remoteImageFailures.remove(cacheKey)
                    Coordinator.imageCache.setObject(image, forKey: cacheKey as NSString, cost: PreviewImage.decodedByteCost(image))
                    resources?.insert(image, forKey: cacheKey, generation: generation)
                    NotificationCenter.default.post(name: .diagramRendered, object: docId)
                }
            }
            return nil
        }

        // Activate directory security scope for relative image access
        var accessingDirectory = false
        var dirURL: URL?
        if let bookmark = directoryBookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                dirURL = resolved
                accessingDirectory = resolved.startAccessingSecurityScopedResource()
            }
        }
        defer {
            if accessingDirectory, let dir = dirURL {
                dir.stopAccessingSecurityScopedResource()
            }
        }

        // Local file — synchronous is fine for local disk I/O
        let resolvedURL: URL?

        let absoluteURL = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: absoluteURL.path) {
            resolvedURL = absoluteURL
        } else if let base = baseURL?.deletingLastPathComponent() {
            let relativeURL = base.appendingPathComponent(path)
            resolvedURL = FileManager.default.fileExists(atPath: relativeURL.path) ? relativeURL : nil
        } else {
            resolvedURL = nil
        }

        if let url = resolvedURL, let image = PreviewImage.load(contentsOf: url, maximumPixelWidth: pixelWidth) {
            Coordinator.imageCache.setObject(image, forKey: cacheKey as NSString, cost: PreviewImage.decodedByteCost(image))
            imageResources?.insert(image, forKey: cacheKey, generation: imageResources?.generation ?? 0)
            return image
        }

        return nil
    }
}
