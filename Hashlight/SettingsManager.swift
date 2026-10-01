import SwiftUI

// MARK: - Named Constants
//
// Centralizes timing/size/CDN magic numbers that were previously scattered as inline literals.
// Changing any value here is the single edit point; no grep-hunt required.
// Living alongside SettingsManager to avoid adding a new file to the Xcode project (legacy
// pbxproj format; file additions require manual project edits).

/// Cross-app timing constants (seconds unless noted).
enum Timing {
    /// Debounce window for FSEvents directory-change callbacks before rebuilding the tree.
    static let directoryWatcherDebounce: TimeInterval = 0.3
    /// Latency the FSEvents stream coalesces file events within.
    static let directoryWatcherLatency: CFTimeInterval = 1.0
    /// Scroll debounce for persisting a document's scroll position to UserDefaults.
    static let scrollPositionPersistDebounce: TimeInterval = 0.5
}

/// Animation tokens. Every animation in the app should use one of these
/// rather than a hand-typed curve/duration, so motion stays cohesive and the
/// system Reduce Motion setting is honored in one place.
enum Motion {
    /// True when macOS's "Reduce motion" accessibility setting is on.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Hover states, tiny state flips. 100–150ms class.
    static var fast: Animation { .easeOut(duration: 0.12) }
    /// Things appearing/entering (entrances want ease-out: fast start,
    /// settled end).
    static var entrance: Animation { .easeOut(duration: 0.2) }
    /// Like `fast`, but nil under Reduce Motion — use for anything that
    /// changes position or size (scales, reflows, slides). Keep `fast` for
    /// color-only fades, which stay enabled either way.
    static var fastMovement: Animation? { reduceMotion ? nil : fast }
    /// Like `entrance`, but nil under Reduce Motion.
    static var entranceMovement: Animation? { reduceMotion ? nil : entrance }
    /// On-screen movement/morphs (sidebars toggling, the find bar).
    static func layoutAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    static var standard: Animation? {
        layoutAnimation(reduceMotion: reduceMotion)
    }
    /// Showing or hiding the sidebar, including focus mode, which hides it. Upper bound of the
    /// UI budget. Never nil: AppKit widens the window instead of narrowing the document when a
    /// sidebar appears without animation, so Reduce Motion gets a near-instant animation.
    static var sidebar: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.3)
    }
    /// Subtle spring for stack reflows and rare entrances (toasts, welcome
    /// icon). Bounce is intentionally quiet; nil under Reduce Motion.
    static var springy: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)
    }

    /// A movement transition that degrades to a plain fade under Reduce
    /// Motion — keeps the state-change feedback, drops the position change.
    static func slideOrFade(edge: Edge) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: edge))
    }

    /// A scale entrance that degrades to a plain fade under Reduce Motion.
    static func scaleOrFade(_ scale: CGFloat = 0.95) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: scale))
    }
}

/// Fades inserted chrome in under Reduce Motion. Layout changes there are driven by nil
/// animations (`Motion.standard`), so a `slideOrFade` transition's opacity fallback never
/// animated and sidebars and the find bar popped in. The layout still changes instantly;
/// only the inserted view's opacity animates, in its own transaction.
struct FadeInUnderReduceMotion: ViewModifier {
    @State private var isVisible = !Motion.reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(Motion.entrance) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func fadeInUnderReduceMotion() -> some View {
        modifier(FadeInUnderReduceMotion())
    }
}

/// Cache limits for in-memory image + diagram storage.
enum Cache {
    static let imageCountLimit: Int = 100
    static let imageByteLimit: Int = 100 * 1024 * 1024
    // Math/Mermaid images are tiny (~5KB each). Long docs hit ~300+ inline math spans;
    // with countLimit=100 the cache thrashed, causing constant re-render loops that
    // visibly auto-scrolled the viewport. Bumped to a value that comfortably fits even
    // long technical/research papers, byte-bounded by the 100MB cap below.
    static let diagramCountLimit: Int = 2000
    static let diagramByteLimit: Int = 100 * 1024 * 1024
    /// Maximum number of per-document scroll-position entries kept in UserDefaults.
    static let scrollPositionLimit: Int = 100
    /// Maximum Recent Files retained across launches.
    static let recentFilesLimit: Int = 10
}

