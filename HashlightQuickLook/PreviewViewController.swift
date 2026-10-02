import AppKit
import QuickLookUI
#if HASHLIGHT_QUICKLOOK_TESTS
// The test target compiles this file too; there the shared preview code is the app's module.
@testable import Hashlight
#endif

/// Quick Look preview for Markdown files (Space in Finder), drawn by the app's own renderer:
/// the same `PreviewRenderer`, `PreviewTextView`, and layout manager as a Hashlight window, with
/// the app's light and dark themes and its fonts and font sizes (Settings → Viewing), read from
/// the preferences the app shares with the extension, together with its table-column setting.
/// The layout is always left-aligned, full-width, with normal margins, at 100 % zoom, with the
/// frontmatter shown.
///
/// The extension is sandboxed with no network and reads only the previewed file, so pictures
/// show their placeholder and Mermaid diagrams and display math show their source.
final class PreviewViewController: NSViewController, QLPreviewingController {
    static let contentAlignment: PreviewContentAlignment = .left
    static let contentWidth: PreviewContentWidth = .full
    static let pageMargin: PreviewPageMargin = .normal
    /// The app's preview uses the same space above and below the text.
    static let verticalInset: CGFloat = 40

    /// What the preview takes from the app, validated as the app validates its own settings:
    /// an unknown theme, a missing font, or a size out of range falls back to the default.
    struct Options: Equatable {
        var lightThemeID = PreviewThemeCatalog.defaultLightID
        var darkThemeID = PreviewThemeCatalog.defaultDarkID
        var mainFontID = PreviewFontCatalog.systemMainID
        var fixedFontID = PreviewFontCatalog.systemFixedID
        var mainFontSize = PreviewFontCatalog.defaultMainSize
        var fixedFontSize = PreviewFontCatalog.defaultFixedSize
        var tableColumnConfiguration: MarkdownTableColumnConfiguration?

        /// Hashlight's defaults.
        static let defaults = Options()

        init() {}

        init(_ viewing: QuickLookViewingSettings, tableColumnConfiguration: MarkdownTableColumnConfiguration?) {
            lightThemeID = PreviewThemeCatalog.validatedLightID(viewing.lightThemeID)
            darkThemeID = PreviewThemeCatalog.validatedDarkID(viewing.darkThemeID)
            mainFontID = PreviewFontCatalog.validatedMainID(viewing.mainFontID)
            fixedFontID = PreviewFontCatalog.validatedFixedID(viewing.fixedFontID)
            mainFontSize = PreviewFontCatalog.validatedSize(
                viewing.mainFontSize.map(NSNumber.init(value:)),
                default: PreviewFontCatalog.defaultMainSize,
                range: PreviewFontCatalog.mainSizeRange
            )
            fixedFontSize = PreviewFontCatalog.validatedSize(
                viewing.fixedFontSize.map(NSNumber.init(value:)),
                default: PreviewFontCatalog.defaultFixedSize,
                range: PreviewFontCatalog.fixedSizeRange
            )
            self.tableColumnConfiguration = tableColumnConfiguration
        }

        /// The app's current choices, read afresh for every preview.
        static func shared() -> Options {
            Options(
                QuickLookViewingPreferences.loadQuickLookDefaults(),
                tableColumnConfiguration: MarkdownTableColumnPreferences.loadQuickLookDefaults()
            )
        }

        /// The light theme in Light mode, the dark one in Dark mode, as in the app.
        func theme(dark: Bool) -> PreviewTheme {
            let id = dark ? darkThemeID : lightThemeID
            return (dark ? PreviewThemeCatalog.dark : PreviewThemeCatalog.light).first { $0.id == id }
                ?? .system(dark: dark)
        }
    }

    private(set) var textView: PreviewTextView?
    private var elements: [MarkdownParser.Element] = []
    private var baseURL: URL?
    private var truncated = false
    private var frontmatterExpanded = false
    private var options = Options.defaults
    /// The appearance the text was last built for; themes bake their colors in.
    private var renderedDark: Bool?

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let container = AppearanceTrackingView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
        let (scrollView, textView) = PreviewTextView.makeScrollView(
            theme: .system(dark: Self.isDark(container.effectiveAppearance)),
            contentAlignment: Self.contentAlignment,
            contentWidth: Self.contentWidth,
            pageMargin: Self.pageMargin,
            verticalInset: Self.verticalInset
        )
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)

        textView.delegate = self
        textView.onFrontmatterToggle = { [weak self] in
            guard let self else { return }
            frontmatterExpanded.toggle()
            render(keepingScrollPosition: true)
        }
        container.onEffectiveAppearanceChange = { [weak self] in
            guard let self, renderedDark != nil, renderedDark != Self.isDark(view.effectiveAppearance) else { return }
            render(keepingScrollPosition: true)
        }
        self.textView = textView
        view = container
        preferredContentSize = container.frame.size
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let (data, truncated) = try QuickLookDocument.readPrefix(of: url)
        show(QuickLookDocument.decode(data, truncated: truncated), baseURL: url, truncated: truncated, options: .shared())
    }

    /// Lays out `markdown` as the preview. Separate from reading so tests can drive it.
    func show(_ markdown: String, baseURL: URL?, truncated: Bool, options: Options) {
        _ = view
        elements = MarkdownParser.shared.parse(markdown)
        self.baseURL = baseURL
        self.truncated = truncated
        self.options = options
        frontmatterExpanded = false
        render(keepingScrollPosition: false)
    }

    private func render(keepingScrollPosition: Bool) {
        guard let textView, let scrollView = textView.enclosingScrollView else { return }
        let dark = Self.isDark(view.effectiveAppearance)
        let theme = options.theme(dark: dark)
        let renderer = PreviewRenderer(
            mainFontID: options.mainFontID,
            fixedFontID: options.fixedFontID,
            mainFontSize: CGFloat(options.mainFontSize),
            fixedFontSize: CGFloat(options.fixedFontSize),
            theme: theme,
            zoomLevel: 1,
            contentWidth: Self.contentWidth,
            tableColumnConfiguration: options.tableColumnConfiguration,
            baseURL: baseURL,
            resources: nil
        )
        let text = renderer.attributedString(for: elements, showsFrontmatter: true, frontmatterExpanded: frontmatterExpanded)
        if truncated {
            renderer.render(.horizontalRule, to: text, frontmatterExpanded: false)
            renderer.render(.paragraph("*\(QuickLookDocument.truncationNotice)*"), to: text, frontmatterExpanded: false)
        }

        let scrollOrigin = scrollView.contentView.bounds.origin
        textView.apply(theme)
        textView.showPreview(text)
        renderedDark = dark
        if keepingScrollPosition, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            // The new text's height is needed before the old offset can be clamped to it.
            layoutManager.ensureLayout(for: textContainer)
            textView.sizeToFit()
            let clipView = scrollView.contentView
            let kept = clipView.constrainBoundsRect(NSRect(origin: scrollOrigin, size: clipView.bounds.size))
            clipView.setBoundsOrigin(kept.origin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension PreviewViewController: NSTextViewDelegate {
    /// Web and mail links open in their apps; anything else (relative Markdown links, files)
    /// has nowhere to go from a preview.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        if let url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return true
    }
}

/// The preview's root view. NSViewController has no appearance callback, and the themes'
/// colors are resolved into the text, so a Light/Dark switch rebuilds it.
private final class AppearanceTrackingView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}
