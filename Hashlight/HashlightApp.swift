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
                .frame(minWidth: 700, minHeight: 550)
                .onAppear {
                    // Set up window delegate after window is created
                    DispatchQueue.main.async {
                        if let window = NSApplication.shared.windows.first {
                            let delegate = WindowCloseDelegate.shared
                            delegate.documentManager = documentManager
                            window.delegate = delegate
                            delegate.attachWindowChrome(to: window)
                            // Set default window size on first launch
                            if window.frame.width < 900 || window.frame.height < 650 {
                                let screen = window.screen ?? NSScreen.main
                                let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                                let newSize = NSSize(width: 1000, height: 700)
                                let origin = NSPoint(
                                    x: screenFrame.midX - newSize.width / 2,
                                    y: screenFrame.midY - newSize.height / 2
                                )
                                window.setFrame(NSRect(origin: origin, size: newSize), display: true, animate: false)
                            }
                        }
                    }
                    // Restore last-opened folder
                    folderManager.restoreFolder()
                }
                .sheet(isPresented: $showingHelp) {
                    HelpView()
                }
        }
        .commands {
            // Keep ⌘W reserved for Close Tab. SwiftUI places the native Close command in
            // `saveItem`; replacing that group removes its duplicate ⌘W binding while the
            // red titlebar button continues to use the NSWindow close delegate below. A viewer
            // has nothing to save, so the group holds Open File Location (an empty group would
            // leave two adjacent separators in the File menu).
            CommandGroup(replacing: .saveItem) {
                Button("Open File Location") {
                    if let selectedId = documentManager.selectedDocumentId,
                       let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
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
                Button("Open...") {
                    documentManager.openFile()
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

                Button("Open Folder...") {
                    folderManager.openFolder()
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
                Button("Print...") {
                    if let selectedId = documentManager.selectedDocumentId,
                       let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
                        PrintManager.shared.print(content: document.content, fileName: document.name)
                    }
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(documentManager.openDocuments.isEmpty)
            }

            CommandGroup(after: .importExport) {
                Menu("Export") {
                    Button("PDF...") {
                        if let selectedId = documentManager.selectedDocumentId,
                           let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
                            ExportManager.shared.exportToPDF(content: document.content, fileName: document.name, baseURL: document.url)
                        }
                    }
                    .disabled(documentManager.openDocuments.isEmpty)

                    Divider()

                    Button("HTML...") {
                        if let selectedId = documentManager.selectedDocumentId,
                           let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
                            ExportManager.shared.exportToHTML(content: document.content, fileName: document.name, includeStyles: true)
                        }
                    }
                    .disabled(documentManager.openDocuments.isEmpty)

                    Button("HTML (without styles)...") {
                        if let selectedId = documentManager.selectedDocumentId,
                           let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
                            ExportManager.shared.exportToHTML(content: document.content, fileName: document.name, includeStyles: false)
                        }
                    }
                    .disabled(documentManager.openDocuments.isEmpty)

                    Divider()

                    Button("Word (.docx)...") {
                        if let selectedId = documentManager.selectedDocumentId,
                           let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
                            ExportManager.shared.exportToDOCX(content: document.content, fileName: document.name, baseURL: document.url)
                        }
                    }
                    .disabled(documentManager.openDocuments.isEmpty)

                    Button("Word (.rtf)...") {
                        if let selectedId = documentManager.selectedDocumentId,
                           let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
                            ExportManager.shared.exportToWord(content: document.content, fileName: document.name, baseURL: document.url)
                        }
                    }
                    .disabled(documentManager.openDocuments.isEmpty)
                }
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
                    if let selectedId = documentManager.selectedDocumentId,
                       let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
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

                Button("Find...") {
                    documentManager.startSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(documentManager.openDocuments.isEmpty)

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

// AppDelegate to prevent app from quitting when window closes. It deliberately does not
// implement applicationShouldTerminate(_:): a viewer has nothing to save, so Quit is immediate.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
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

        // Register for Apple Events to handle file opening
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Handle files opened from Finder using shared DocumentManager
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

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        let documentManager = DocumentManager.shared

        if let urlList = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) {
            for i in 1...urlList.numberOfItems {
                if let urlString = urlList.atIndex(i)?.stringValue,
                   let url = URL(string: urlString) {
                    let ext = url.pathExtension.lowercased()
                    if ext == "md" || ext == "markdown" {
                        documentManager.loadDocument(from: url)
                    }
                }
            }
        }
    }
}

// Window delegate to handle window close events
class WindowCloseDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowCloseDelegate()
    weak var documentManager: DocumentManager?
    private weak var chromeWindow: NSWindow?
    private var chromeCancellable: AnyCancellable?

    /// Mirror the selected document into the window's titlebar: title and proxy icon
    /// (representedURL — drag-file-from-titlebar, ⌘-click path menu). The app previously carried
    /// document identity only in its own tab bar; the OS-level wayfinding affordances every
    /// macOS document app ships were absent.
    func attachWindowChrome(to window: NSWindow) {
        chromeWindow = window
        updateWindowChrome()
        chromeCancellable = documentManager?.objectWillChange
            // objectWillChange fires BEFORE the mutation — hop to the next main-queue
            // turn so we read post-mutation state.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateWindowChrome() }
    }

    private func updateWindowChrome() {
        guard let window = chromeWindow, let documentManager else { return }
        let doc = documentManager.selectedDocumentId.flatMap { id in
            documentManager.openDocuments.first(where: { $0.id == id })
        }
        let title = doc?.name ?? "Hashlight"
        let url = doc?.url
        // Equality guards: this runs on every DocumentManager publish (including find-bar
        // typing); actual window mutations must stay rare.
        if window.title != title { window.title = title }
        if window.representedURL != url { window.representedURL = url }
    }

    /// The red titlebar button closes every tab at once, without asking: there is nothing to
    /// save. The app keeps running and reopens to the welcome screen.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        documentManager?.closeAllDocuments()
        return true
    }

    /// Closing the last tab also dismisses the window. The red button's all-tabs close does not
    /// come through here (closeAllDocuments skips it), since that window is already closing.
    func closeWindowWhenEmpty() {
        guard documentManager?.openDocuments.isEmpty == true,
              chromeWindow != nil else { return }
        documentManager?.closeMainWindow()
    }
}
