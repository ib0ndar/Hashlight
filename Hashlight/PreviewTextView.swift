import AppKit
import CoreText

// MARK: - NSFont Extensions

extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weight]
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }

    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

// MARK: - Preview text view (column alignment)

/// The preview's NSTextView, able to place its fixed-width text column left, center, or right
/// within the pane.
///
/// Why a subclass: `textContainerInset` is symmetric — the same value pads both sides — so it
/// can express "centered" at best and can never express "right". Overriding
/// `textContainerOrigin` is AppKit's supported hook for positioning the container; drawing,
/// hit-testing (link clicks, selection), and temporary-attribute highlights all route through
/// it, so everything stays consistent with the moved column.
final class PreviewTextView: NSTextView {
    var contentAlignment: PreviewContentAlignment = .left {
        didSet {
            guard oldValue != contentAlignment else { return }
            invalidateTextContainerOrigin()
            needsDisplay = true
        }
    }

    /// Maximum column width from the Content Width setting; nil = fill the pane.
    var preferredColumnWidth: CGFloat? = 800 {
        didSet {
            guard oldValue != preferredColumnWidth else { return }
            // A settings change reflows every line, so a raw scroll offset would land on
            // different text. (Resizes skip this — they take the cheap path and behave like
            // any wrapping text view; see viewDidEndLiveResize.)
            keepingReadingPosition { updateColumnWidth() }
        }
    }

    nonisolated private static let minimumColumnWidth: CGFloat = 200

    /// Pure width math (unit-tested). Not yet sized (width 0 during construction) → use the
    /// preferred width so the first layout isn't done at a throwaway size.
    nonisolated static func columnWidth(preferred: CGFloat?, viewWidth: CGFloat, inset: CGFloat) -> CGFloat {
        guard viewWidth > 0 else { return preferred ?? 800 }
        let available = max(minimumColumnWidth, viewWidth - inset * 2)
        guard let preferred else { return available }
        return min(preferred, available)
    }