/// UserDefaults key strings. Centralizing them prevents silent user-data loss from typos —
/// renaming a raw string "RecentMarkdownFiles" → "recentFiles" on a live install wipes the
/// user's Open Recent list. Values here MUST match the historical string used at write time.
enum DefaultsKeys {
    // MARK: Settings (SettingsManager)
    static let colorScheme = "colorScheme"
    static let dockIconMode = "dockIconMode"
    static let lightPreviewThemeID = "lightPreviewThemeID"
    static let darkPreviewThemeID = "darkPreviewThemeID"
    /// Used only to migrate builds that stored one preview theme for both appearances.
    static let legacyPreviewThemeID = "previewThemeID"
    static let mainPreviewFontID = "mainPreviewFontID"
    static let fixedPreviewFontID = "fixedPreviewFontID"
    /// Used only to migrate the former System / Serif / Monospace preview setting.
    static let legacyFontStyle = "fontStyle"
    static let contentAlignment = "contentAlignment"
    static let contentWidth = "contentWidth"
    static let pageMargin = "pageMargin"
    static let tableColumnConfiguration = MarkdownTableColumnPreferences.appKey
    static let zoomLevel = "zoomLevel"

    // MARK: DocumentManager
    static let recentFiles = "RecentMarkdownFiles"
    static let scrollPositions = "DocumentScrollPositions"

    // MARK: FolderManager
    static let folderBookmark = "FolderBookmarkData"

    // MARK: Main window navigator (SettingsManager)
    static let navigatorMode = "navigatorMode"
    static let navigatorVisible = "navigatorVisible"
    /// Used only to migrate the former outline-pane toggle to the navigator settings.
    static let legacyShowOutline = "showOutline"

    // MARK: SettingsView
    /// The Settings pane shown last; Settings reopens on it.
    static let settingsPane = "settingsPane"
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var colorScheme: ColorScheme? {
        didSet {
            UserDefaults.standard.set(colorScheme == .dark ? "dark" : (colorScheme == .light ? "light" : "system"), forKey: DefaultsKeys.colorScheme)
        }
    }

    /// Icon the Dock and app switcher show while Hashlight runs; `DockIconController` applies it.
    @Published var dockIconMode: DockIconMode {
        didSet {
            UserDefaults.standard.set(dockIconMode.rawValue, forKey: DefaultsKeys.dockIconMode)
        }
    }

    /// Palette used by the rendered Markdown preview while the effective appearance is light.
    @Published var lightPreviewThemeID: String {
        didSet {
            UserDefaults.standard.set(lightPreviewThemeID, forKey: DefaultsKeys.lightPreviewThemeID)
        }
    }

    /// Palette used by the rendered Markdown preview while the effective appearance is dark.
    @Published var darkPreviewThemeID: String {
        didSet {
            UserDefaults.standard.set(darkPreviewThemeID, forKey: DefaultsKeys.darkPreviewThemeID)
        }
    }

    @Published var mainPreviewFontID: String {
        didSet {
            UserDefaults.standard.set(mainPreviewFontID, forKey: DefaultsKeys.mainPreviewFontID)
        }
    }

    @Published var fixedPreviewFontID: String {
        didSet {
            UserDefaults.standard.set(fixedPreviewFontID, forKey: DefaultsKeys.fixedPreviewFontID)
        }
    }

    /// Where the preview's fixed-width text column sits when the pane is wider than the column.
    @Published var contentAlignment: ContentAlignment {
        didSet {
            UserDefaults.standard.set(contentAlignment.rawValue, forKey: DefaultsKeys.contentAlignment)
        }
    }

    /// Maximum width of the preview's text column (it always shrinks to fit a narrower pane).
    @Published var contentWidth: ContentWidth {
        didSet {
            UserDefaults.standard.set(contentWidth.rawValue, forKey: DefaultsKeys.contentWidth)
        }
    }

    /// Horizontal padding around rendered Markdown, including in Full width mode.
    @Published var pageMargin: PageMargin {
        didSet {
            UserDefaults.standard.set(pageMargin.rawValue, forKey: DefaultsKeys.pageMargin)
        }
    }

    /// Editable table sizing rules used by Preview and copied to the Quick Look preferences domain.
    @Published var tableColumnConfiguration: MarkdownTableColumnConfiguration {
        didSet { MarkdownTableColumnPreferences.persist(tableColumnConfiguration) }
    }

    @Published var zoomLevel: CGFloat {
        didSet {
            UserDefaults.standard.set(zoomLevel, forKey: DefaultsKeys.zoomLevel)
        }
    }

    /// What the main window's sidebar shows: the open folder's files or the document outline.
    @Published var navigatorMode: NavigatorMode {
        didSet {
            UserDefaults.standard.set(navigatorMode.rawValue, forKey: DefaultsKeys.navigatorMode)
        }
    }

    /// Whether the main window's sidebar is shown (focus mode hides it without changing this).
    @Published var isNavigatorVisible: Bool {
        didSet {
            UserDefaults.standard.set(isNavigatorVisible, forKey: DefaultsKeys.navigatorVisible)
        }
    }

