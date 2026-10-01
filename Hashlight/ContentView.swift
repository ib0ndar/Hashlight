import SwiftUI

struct ContentView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var folderManager: FolderManager
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismissWindow
    @State private var selectedHeadingId: String?
    @State private var showQuickOpen = false
    /// Text Quick Open opens with: "" normally, ">" for Search in Folder.
    @State private var quickOpenInitialQuery = ""
    @State private var showCommandPalette = false
    @State private var showFocusExitPill = false
    @State private var magnifyMonitor: Any?
    @State private var baseZoomForGesture: CGFloat = 1.0
    /// Timestamp of the last zoomLevel write emitted from a live pinch tick (throttle state).
    @State private var lastZoomGestureEmit: Date = .distantPast

    /// Focus mode hides the sidebar without changing the saved visibility.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                settings.isNavigatorVisible && !documentManager.isFocusModeActive ? .all : .detailOnly
            },
            set: { visibility in
                guard !documentManager.isFocusModeActive else { return }
                settings.isNavigatorVisible = visibility != .detailOnly
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            NavigatorSidebar(selectedHeadingId: $selectedHeadingId)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                .modifier(SidebarToggleRemoval(isRemoved: documentManager.isFocusModeActive))
        } detail: {
            ZStack {
                Group {
                    if documentManager.openDocuments.isEmpty {
                        WelcomeView()
                            .modifier(ViewerToolbar(documentManager: documentManager, hasDocument: false))
                            .transition(.opacity)
                    } else {
                        NormalContentView(selectedHeadingId: $selectedHeadingId)
                    }
                }
                .animation(Motion.standard, value: documentManager.openDocuments.isEmpty)

                if documentManager.isFocusModeActive {
                    focusModeControls
                }
            }
        }
        .overlay {
            QuickOpenOverlay(isPresented: $showQuickOpen, selectedHeadingId: $selectedHeadingId, initialQuery: quickOpenInitialQuery)
                .environmentObject(documentManager)
        }
        .overlay {
            if showCommandPalette {
                CommandPaletteOverlay(isPresented: $showCommandPalette)
                    .environmentObject(documentManager)
                    .environmentObject(folderManager)
            }
        }
        .overlay {
            ToastOverlay()
        }
        // The `.keyboardShortcut("o", [.command, .shift])` previously attached here was dead —
        // SwiftUI's .keyboardShortcut only binds to an interactable control (Button, MenuItem).
        // Without a control it was never wired to anything; the real Quick Open shortcut lives
        // on the File menu. Removed.
        .onReceive(NotificationCenter.default.publisher(for: .showQuickOpen)) { _ in
            showCommandPalette = false
            quickOpenInitialQuery = ""
            showQuickOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFolderSearch)) { _ in
            showCommandPalette = false
            quickOpenInitialQuery = ">"
            showQuickOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            showQuickOpen = false
            showCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFocusMode)) { _ in
            withAnimation(Motion.sidebar) {
                documentManager.isFocusModeActive.toggle()
            }
        }
        .onAppear {
            documentManager.registerMainWindowOpener {
                openWindow(id: "main")
            }
            documentManager.registerMainWindowCloser {
                dismissWindow()
            }
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
                if event.phase == .began {
                    baseZoomForGesture = SettingsManager.shared.zoomLevel
                }
                // Accumulate delta magnification
                baseZoomForGesture += event.magnification
                let clamped = min(2.0, max(0.5, baseZoomForGesture))
                // Snap to 10% increments on gesture end
                if event.phase == .ended || event.phase == .cancelled {
                    SettingsManager.shared.zoomLevel = (clamped * 10).rounded() / 10
                    baseZoomForGesture = SettingsManager.shared.zoomLevel
                } else {
                    // Quantize live ticks to 5% steps and throttle to ~12 writes/s. Every
                    // zoomLevel write triggers an IMMEDIATE full preview rebuild with a 100%
                    // element-cache miss (zoom is part of the cache key) — raw .magnify events
                    // arrive ~60/s, which wired the app's one live-tracked gesture straight
                    // into its most expensive operation. Keyboard zoom (⌘+/-) is untouched:
                    // discrete steps stay immediate.
                    let stepped = (clamped * 20).rounded() / 20
                    let now = Date.now
                    if stepped != SettingsManager.shared.zoomLevel,
                       now.timeIntervalSince(lastZoomGestureEmit) > 0.08 {
                        lastZoomGestureEmit = now
                        SettingsManager.shared.zoomLevel = stepped
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = magnifyMonitor {
                NSEvent.removeMonitor(monitor)
                magnifyMonitor = nil
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            DropHandler.handle(providers: providers, documentManager: documentManager)
            return true
        }
    }

    /// Escape and a hover-revealed button leave focus mode. The hidden cancelAction button
    /// catches Escape without a local NSEvent monitor.
    @ViewBuilder
    private var focusModeControls: some View {
        Button("Exit Focus Mode", action: exitFocusMode)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityLabel("Exit Focus Mode")

        VStack {
            ZStack {
                if showFocusExitPill {
                    focusExitButton
                        .transition(Motion.slideOrFade(edge: .top))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .top)
            .padding(.top, 12)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(Motion.entrance) {
                    showFocusExitPill = hovering
                }
            }
            Spacer()
        }
    }

    /// A floating control over content: Liquid Glass on macOS 26, a bordered button before.
    @ViewBuilder
    private var focusExitButton: some View {
        let button = Button(action: exitFocusMode) {
            Label("Exit Focus Mode", systemImage: "arrow.down.left.and.arrow.up.right")
        }
        if #available(macOS 26, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func exitFocusMode() {
        withAnimation(Motion.sidebar) {
            documentManager.isFocusModeActive = false
        }
    }
}

extension Notification.Name {
    static let showQuickOpen = Notification.Name("showQuickOpen")
    static let showFolderSearch = Notification.Name("showFolderSearch")
    static let showCommandPalette = Notification.Name("showCommandPalette")
    static let toggleFocusMode = Notification.Name("toggleFocusMode")
    /// ⌘F: start a find and focus the toolbar's search field.
    static let focusFindField = Notification.Name("focusFindField")
}

/// Focus mode hides the sidebar, so it also drops the toolbar's sidebar toggle (macOS 14+; on
/// macOS 13 the toggle stays and does nothing while focus mode is on).
private struct SidebarToggleRemoval: ViewModifier {
    let isRemoved: Bool

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.toolbar(removing: isRemoved ? .sidebarToggle : nil)
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DocumentManager())
        .environmentObject(FolderManager.shared)
        .environmentObject(SettingsManager.shared)
}
