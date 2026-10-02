import SwiftUI

/// The split view's detail column while documents are open: the tab strip, the preview, the
/// status bar, and the window toolbar with Find. Focus mode keeps only the preview.
struct NormalContentView: View {
    @EnvironmentObject private var documentManager: DocumentManager
    @EnvironmentObject private var settings: SettingsManager
    @Binding var selectedHeadingId: String?

    /// The tab strip is shown outside focus mode, unless the setting hides it for a lone
    /// document; it comes back as soon as a second one opens.
    private var showsTabBar: Bool {
        guard !documentManager.isFocusModeActive else { return false }
        return !(settings.hidesTabBarForSingleDocument && documentManager.openDocuments.count == 1)
    }

    var body: some View {
        if let document = documentManager.selectedDocument {
            documentColumn(document)
        } else {
            EmptyDocumentView()
                .modifier(ViewerToolbar(documentManager: documentManager, hasDocument: false))
        }
    }

    private func documentColumn(_ document: MarkdownDocument) -> some View {
        let isFocusMode = documentManager.isFocusModeActive
        return VStack(spacing: 0) {
            if showsTabBar {
                TabBar()
                    .transition(Motion.slideOrFade(edge: .top))
            }

            // Focus mode shows the same preview, with the reader's alignment, width, and margin;
            // its scroll view runs under the transparent title bar, where AppKit insets its
            // content for the bar and applies the scroll edge effect. One view for both modes
            // keeps the preview (and its scroll position) when focus mode toggles.
            DocumentViewModeContent(document: document, selectedHeadingId: $selectedHeadingId)
                .ignoresSafeArea(.container, edges: isFocusMode ? .top : [])
        }
        .modifier(StatusBarPlacement(isShown: !isFocusMode, documentManager: documentManager, settings: settings))
        .animation(Motion.standard, value: showsTabBar)
        // Focus mode shows no title or proxy icon: SwiftUI owns them and re-asserts the
        // window's title visibility, so they are cleared here rather than through NSWindow.
        .navigationTitle(isFocusMode ? "" : document.name)
        .modifier(DocumentProxy(url: isFocusMode ? nil : document.url))
        .modifier(ViewerToolbar(documentManager: documentManager, hasDocument: true, isFocusMode: isFocusMode))
        .modifier(ToolbarFind(documentManager: documentManager, isShown: !isFocusMode))
        .onChange(of: documentManager.searchText) { text in
            // The field is always in the toolbar: typing starts a find, and clearing the field
            // (Escape, its clear button) ends it and removes the highlights.
            if text.isEmpty {
                if documentManager.isSearching {
                    documentManager.endSearch()
                }
            } else if !documentManager.isSearching {
                documentManager.isSearching = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusFindField)) { _ in
            guard !documentManager.isFocusModeActive else { return }
            if !documentManager.isSearching {
                documentManager.startSearch()
            }
            DispatchQueue.main.async {
                FindField.focus()
            }
        }
    }
}

/// The title bar's proxy icon and drag source, present outside focus mode.
private struct DocumentProxy: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.navigationDocument(url)
        } else {
            content
        }
    }
}

/// Find as the toolbar's search field; Return goes to the next match. Focus mode, which shows
/// only the document, has no search field (the preview keeps any current highlights).
private struct ToolbarFind: ViewModifier {
    @ObservedObject var documentManager: DocumentManager
    let isShown: Bool

    func body(content: Content) -> some View {
        if isShown {
            content
                .searchable(text: $documentManager.searchText, placement: .toolbar, prompt: "Find in document")
                .onSubmit(of: .search) {
                    documentManager.nextMatch()
                }
        } else {
            content
        }
    }
}

/// Places the status bar under the detail column. On macOS 26 it is a split-item accessory
/// (`StatusBarAccessoryAnchor`): AppKit insets the preview's scroll view for it and draws the
/// scroll edge effect where the document passes underneath. Before that, or if the accessory
/// cannot attach, it is an inset on the standard bar material.
private struct StatusBarPlacement: ViewModifier {
    let isShown: Bool
    let documentManager: DocumentManager
    let settings: SettingsManager
    @State private var accessoryIsAttached = true

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background {
                    StatusBarAccessoryAnchor(isShown: isShown, isAttached: $accessoryIsAttached) {
                        StatusBarView()
                            .environmentObject(documentManager)
                            .environmentObject(settings)
                    }
                    .frame(width: 0, height: 0)
                }
                .modifier(InsetStatusBar(isShown: isShown && !accessoryIsAttached))
        } else {
            content.modifier(InsetStatusBar(isShown: isShown))
        }
    }
}

/// The status bar as a bottom inset on the standard bar material.
private struct InsetStatusBar: ViewModifier {
    let isShown: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if isShown {
                VStack(spacing: 0) {
                    Divider()
                    StatusBarView()
                }
                .background(.bar)
                .transition(Motion.slideOrFade(edge: .bottom))
            }
        }
    }
}
