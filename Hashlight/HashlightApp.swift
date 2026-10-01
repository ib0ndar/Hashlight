import SwiftUI
import Combine

/// Applies the user's app-wide appearance choice through AppKit.
///
/// `preferredColorScheme(nil)` does not reliably clear an existing forced color scheme in a
/// macOS Settings scene until the window resigns key status. Setting `NSApplication.appearance`
/// is the native app-wide mechanism and makes every open window inherit the system appearance
/// immediately when the override is removed.
enum ApplicationAppearance {
    static func appKitName(for colorScheme: ColorScheme?) -> NSAppearance.Name? {
        switch colorScheme {
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        case nil:
            return nil
        @unknown default:
            return nil
        }
    }

    @MainActor
    static func apply(_ colorScheme: ColorScheme?, to application: NSApplication = .shared) {
        application.appearance = appKitName(for: colorScheme).flatMap(NSAppearance.init(named:))
    }
}

@main
struct HashlightApp: App {
    @ObservedObject private var documentManager = DocumentManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var folderManager = FolderManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showingHelp = false

    init() {
        // DocumentManager.shared is now available immediately for file opening at launch
    }

    var body: some Scene {
        Window("Hashlight", id: "main") {
            ContentView()
                .environmentObject(documentManager)
                .environmentObject(folderManager)
                .environmentObject(settings)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    // Set up window delegate after window is created
                    DispatchQueue.main.async {
                        if let window = NSApplication.shared.windows.first {
                            let delegate = WindowCloseDelegate.shared
                            delegate.documentManager = documentManager
                            delegate.attach(to: window)
                        }
                    }
                    // Restore last-opened folder
                    folderManager.restoreFolder()
                }
                .sheet(isPresented: $showingHelp) {
                    HelpView()
                }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Hashlight") {
                    AboutPanel.show()
                }
            }

            // The File menu's groups share one Group: Xcode 26.6's CommandsBuilder accepts at
            // most ten entries per block (Xcode 27 has no limit), and CI builds with 26.6.
            Group {
                // Keep ⌘W reserved for Close Tab. SwiftUI places the native Close command in
                // `saveItem`; replacing that group removes its duplicate ⌘W binding while the
                // red titlebar button continues to use the NSWindow close delegate below. A viewer
                // has nothing to save, so the group holds Open File Location (an empty group would
                // leave two adjacent separators in the File menu).
                CommandGroup(replacing: .saveItem) {
                    Button("Open File Location") {
                        if let document = documentManager.selectedDocument {
                            documentManager.revealInFinder(document: document)
                        }
                    }
                    .disabled(documentManager.openDocuments.isEmpty)
                }

                CommandGroup(replacing: .appTermination) {
                    Button("Quit Hashlight") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }

                CommandGroup(replacing: .newItem) {
                    // macOS 27 shows menu icons only for key actions; Open is one.
                    Button {
                        documentManager.openFile()
                    } label: {
                        Label("Open...", systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Button("Quick Open...") {
                        NotificationCenter.default.post(name: .showQuickOpen, object: nil)
                    }
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                    // ⌘⇧F is Focus Mode, so folder search takes ⌃⇧F.
                    Button("Search in Folder...") {
                        NotificationCenter.default.post(name: .showFolderSearch, object: nil)
                    }
                    .keyboardShortcut("f", modifiers: [.control, .shift])

                    Button {
                        folderManager.openFolder()
                    } label: {
                        Label("Open Folder...", systemImage: "text.below.folder")
                    }
                    .keyboardShortcut("o", modifiers: [.command, .option])

                    Button("Close Folder") {
                        folderManager.closeFolder()
                    }
                    .disabled(folderManager.folderURL == nil)

                    Menu("Open Recent") {
                        if documentManager.recentFileURLs.isEmpty {
                            Text("No Recent Files")
                                .disabled(true)
                        } else {
                            ForEach(documentManager.recentFileURLs, id: \.self) { url in
                                Button(url.lastPathComponent) {
                                    documentManager.loadDocument(from: url)
                                }
                            }

                            Divider()

                            Button("Clear Items") {
                                documentManager.clearRecentFiles()
                            }
                        }
                    }
                }

                CommandGroup(replacing: .printItem) {
                    PrintMenuItem(documentManager: documentManager)
                        .keyboardShortcut("p", modifiers: .command)
                }

                CommandGroup(after: .importExport) {
                    Menu {
                        ExportMenuItems(documentManager: documentManager)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }

            // The sidebar is the navigator; its toolbar toggle comes from NavigationSplitView.
            CommandGroup(replacing: .sidebar) {
                Button(settings.isNavigatorVisible ? "Hide Sidebar" : "Show Sidebar") {
                    settings.toggleNavigator()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(documentManager.isFocusModeActive)

                // ⌘⌥1 / ⌘⌥2 follow Xcode's navigator shortcuts.
                Menu("Navigator") {
                    Button(SettingsManager.NavigatorMode.files.displayName) {
                        settings.showNavigator(.files)
                    }
                    .keyboardShortcut("1", modifiers: [.command, .option])

                    Button(SettingsManager.NavigatorMode.outline.displayName) {
                        settings.showNavigator(.outline)
                    }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                }
                .disabled(documentManager.isFocusModeActive)
            }

            // Extend the standard View menu (which already holds Enter Full Screen) instead of
            // adding a second top-level "View" menu with CommandMenu.
            CommandGroup(before: .toolbar) {
                Button(documentManager.isFocusModeActive ? "Exit Focus Mode" : "Focus Mode") {
                    NotificationCenter.default.post(name: .toggleFocusMode, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Command Palette...") {
                    NotificationCenter.default.post(name: .showCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Zoom In") {
                    SettingsManager.shared.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    SettingsManager.shared.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Zoom") {
                    SettingsManager.shared.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Refresh") {
                    documentManager.refreshCurrentDocument()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(documentManager.openDocuments.isEmpty)
            }

            CommandMenu("Tab") {
                Button("Close Tab") {
                    if let document = documentManager.selectedDocument {
                        documentManager.closeDocument(document)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(documentManager.openDocuments.isEmpty)

                // Refresh Tab is reachable via this menu for discoverability, but the ⌘R
                // keyboard shortcut lives solely on View → Refresh to avoid duplicate binding.
                Button("Refresh Tab") {
                    documentManager.refreshCurrentDocument()
                }
                .disabled(documentManager.openDocuments.isEmpty)

                Divider()

                Button("Next Tab") {
                    documentManager.selectNextTab()
                }
                .keyboardShortcut(.tab, modifiers: .control)

                Button("Previous Tab") {
                    documentManager.selectPreviousTab()
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            }

            // Enable standard Edit menu commands
            CommandGroup(after: .textEditing) {
                Divider()

                // Focuses the toolbar's search field.
                Button("Find...") {
                    NotificationCenter.default.post(name: .focusFindField, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(documentManager.openDocuments.isEmpty || documentManager.isFocusModeActive)

                Button("Find Next") {
                    documentManager.nextMatch()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(documentManager.renderedMatchCount == 0)

                Button("Find Previous") {
                    documentManager.previousMatch()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(documentManager.renderedMatchCount == 0)
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Hashlight Help") {
                    showingHelp = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// The standard About panel. It shows the icon the Dock shows (the Dock icon setting) and the
/// "Based on zMD" credit from Credits.rtf.
enum AboutPanel {
    static func options(icon: NSImage, bundle: Bundle = .main) -> [NSApplication.AboutPanelOptionKey: Any] {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationIcon: icon]
        if let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            options[.applicationVersion] = version
        }
        if let credits = credits(in: bundle) {
            options[.credits] = credits
        }
        return options
    }

    static func credits(in bundle: Bundle = .main) -> NSAttributedString? {
        guard let url = bundle.url(forResource: "Credits", withExtension: "rtf") else { return nil }
        return try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    }

    static func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: options(icon: DockIconController.shared.image))
    }
}

// AppDelegate to prevent app from quitting when window closes. It deliberately does not
// implement applicationShouldTerminate(_:): a viewer has nothing to save, so Quit is immediate.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SidebarAutosave.repair(
            in: NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" })
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DocumentManager.shared.showMainWindow()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make AppKit the single owner of the app-wide override. In particular, assigning nil
        // here means "inherit macOS" and updates existing windows without requiring a focus
        // change, unlike clearing SwiftUI's preferredColorScheme on a Settings scene.
        ApplicationAppearance.apply(SettingsManager.shared.colorScheme, to: NSApplication.shared)
        DockIconController.shared.start(observing: SettingsManager.shared)
    }

    /// Files opened through AppKit's handler, until the main window has first appeared.
    func application(_ application: NSApplication, open urls: [URL]) {
        OpenDocumentsEvents.open(urls)
    }
}

/// Files opened from outside the app (Finder, the Dock, `open`, AppleScript) arrive as
/// open-documents Apple Events, and every one ends in `open(_:)`, the one rule for them.
///
/// AppKit's handler routes the event through SwiftUI. That is what opens the main window when
/// there is none yet (SwiftUI opens no window of its own when the app is launched to open
/// documents or launched by a script), but SwiftUI also holds the reply until the app can come to
/// the front: a script's `open` then waited for minutes and failed although the files had opened.
/// Once the main window has appeared, DocumentManager can reopen it, so `takeOver()` installs a
/// handler that replies at once.
@MainActor
final class OpenDocumentsEvents: NSObject {
    static let shared = OpenDocumentsEvents()
    private var isInstalled = false

    func takeOver() {
        guard !isInstalled else { return }
        isInstalled = true
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handle(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        Self.open(Self.fileURLs(in: event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))))
    }

    /// Each Markdown file opens in a tab.
    static func open(_ urls: [URL]) {
        let documentManager = DocumentManager.shared

        for url in urls {
            // Case-insensitive: Finder happily hands us README.MD; the case-sensitive compare
            // silently ignored it (DropHandler already lowercases — keep the paths consistent).
            let ext = url.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                documentManager.loadDocument(from: url)
            }
        }
    }

    /// The files in an open-documents event's direct object, in order. Senders put one file or a
    /// list there, as file URLs (AppleScript), bookmarks (Finder, `open`), or aliases. The handler
    /// inherited from zMD trapped on a single file and dropped file URLs.
    static func fileURLs(in directObject: NSAppleEventDescriptor?) -> [URL] {
        guard let list = directObject?.coerce(toDescriptorType: DescType(typeAEList)),
              list.numberOfItems > 0 else { return [] }
        return (1...list.numberOfItems).compactMap { list.atIndex($0)?.fileURLValue }
    }
}

// Window delegate to handle window close events. The window's title and proxy icon come from
// the detail view's navigationTitle / navigationDocument.
class WindowCloseDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowCloseDelegate()
    weak var documentManager: DocumentManager? {
        didSet { observeFocusMode() }
    }
    private weak var window: NSWindow?
    private var focusModeCancellable: AnyCancellable?
    private var chromeOutsideFocusMode: FocusModeWindowChrome.SavedChrome?

    func attach(to window: NSWindow) {
        self.window = window
        window.delegate = self
        observeFocusMode()
    }

    /// Focus mode keeps the window controls but nothing else of the title bar, like the
    /// distraction-free modes of Mac writing apps. SwiftUI's `toolbar(.hidden, for:
    /// .windowToolbar)` removes the window controls too on macOS 26, so the title bar is changed
    /// on the NSWindow. `$isFocusModeActive` delivers the new value.
    private func observeFocusMode() {
        guard let documentManager, window != nil else { return }
        focusModeCancellable = documentManager.$isFocusModeActive
            .removeDuplicates()
            .sink { [weak self] isActive in
                guard let self, let window = self.window else { return }
                if isActive {
                    if chromeOutsideFocusMode == nil {
                        chromeOutsideFocusMode = FocusModeWindowChrome.enter(window)
                    }
                } else if let saved = chromeOutsideFocusMode {
                    FocusModeWindowChrome.leave(window, restoring: saved)
                    chromeOutsideFocusMode = nil
                }
            }
    }

    /// The red titlebar button closes every tab at once, without asking: there is nothing to
    /// save. The app keeps running and reopens to the welcome screen.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        documentManager?.closeAllDocuments()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        SidebarAutosave.repair(in: notification.object as? NSWindow)
        // Focus mode belongs to the window it was turned on in; the next window starts with
        // the sidebar as saved. Animated, because AppKit widens a window whose sidebar
        // reappears without animation.
        if documentManager?.isFocusModeActive == true {
            withAnimation(Motion.sidebar) {
                documentManager?.isFocusModeActive = false
            }
        }
    }

    /// Closing the last tab also dismisses the window. The red button's all-tabs close does not
    /// come through here (closeAllDocuments skips it), since that window is already closing.
    func closeWindowWhenEmpty() {
        guard documentManager?.openDocuments.isEmpty == true,
              window != nil else { return }
        documentManager?.closeMainWindow()
    }
}

/// The NSWindow side of focus mode: the title bar becomes transparent over full-size content,
/// so the document runs under it and only the window controls remain. The title, proxy icon,
/// and toolbar items are SwiftUI's (`navigationTitle`, `navigationDocument`, `ViewerToolbar`)
/// and are cleared there; hiding the toolbar itself resizes the window. `enter` returns what to
/// put back.
enum FocusModeWindowChrome {
    struct SavedChrome: Equatable {
        var titlebarAppearsTransparent: Bool
        var hasFullSizeContentView: Bool
    }

    @MainActor
    static func enter(_ window: NSWindow) -> SavedChrome {
        let saved = SavedChrome(
            titlebarAppearsTransparent: window.titlebarAppearsTransparent,
            hasFullSizeContentView: window.styleMask.contains(.fullSizeContentView)
        )
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        return saved
    }

    @MainActor
    static func leave(_ window: NSWindow, restoring saved: SavedChrome) {
        if !saved.hasFullSizeContentView {
            window.styleMask.remove(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = saved.titlebarAppearsTransparent
    }
}

/// Focus mode hides the sidebar for the session only, but AppKit autosaves the split view with
/// the sidebar collapsed. A window that restores it collapsed while the navigator should show
/// widens itself by the sidebar's width to show it, so when a window closes or the app quits,
/// a collapsed state the navigator setting does not ask for is corrected.
enum SidebarAutosave {
    static func repair(in window: NSWindow?) {
        guard SettingsManager.shared.isNavigatorVisible,
              let splitView = firstSplitView(in: window?.contentView),
              let name = splitView.autosaveName, !name.isEmpty else { return }
        let key = "NSSplitView Subview Frames \(name)"
        guard let frames = UserDefaults.standard.stringArray(forKey: key),
              let repaired = framesWithSidebarExpanded(frames) else { return }
        UserDefaults.standard.set(repaired, forKey: key)
    }

    /// `frames` with the first (sidebar) entry marked expanded, or nil if it already is or the
    /// format is not the expected "x, y, width, height, isCollapsed, isHidden" per subview.
    static func framesWithSidebarExpanded(_ frames: [String]) -> [String]? {
        guard let sidebar = frames.first else { return nil }
        var fields = sidebar.components(separatedBy: ", ")
        guard fields.count == 6, fields[4] == "YES" else { return nil }
        fields[4] = "NO"
        var repaired = frames
        repaired[0] = fields.joined(separator: ", ")
        return repaired
    }

    private static func firstSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let splitView = view as? NSSplitView { return splitView }
        for subview in view.subviews {
            if let splitView = firstSplitView(in: subview) { return splitView }
        }
        return nil
    }
}