    private func updateColumnWidth() {
        guard let container = textContainer else { return }
        let width = Self.columnWidth(
            preferred: preferredColumnWidth,
            viewWidth: bounds.width,
            inset: textContainerInset.width
        )
        // Equality guard: setting containerSize relayouts, relayout changes our height, and
        // a height change re-enters setFrameSize → here. Same width must be a no-op.
        if abs(container.containerSize.width - width) > 0.5 {
            // Content-sized tables follow the column's width; the resize relayouts them.
            if let textStorage {
                PreviewTableLayout.fitTables(in: textStorage, availableWidth: width - 2 * container.lineFragmentPadding)
            }
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        invalidateTextContainerOrigin()
        needsDisplay = true
    }

    /// Page Margin sets the horizontal inset, which reflows the column like a Content Width
    /// change; the reader's place is kept the same way.
    func setTextContainerInsetKeepingReadingPosition(_ inset: NSSize) {
        guard inset != textContainerInset else { return }
        keepingReadingPosition {
            textContainerInset = inset
            updateColumnWidth()
        }
    }

    /// The reader's place: the character at the top of the viewport and how far below the top
    /// of that character's line fragment the viewport's top edge lies.
    private struct ReadingAnchor {
        let characterIndex: Int
        let offset: CGFloat
        let fragmentHeight: CGFloat
    }

    /// Runs a change that reflows the column, then puts the reader back at the same place.
    /// The restore is deferred: callers run inside updateNSView, and scrolling fires the
    /// bounds-change observer synchronously; nothing may react to that during the SwiftUI update
    /// pass (the hazard reportMatchCount defers around). A Content Width change also rebuilds the
    /// text in that pass; the same content keeps its character indices, so the anchor still holds.
    private func keepingReadingPosition(_ change: () -> Void) {
        let anchor = readingAnchor()
        change()
        if let anchor {
            Task { @MainActor [weak self] in
                self?.restoreReadingPosition(anchor)
            }
        }
    }

    private func readingAnchor() -> ReadingAnchor? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0,
              enclosingScrollView != nil else { return nil }
        let top = visibleRect.minY - textContainerOrigin.y
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 1, y: max(0, top) + 1), in: textContainer)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return ReadingAnchor(
            characterIndex: layoutManager.characterIndexForGlyph(at: glyph),
            offset: top - fragment.minY,
            fragmentHeight: fragment.height
        )
    }

    /// Pure math (unit-tested): where the viewport's top edge goes once the anchor's line
    /// fragment has moved or changed height. Inside the fragment the offset scales with it, so
    /// a rescaled image keeps the same part at the top; outside it (the top inset, or space below
    /// a short table cell) the offset is kept as it was.
    nonisolated static func anchoredTop(offset: CGFloat, fragmentHeight: CGFloat, newFragment: NSRect) -> CGFloat {
        guard fragmentHeight > 0, offset >= 0, offset <= fragmentHeight else { return newFragment.minY + offset }
        return newFragment.minY + offset / fragmentHeight * newFragment.height
    }

    private func restoreReadingPosition(_ anchor: ReadingAnchor) {
        guard let layoutManager, let textContainer, let scrollView = enclosingScrollView,
              let storage = textStorage, anchor.characterIndex < storage.length else { return }
        // One-off full layout (settings change only): the view's height is stale until the
        // reflow completes, and the clamp below needs the real one.
        layoutManager.ensureLayout(for: textContainer)
        sizeToFit()
        let glyph = layoutManager.glyphIndexForCharacter(at: anchor.characterIndex)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let top = Self.anchoredTop(offset: anchor.offset, fragmentHeight: anchor.fragmentHeight, newFragment: fragment)
        let maxY = max(0, frame.height - scrollView.contentView.bounds.height)
        let y = min(max(0, top + textContainerOrigin.y), maxY)
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Code-block copy button

    nonisolated static let codeBlockKey = NSAttributedString.Key("Hashlight.codeBlock")
    /// A range PreviewLayoutManager draws a rounded card behind (code blocks, frontmatter).
    nonisolated static let cardKey = NSAttributedString.Key("Hashlight.card")
    nonisolated static let tableKey = NSAttributedString.Key("Hashlight.table")
    /// Marks the frontmatter block's header row; a click on that row toggles the block.
    nonisolated static let frontmatterToggleKey = NSAttributedString.Key("Hashlight.frontmatterToggle")

    var onFrontmatterToggle: (() -> Void)?

    /// A click on the frontmatter header row toggles the block instead of moving the
    /// insertion point or starting a selection.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, isOnFrontmatterToggle(convert(event.locationInWindow, from: nil)) {
            onFrontmatterToggle?()
            return
        }
        super.mouseDown(with: event)
    }

    /// Whether `point` (view coordinates) lies on the line of the frontmatter header row.
    private func isOnFrontmatterToggle(_ point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return false }
        let origin = textContainerOrigin
        let probe = NSPoint(
            x: min(max(point.x - origin.x, 1), max(1, textContainer.containerSize.width - 1)),
            y: point.y - origin.y
        )
        let glyph = layoutManager.glyphIndex(for: probe, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyph)
        guard charIndex < storage.length,
              storage.attribute(Self.frontmatterToggleKey, at: charIndex, effectiveRange: nil) != nil else { return false }
        // glyphIndex(for:) returns the nearest glyph even for points outside all text.
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
        return point.y >= line.minY && point.y <= line.maxY
    }

    private var hoverTrackingArea: NSTrackingArea?
    private var hoveredCodeBlock: CodeBlockPayload?
    private lazy var codeCopyButton: CodeCopyButton = {
        let button = CodeCopyButton(target: self, action: #selector(copyHoveredCodeBlock))
        button.isHidden = true
        addSubview(button)
        return button
    }()
    // nonisolated(unsafe): main-actor only in practice; annotated solely so nonisolated
    // deinit can invalidate it (deinit has exclusive access).
    nonisolated(unsafe) private var copyConfirmationTimer: Timer?

    deinit {
        copyConfirmationTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A rebuild replaces the storage wholesale; the hovered block's geometry is then
        // meaningless, so drop the button until the mouse next moves.
        NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: nil)
        if window != nil, let textStorage {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(previewStorageDidEdit(_:)),
                name: NSTextStorage.didProcessEditingNotification,
                object: textStorage
            )
        }
    }

    @objc private func previewStorageDidEdit(_ note: Notification) {
        guard let storage = note.object as? NSTextStorage,
              storage.editedMask.contains(.editedCharacters) else { return }
        hideCodeCopyButton()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        guard let (payload, rect) = codeBlock(at: point) else {
            hideCodeCopyButton()
            return
        }
        if payload !== hoveredCodeBlock {
            hoveredCodeBlock = payload
            codeCopyButton.cardStyle = payload.style
            codeCopyButton.showCopyState()
        }
        // Top-right corner of the card, on the first line's row, left of the language label.
        let size = CodeCopyButton.size
        let labelWidth = payload.label.map { ceil($0.size().width) + 8 } ?? 0
        codeCopyButton.frame = NSRect(
            x: rect.maxX - CodeBlockCard.labelInset - labelWidth - size.width,
            y: rect.minY + CodeBlockCard.verticalPadding - 3,
            width: size.width,
            height: size.height
        )
        codeCopyButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Exiting INTO the button (a subview) also fires this; only hide when the pointer
        // has really left the text view.
        let point = convert(event.locationInWindow, from: nil)
        if !bounds.contains(point) { hideCodeCopyButton() }
    }

    private func hideCodeCopyButton() {
        guard hoveredCodeBlock != nil || !codeCopyButton.isHidden else { return }
        hoveredCodeBlock = nil
        codeCopyButton.isHidden = true
    }

    /// The code block whose card contains `point` vertically (view coordinates), if any.
    /// Vertical-only containment is deliberate: hovering to the right of a short line should
    /// still count as "in the block".
    private func codeBlock(at point: NSPoint) -> (CodeBlockPayload, NSRect)? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let probe = NSPoint(
            x: min(max(point.x - origin.x, 1), max(1, textContainer.containerSize.width - 1)),
            y: point.y - origin.y
        )
        let glyph = layoutManager.glyphIndex(for: probe, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyph)
        guard charIndex < storage.length else { return nil }
        var range = NSRange()
        guard let payload = storage.attribute(
            Self.codeBlockKey, at: charIndex,
            longestEffectiveRange: &range,
            in: NSRange(location: 0, length: storage.length)
        ) as? CodeBlockPayload else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = (layoutManager as? PreviewLayoutManager)?.codeBlockCardRect(forCharacterRange: range, in: textContainer)
            ?? layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        // glyphIndex(for:) returns the NEAREST glyph even for points outside all text.
        guard point.y >= rect.minY, point.y <= rect.maxY else { return nil }
        return (payload, rect)
    }

    @objc private func copyHoveredCodeBlock() {
        guard let payload = hoveredCodeBlock else { return }
        copyToPasteboard(payload.code)
        // Confirm at the point of action (the button itself), not with a distant toast.
        codeCopyButton.showCopiedState()
        copyConfirmationTimer?.invalidate()
        copyConfirmationTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.codeCopyButton.showCopyState()
            }
        }
    }

    /// Test seam: the suite substitutes a private named pasteboard so running tests never
    /// clobbers the user's real clipboard.
    var pasteboard: NSPasteboard = .general

    private func copyToPasteboard(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Right-click → "Copy Code Block": the hover button is unreachable by keyboard and
    /// VoiceOver, so the same action must exist somewhere that isn't hover-gated.
    override func menu(for event: NSEvent) -> NSMenu? {
        let baseMenu = super.menu(for: event)
        let point = convert(event.locationInWindow, from: nil)
        guard let (payload, _) = codeBlock(at: point) else { return baseMenu }
        let menu = baseMenu ?? NSMenu()
        let item = NSMenuItem(title: "Copy Code Block", action: #selector(copyCodeBlockFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = payload
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func copyCodeBlockFromMenu(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? CodeBlockPayload else { return }
        copyToPasteboard(payload.code)
    }

    // MARK: Column geometry

    override var textContainerOrigin: NSPoint {
        let base = super.textContainerOrigin
        guard let container = textContainer else { return base }
        let x = Self.containerOriginX(
            alignment: contentAlignment,
            viewWidth: bounds.width,
            containerWidth: container.containerSize.width,
            inset: textContainerInset.width
        )
        return NSPoint(x: x, y: base.y)
    }

    /// A resize changes both how wide the column may be and the free space it floats in
    /// (AppKit caches the origin, so it must be invalidated).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateColumnWidth()
    }

    /// When a live resize ends, NSTextView scrolls the top of the first line fragment in view
    /// back to the top of the viewport (`-_setFrameSize:forceScroll:`). An image or diagram is a
    /// single fragment, so letting go of the window's edge jumped up to its top. Keep the
    /// position the reader saw while resizing.
    override func viewDidEndLiveResize() {
        guard let scrollView = enclosingScrollView else {
            super.viewDidEndLiveResize()
            return
        }
        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        super.viewDidEndLiveResize()
        guard clipView.bounds.origin != origin else { return }
        let kept = clipView.constrainBoundsRect(NSRect(origin: origin, size: clipView.bounds.size))
        clipView.setBoundsOrigin(kept.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Pure placement math (unit-tested). The inset is a MINIMUM margin on both sides: when
    /// the pane has no free space beyond column + margins, every alignment collapses to the
    /// left position instead of pushing the column off-screen.
    nonisolated static func containerOriginX(
        alignment: PreviewContentAlignment,
        viewWidth: CGFloat,
        containerWidth: CGFloat,
        inset: CGFloat
    ) -> CGFloat {
        let freeSpace = viewWidth - containerWidth - inset * 2
        guard freeSpace > 0 else { return inset }
        switch alignment {
        case .left: return inset
        case .center: return inset + freeSpace / 2
        case .right: return inset + freeSpace
        }
    }
}

// MARK: - Setting up a preview

extension PreviewTextView {
    /// A scroll view holding a preview text view as every preview uses it: TextKit 1 with
    /// `PreviewLayoutManager` (code and frontmatter cards, rounded tables), read-only but
    /// selectable, with a column whose width the view computes itself. The app's preview and
    /// the Quick Look extension both start from this.
    static func makeScrollView(
        theme: PreviewTheme,
        contentAlignment: PreviewContentAlignment,
        contentWidth: PreviewContentWidth,
        pageMargin: PreviewPageMargin,
        verticalInset: CGFloat
    ) -> (scrollView: NSScrollView, textView: PreviewTextView) {
        // scrollableTextView() instantiates the receiving class, so the factory's stock
        // scroll-view configuration is unchanged.
        let scrollView = PreviewTextView.scrollableTextView()
        let textView = scrollView.documentView as! PreviewTextView
        textView.contentAlignment = contentAlignment

        // The factory makes a TextKit 2 view; reading `layoutManager` switches it to TextKit 1
        // (which the preview uses), and the preview's own layout manager then draws the
        // code-block cards.
        _ = textView.layoutManager
        textView.textContainer?.replaceLayoutManager(PreviewLayoutManager())

        textView.isEditable = false
        textView.isSelectable = true
        scrollView.drawsBackground = true
        textView.apply(theme)
        textView.textContainerInset = NSSize(width: pageMargin.points, height: verticalInset)
        textView.isRichText = true
        textView.allowsUndo = false

        // Column width is owned by PreviewTextView: a maximum (Content Width setting) that
        // shrinks to fit narrower panes. widthTracksTextView stays false — the view computes
        // the width itself so it can cap it. (This used to be a hard 800pt, which clipped the
        // right edge of every line in any pane under 900pt, such as Focus Mode.)
        textView.textContainer?.widthTracksTextView = false
        textView.preferredColumnWidth = contentWidth.points

        // Links are the document's own; nothing is detected in plain text.
        textView.isAutomaticLinkDetectionEnabled = false
        return (scrollView, textView)
    }

    /// Colors the text view and its scroll view for `theme`.
    func apply(_ theme: PreviewTheme) {
        appearance = theme.appearance
        backgroundColor = theme.backgroundColor
        enclosingScrollView?.appearance = theme.appearance
        enclosingScrollView?.backgroundColor = theme.backgroundColor
    }
}

extension NSTextView {
    /// Shows a freshly built preview document: fits its content-sized tables to the current
    /// column, then replaces the text in one edit.
    func showPreview(_ attributedString: NSAttributedString) {
        if let textContainer {
            PreviewTableLayout.fitTables(
                in: attributedString,
                availableWidth: textContainer.containerSize.width - 2 * textContainer.lineFragmentPadding
            )
        }
        guard let textStorage else { return }
        // Replacing a populated attributed range inserts each new attribute run before
        // removing the old runs. Clearing first avoids quadratic run-array movement.
        textStorage.beginEditing()
        textStorage.deleteCharacters(in: NSRange(location: 0, length: textStorage.length))
        textStorage.append(attributedString)
        textStorage.endEditing()
    }
}

/// A rounded card the layout manager draws behind the attributed range tagged with
/// `PreviewTextView.cardKey`: code blocks and the folded frontmatter. A class (identity
/// equality) on purpose, so adjacent cards do not merge into one effective range. Nonisolated,
/// like the layout manager that reads it while drawing.
nonisolated class PreviewCardPayload: NSObject {
    /// Drawn in the card's top-right corner (a code block's language); nil for none.
    let label: NSAttributedString?
    let style: CodeBlockCard.Style

    init(label: NSAttributedString? = nil, style: CodeBlockCard.Style) {
        self.label = label
        self.style = style
        super.init()
    }
}

/// Raw source of one rendered code block, attached to its attributed range under
/// `PreviewTextView.codeBlockKey` for the copy button and context menu (and under `cardKey`
/// for the drawing) — see appendCodeBlock.
nonisolated final class CodeBlockPayload: PreviewCardPayload {
    let code: String

    init(code: String, label: NSAttributedString? = nil, style: CodeBlockCard.Style = CodeBlockCard.Style(fill: .clear, border: .clear)) {
        self.code = code
        super.init(label: label, style: style)
    }
}

/// The frontmatter disclosure row's markers: filled triangles, as in Xcode, with the text
/// presentation selector so no font renders them as emoji.
nonisolated enum FrontmatterFold {
    static let collapsedMarker = "\u{25B6}\u{FE0E}"
    static let expandedMarker = "\u{25BC}\u{FE0E}"
    /// Tighter than the code cards: the fold is a slim row, not a content block.
    static let verticalPadding: CGFloat = 6
    static let horizontalPadding: CGFloat = 10
}

/// Geometry of the code-block card, shared by the attributed text (padding through paragraph
/// indents and spacing), the layout manager (drawing), and the text view (the copy button).
nonisolated enum CodeBlockCard {
    struct Style {
        let fill: NSColor
        let border: NSColor
    }

    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
    /// Text inset from the card's left and right edges (the container's line fragment
    /// padding adds to it).
    static let horizontalPadding: CGFloat = 12
    /// Paragraph spacing before the first line and after the last one; both are inside the
    /// card because line fragment rects include them.
    static let verticalPadding: CGFloat = 10
    /// The label's distance from the card's right edge, and the gap kept between it and the
    /// first code line.
    static let labelInset: CGFloat = 12
    static let labelGap: CGFloat = 20

    /// Where the label sits for a card of `rect` (the text view is flipped: y grows downward).
    static func labelOrigin(for label: NSAttributedString, in rect: NSRect) -> NSPoint {
        let size = label.size()
        return NSPoint(x: rect.maxX - labelInset - ceil(size.width), y: rect.minY + verticalPadding + 2)
    }
}

/// Marks one rendered table's attributed range under `PreviewTextView.tableKey` so the layout
/// manager can round its corners. A class (identity equality) on purpose — see appendTable.
/// `columnMetrics` is set for content-sized tables (column weighting off).
nonisolated final class TablePayload: NSObject {
    let borderColor: NSColor
    let columnMetrics: TableColumnMetrics?
    init(borderColor: NSColor, columnMetrics: TableColumnMetrics? = nil) {
        self.borderColor = borderColor
        self.columnMetrics = columnMetrics
        super.init()
    }
}

/// What a content-sized table needs to fit itself to any width, as whole-cell widths (text plus
/// `PreviewTableLayout.cellChrome`): each column's widest unwrapped line and longest word, the
/// minimum column width (4em of the table font), and the widest row that spans the table.
nonisolated struct TableColumnMetrics: Equatable, Sendable {
    let natural: [CGFloat]
    let words: [CGFloat]
    let minimum: CGFloat
    let spanning: CGFloat
}

/// Measures table cells with CoreText. One measurer serves a whole table, so the line-break
/// tokenizer (expensive to create) is reused across its cells.
nonisolated final class TableCellMeasurer {
    private let tokenizer = CFStringTokenizerCreate(nil, "" as CFString, CFRange(location: 0, length: 0), kCFStringTokenizerUnitLineBreak, nil)

    /// The widest unwrapped line of `cell` and its widest unbreakable segment, in points. Lines
    /// no wider than `knownWord` cannot hold a wider word, so their words are not measured.
    func measure(_ cell: NSAttributedString, knownWord: CGFloat = 0) -> (natural: CGFloat, longestWord: CGFloat) {
        let text = cell.string as NSString
        var natural: CGFloat = 0
        var longestWord: CGFloat = 0
        var lineStart = 0
        while lineStart < text.length {
            let newline = text.range(of: "\n", range: NSRange(location: lineStart, length: text.length - lineStart))
            let lineEnd = newline.location == NSNotFound ? text.length : newline.location
            if lineEnd > lineStart {
                let range = NSRange(location: lineStart, length: lineEnd - lineStart)
                let line = range.length == text.length ? cell : cell.attributedSubstring(from: range)
                let size = measureLine(line, knownWord: max(knownWord, longestWord))
                natural = max(natural, size.width)
                longestWord = max(longestWord, size.longestWord)
            }
            lineStart = lineEnd + 1
        }
        return (natural, longestWord)
    }

    private func measureLine(_ line: NSAttributedString, knownWord: CGFloat) -> (width: CGFloat, longestWord: CGFloat) {
        let ctLine = CTLineCreateWithAttributedString(line)
        var width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(ctLine))
        var longestWord: CGFloat = 0

        // CoreText does not know text attachments (images, rendered math); add their widths.
        line.enumerateAttribute(.attachment, in: NSRange(location: 0, length: line.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let attachmentWidth = attachment.bounds.width > 0 ? attachment.bounds.width : (attachment.image?.size.width ?? 0)
            width += attachmentWidth
            longestWord = max(longestWord, attachmentWidth)
        }
        guard width > knownWord else { return (width, longestWord) }

        let string = line.string as NSString
        CFStringTokenizerSetString(tokenizer, string, CFRange(location: 0, length: string.length))
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let token = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            var end = token.location + token.length
            while end > token.location,
                  let scalar = Unicode.Scalar(string.character(at: end - 1)),
                  CharacterSet.whitespaces.contains(scalar) {
                end -= 1
            }
            let start = CTLineGetOffsetForStringIndex(ctLine, token.location, nil)
            let finish = CTLineGetOffsetForStringIndex(ctLine, end, nil)
            longestWord = max(longestWord, abs(finish - start))
        }
        return (width, longestWord)
    }
}

/// Geometry of preview tables. Cells follow Xcode 27's Markdown tables: body-size text, 4 × 8
/// pt padding, a light neutral header, no row stripes. With column weighting off the columns
/// are sized to their content (`MarkdownTableColumnLayout.fittedWidths`): measured once per
/// build, and fitted again whenever the text column's width changes, without a rebuild.
nonisolated enum PreviewTableLayout {
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 4
    static let borderWidth: CGFloat = 0.5
    /// A cell's width beyond its text: padding and border on both sides, and a point for TextKit
    /// rounding the half-point borders. Line fragment padding does not apply inside table cells.
    static var cellChrome: CGFloat { 2 * (horizontalPadding + borderWidth) + 1 }
    /// A column never gets narrower than this many ems of the table font, unless the columns
    /// cannot fit otherwise (Xcode's `minmax(4em, auto)`).
    static let minimumColumnEms: CGFloat = 4

    static var headerBackground: NSColor { NSColor(white: 0.5, alpha: 0.1) }

    /// The widest unwrapped line of a cell and its widest unbreakable segment (the line-break
    /// opportunities TextKit wraps at), in points, without the cell's chrome.
    static func measure(_ cell: NSAttributedString) -> (natural: CGFloat, longestWord: CGFloat) {
        TableCellMeasurer().measure(cell)
    }

    /// Whole-cell width for measured text: rounded up, plus a point so TextKit never wraps a
    /// line that CoreText measured as fitting, plus the cell's chrome.
    static func cellWidth(forText width: CGFloat) -> CGFloat {
        ceil(width) + 1 + cellChrome
    }

    /// Fits every content-sized table in `string` to `availableWidth` (the text container's
    /// width less its line fragment padding). It changes the tables' blocks, not the string;
    /// the caller's storage edit or container resize invalidates the layout.
    static func fitTables(in string: NSAttributedString, availableWidth: CGFloat) {
        string.enumerateAttribute(PreviewTextView.tableKey, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard let metrics = (value as? TablePayload)?.columnMetrics else { return }
            apply(widths(for: metrics, available: availableWidth), toTableIn: range, of: string)
        }
    }

    static func widths(for metrics: TableColumnMetrics, available: CGFloat) -> [CGFloat] {
        MarkdownTableColumnLayout.fittedWidths(
            natural: metrics.natural,
            words: metrics.words,
            minimum: metrics.minimum,
            spanning: metrics.spanning,
            available: available
        )
    }

    /// Sets each cell's content width from whole-cell column widths; a spanning cell takes the
    /// sum of its columns. The table keeps its percentage width: cells with absolute widths do
    /// not stretch to fill it, so it shrinks to its content. (An absolute table width equal to
    /// the cells' sum squeezes them, because TextKit rounds each cell's half-point borders up.)
    static func apply(_ widths: [CGFloat], toTableIn range: NSRange, of string: NSAttributedString) {
        string.enumerateAttribute(.paragraphStyle, in: range) { value, _, _ in
            guard let block = (value as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock else { return }
            let start = block.startingColumn
            let end = min(widths.count, start + block.columnSpan)
            guard start < end else { return }
            let width = widths[start..<end].reduce(0, +)
            block.setContentWidth(max(1, width - cellChrome), type: .absoluteValueType)
        }
    }
}

/// The preview's TextKit 1 layout manager. It draws a rounded card behind every code block
/// before the standard backgrounds (so selection and find highlights stay on top), clips each
/// table's cell backgrounds and borders to a rounded rectangle, and strokes that outline over
/// them. `NSLayoutManager` is not main-actor-isolated, so neither is the subclass.
nonisolated final class PreviewLayoutManager: NSLayoutManager {
    // Key by occurrence, not payload identity: identical cached blocks can appear twice.
    private var tableFrameCache: [Int: TableFrame] = [:]

    override func invalidateLayout(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) {
        tableFrameCache.removeAll(keepingCapacity: true)
        super.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: actualCharRange)
    }

    override func textContainerChangedGeometry(_ container: NSTextContainer) {
        tableFrameCache.removeAll(keepingCapacity: true)
        super.textContainerChangedGeometry(container)
    }

    override func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        tableFrameCache.removeAll(keepingCapacity: true)
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawCodeBlockCards(forGlyphRange: glyphsToShow, at: origin)

        let tables = tableFrames(intersecting: glyphsToShow)
        guard !tables.isEmpty else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        // The standard drawing of a cell paints its whole block, so a table's part of the
        // range is drawn in one call under a rounded clip; the rest is drawn as usual.
        var cursor = glyphsToShow.location
        let end = NSMaxRange(glyphsToShow)
        for table in tables {
            let tableStart = max(table.glyphRange.location, cursor)
            let tableEnd = min(NSMaxRange(table.glyphRange), end)
            if tableStart > cursor {
                super.drawBackground(forGlyphRange: NSRange(location: cursor, length: tableStart - cursor), at: origin)
            }
            NSGraphicsContext.saveGraphicsState()
            Self.tablePath(for: table.rect.offsetBy(dx: origin.x, dy: origin.y)).addClip()
            super.drawBackground(forGlyphRange: NSRange(location: tableStart, length: tableEnd - tableStart), at: origin)
            NSGraphicsContext.restoreGraphicsState()
            cursor = tableEnd
        }
        if cursor < end {
            super.drawBackground(forGlyphRange: NSRange(location: cursor, length: end - cursor), at: origin)
        }

        for table in tables {
            let path = Self.tablePath(for: table.rect.offsetBy(dx: origin.x, dy: origin.y))
            table.payload.borderColor.setStroke()
            path.lineWidth = CodeBlockCard.borderWidth
            path.stroke()
        }
    }

    private struct TableFrame {
        let payload: TablePayload
        let glyphRange: NSRange
        let rect: NSRect
    }

    private static func tablePath(for rect: NSRect) -> NSBezierPath {
        NSBezierPath(
            roundedRect: rect.insetBy(dx: CodeBlockCard.borderWidth / 2, dy: CodeBlockCard.borderWidth / 2),
            xRadius: CodeBlockCard.cornerRadius,
            yRadius: CodeBlockCard.cornerRadius
        )
    }

    /// The tables whose text intersects `glyphsToShow`, in order, each with its full glyph
    /// range and frame in container coordinates (the union of its cells' bounds).
    private func tableFrames(intersecting glyphsToShow: NSRange) -> [TableFrame] {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        let fullRange = NSRange(location: 0, length: storage.length)
        let shownRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var frames: [TableFrame] = []
        storage.enumerateAttribute(PreviewTextView.tableKey, in: shownRange) { value, partialRange, _ in
            guard let payload = value as? TablePayload else { return }
            var tableRange = NSRange()
            _ = storage.attribute(PreviewTextView.tableKey, at: partialRange.location, longestEffectiveRange: &tableRange, in: fullRange)
            if let cached = tableFrameCache[tableRange.location] {
                frames.append(cached)
                return
            }
            // The part of the table below the visible area may not be laid out yet, and its
            // cells' bounds are needed for the frame.
            ensureLayout(forCharacterRange: tableRange)
            var union = NSRect.null
            storage.enumerateAttribute(.paragraphStyle, in: tableRange) { style, paragraphRange, _ in
                guard let block = (style as? NSParagraphStyle)?.textBlocks.first else { return }
                let glyphs = glyphRange(forCharacterRange: paragraphRange, actualCharacterRange: nil)
                union = union.union(boundsRect(for: block, glyphRange: glyphs))
            }
            guard !union.isNull else { return }
            let frame = TableFrame(
                payload: payload,
                glyphRange: glyphRange(forCharacterRange: tableRange, actualCharacterRange: nil),
                rect: union
            )
            tableFrameCache[tableRange.location] = frame
            frames.append(frame)
        }
        return frames
    }

    /// The card behind the code block whose attributed range is `characterRange`, in container
    /// coordinates: the union of its first and last line fragments (so the paragraph spacing
    /// at both ends is inside) across the container's full width. nil until the block is laid
    /// out.
    func codeBlockCardRect(forCharacterRange characterRange: NSRange, in container: NSTextContainer) -> NSRect? {
        guard characterRange.length > 0 else { return nil }
        let glyphRange = self.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }
        let first = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let last = lineFragmentRect(forGlyphAt: glyphRange.location + glyphRange.length - 1, effectiveRange: nil)
        return NSRect(x: 0, y: first.minY, width: container.size.width, height: last.maxY - first.minY)
    }

    private func drawCodeBlockCards(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let shownRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(PreviewTextView.cardKey, in: shownRange) { value, partialRange, _ in
            guard let payload = value as? PreviewCardPayload else { return }
            // The enumeration clips to the drawn range; the card needs the whole block.
            var blockRange = NSRange()
            _ = storage.attribute(PreviewTextView.cardKey, at: partialRange.location, longestEffectiveRange: &blockRange, in: fullRange)
            let glyphLocation = glyphIndexForCharacter(at: blockRange.location)
            guard let container = textContainer(forGlyphAt: glyphLocation, effectiveRange: nil),
                  let cardRect = codeBlockCardRect(forCharacterRange: blockRange, in: container) else { return }
            let rect = cardRect.offsetBy(dx: origin.x, dy: origin.y)

            let path = NSBezierPath(
                roundedRect: rect.insetBy(dx: CodeBlockCard.borderWidth / 2, dy: CodeBlockCard.borderWidth / 2),
                xRadius: CodeBlockCard.cornerRadius,
                yRadius: CodeBlockCard.cornerRadius
            )
            payload.style.fill.setFill()
            path.fill()
            payload.style.border.setStroke()
            path.lineWidth = CodeBlockCard.borderWidth
            path.stroke()

            if let label = payload.label {
                label.draw(at: CodeBlockCard.labelOrigin(for: label, in: rect))
            }
        }
    }
}