    /// Tick that bumps when the system effective appearance changes (light ↔ dark), when the
    /// system colors change (accent color), or when the accessibility display options change
    /// (Increase Contrast). Views observing SettingsManager re-render, resolve the preview theme
    /// again — the System themes are rebuilt from the current system colors — and pass it into
    /// MarkdownTextView, whose cache key includes the resolved palette.
    @Published var appearanceTick: Int = 0
    private var appearanceObserver: NSKeyValueObservation?

    func zoomIn() {
        zoomLevel = min(2.0, (zoomLevel * 10 + 1).rounded() / 10)
    }

    func zoomOut() {
        zoomLevel = max(0.5, (zoomLevel * 10 - 1).rounded() / 10)
    }

    func resetZoom() {
        zoomLevel = 1.0
    }

    /// Shows the sidebar in `mode` (View → Navigator, and after Open Folder).
    func showNavigator(_ mode: NavigatorMode) {
        withAnimation(Motion.sidebar) {
            navigatorMode = mode
            isNavigatorVisible = true
        }
    }

    func toggleNavigator() {
        withAnimation(Motion.sidebar) {
            isNavigatorVisible.toggle()
        }
    }

    /// Horizontal placement of the preview's text column. This positions the whole column
    /// within the pane — text inside the column stays left-aligned (it is not paragraph
    /// alignment). Only visible when the pane is wider than the column plus its margins;
    /// in narrow panes and Focus Mode all three settings look the same.
    enum ContentAlignment: String, CaseIterable {
        case left = "Left"
        case center = "Center"
        case right = "Right"

        var displayName: String {
            return self.rawValue
        }

        var icon: String {
            switch self {
            case .left: return "text.alignleft"
            case .center: return "text.aligncenter"
            case .right: return "text.alignright"
            }
        }
    }

    /// Maximum width of the preview's text column. A MAXIMUM, not a fixed size: the column
    /// always shrinks to fit a narrower pane (Focus Mode, a small window). `.full` tracks the pane.
    enum ContentWidth: String, CaseIterable {
        case narrow = "Narrow"
        case medium = "Medium"
        case wide = "Wide"
        case full = "Full"

        var displayName: String {
            return self.rawValue
        }

        /// Column width in points; nil = fill the pane without a maximum.
        var points: CGFloat? {
            switch self {
            case .narrow: return 760
            case .medium: return 960
            case .wide: return 1300
            case .full: return nil
            }
        }

        /// Preset cap for images and diagrams, which are sized once at build time. Full has
        /// no artificial cap, matching the text column's fill-the-pane behavior.
        var attachmentMaxWidth: CGFloat? {
            points.map { max(200, $0 - 100) }
        }
    }

    /// System leaves the icon to macOS (on macOS 13–15: Frost in Light mode, Ember in Dark mode);
    /// Frost and Ember override it.
    enum DockIconMode: String, CaseIterable {
        case system = "System"
        case frost = "Frost"
        case ember = "Ember"

        var displayName: String {
            return self.rawValue
        }
    }

    enum PageMargin: String, CaseIterable {
        case compact = "Compact"
        case normal = "Normal"
        case comfortable = "Comfortable"

        var points: CGFloat {
            switch self {
            case .compact: return 16
            case .normal: return 24
            case .comfortable: return 40
            }
        }
    }

    enum NavigatorMode: String, CaseIterable {
        case files
        case outline

        var displayName: String {
            switch self {
            case .files: return "Files"
            case .outline: return "Outline"
            }
        }
    }

    /// Reads the saved navigator settings, migrating builds that had separate folder and outline
    /// panes: a shown outline becomes a visible Outline navigator; otherwise an open folder (its
    /// pane was always shown) becomes a visible Files navigator. The migrated values are written
    /// back and the legacy key is removed, so this runs once.
    static func loadNavigatorState(from defaults: UserDefaults) -> (mode: NavigatorMode, isVisible: Bool) {
        let savedMode = defaults.string(forKey: DefaultsKeys.navigatorMode).flatMap(NavigatorMode.init(rawValue:))
        let savedVisibility = defaults.object(forKey: DefaultsKeys.navigatorVisible) as? Bool
        if savedMode != nil || savedVisibility != nil {
            return (savedMode ?? .outline, savedVisibility ?? false)
        }

        let state: (mode: NavigatorMode, isVisible: Bool)
        if defaults.bool(forKey: DefaultsKeys.legacyShowOutline) {
            state = (.outline, true)
        } else if defaults.data(forKey: DefaultsKeys.folderBookmark) != nil {
            state = (.files, true)
        } else {
            state = (.outline, false)
        }
        guard defaults.object(forKey: DefaultsKeys.legacyShowOutline) != nil
                || defaults.data(forKey: DefaultsKeys.folderBookmark) != nil else {
            return state
        }
        defaults.set(state.mode.rawValue, forKey: DefaultsKeys.navigatorMode)
        defaults.set(state.isVisible, forKey: DefaultsKeys.navigatorVisible)
        defaults.removeObject(forKey: DefaultsKeys.legacyShowOutline)
        return state
    }