/// The small hover button in a code block's top-right corner. It has no chrome of its own: it
/// fills with the card's colour, so it blends into the card in every theme yet still hides a
/// long first line that runs under it, and takes the card's border colour under the pointer.
final class CodeCopyButton: NSButton {
    static let size = NSSize(width: 26, height: 22)
    static let cornerRadius: CGFloat = 5

    /// The hovered card's colours.
    var cardStyle = CodeBlockCard.Style(fill: .clear, border: .clear) {
        didSet { needsDisplay = true }
    }

    private var isPointerInside = false {
        didSet { if isPointerInside != oldValue { needsDisplay = true } }
    }

    convenience init(target: AnyObject, action: Selector) {
        self.init(frame: NSRect(origin: .zero, size: Self.size))
        self.target = target
        self.action = action
        isBordered = false
        imagePosition = .imageOnly
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        toolTip = "Copy code"
        setAccessibilityLabel("Copy code")
        showCopyState()
    }

    override func draw(_ dirtyRect: NSRect) {
        (isPointerInside ? cardStyle.border : cardStyle.fill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
        super.draw(dirtyRect)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isPointerInside = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isPointerInside = false
    }

    /// Hiding the button under the pointer sends no mouseExited.
    override func viewDidHide() {
        super.viewDidHide()
        isPointerInside = false
    }

    func showCopyState() {
        image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy code")
        contentTintColor = .secondaryLabelColor
    }

    func showCopiedState() {
        image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        contentTintColor = .systemGreen
    }

    /// The text view underneath sets an I-beam; a button should read as clickable.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