    init() {
        // Load saved preferences
        let legacyThemeID = UserDefaults.standard.string(forKey: DefaultsKeys.legacyPreviewThemeID)
        self.lightPreviewThemeID = PreviewThemeCatalog.validatedLightID(
            UserDefaults.standard.string(forKey: DefaultsKeys.lightPreviewThemeID) ?? legacyThemeID
        )
        self.darkPreviewThemeID = PreviewThemeCatalog.validatedDarkID(
            UserDefaults.standard.string(forKey: DefaultsKeys.darkPreviewThemeID) ?? legacyThemeID
        )

        let legacyFontStyle = UserDefaults.standard.string(forKey: DefaultsKeys.legacyFontStyle)
        let migratedMainFontID = legacyFontStyle == "Serif" ? "Charter" : nil
        self.mainPreviewFontID = PreviewFontCatalog.validatedMainID(
            UserDefaults.standard.string(forKey: DefaultsKeys.mainPreviewFontID) ?? migratedMainFontID
        )
        self.fixedPreviewFontID = PreviewFontCatalog.validatedFixedID(
            UserDefaults.standard.string(forKey: DefaultsKeys.fixedPreviewFontID)
        )

        let savedAlignment = UserDefaults.standard.string(forKey: DefaultsKeys.contentAlignment) ?? ContentAlignment.left.rawValue
        self.contentAlignment = ContentAlignment(rawValue: savedAlignment) ?? .left

        let savedWidth = UserDefaults.standard.string(forKey: DefaultsKeys.contentWidth) ?? ContentWidth.medium.rawValue
        self.contentWidth = ContentWidth(rawValue: savedWidth) ?? .medium

        let savedPageMargin = UserDefaults.standard.string(forKey: DefaultsKeys.pageMargin) ?? PageMargin.normal.rawValue
        self.pageMargin = PageMargin(rawValue: savedPageMargin) ?? .normal

        let savedDockIconMode = UserDefaults.standard.string(forKey: DefaultsKeys.dockIconMode) ?? DockIconMode.system.rawValue
        self.dockIconMode = DockIconMode(rawValue: savedDockIconMode) ?? .system

        self.tableColumnConfiguration = MarkdownTableColumnPreferences.loadAppDefaults()

        let savedZoom = UserDefaults.standard.double(forKey: DefaultsKeys.zoomLevel)
        self.zoomLevel = savedZoom > 0 ? CGFloat(savedZoom) : 1.0

        let navigator = Self.loadNavigatorState(from: .standard)
        self.navigatorMode = navigator.mode
        self.isNavigatorVisible = navigator.isVisible

        let savedScheme = UserDefaults.standard.string(forKey: DefaultsKeys.colorScheme) ?? "system"
        switch savedScheme {
        case "dark":
            self.colorScheme = .dark
        case "light":
            self.colorScheme = .light
        default:
            self.colorScheme = nil
        }

        // Initialize Quick Look's read-only preferences snapshot on first launch and keep it
        // aligned with the app's saved settings on subsequent launches.
        MarkdownTableColumnPreferences.persist(tableColumnConfiguration)

        // Observe NSApplication.effectiveAppearance so views observing SettingsManager re-render
        // on system theme toggle. SettingsManager.shared can be touched during HashlightApp.init —
        // BEFORE NSApp's global is wired up — so accessing NSApp directly here was a launch
        // crash (force-unwrap of nil). Defer to the next main-queue spin: by then the App
        // delegate has assigned NSApp, and NSApplication.shared is the safe canonical accessor.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appearanceObserver = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.appearanceTick &+= 1
                }
            }
            // Selector observers are removed automatically when the observer deallocates.
            NotificationCenter.default.addObserver(
                self, selector: #selector(self.systemColorsDidChange(_:)),
                name: NSColor.systemColorsDidChangeNotification, object: nil
            )
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(self.systemColorsDidChange(_:)),
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
            )
        }
    }

    @objc private func systemColorsDidChange(_ notification: Notification) {
        appearanceTick &+= 1
    }

    deinit {
        // No assumeIsolated (traps if the last release happens off-main); KVO
        // invalidate() is thread-safe and deinit has exclusive property access.
        appearanceObserver?.invalidate()
    }
}
