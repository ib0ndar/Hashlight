import SwiftUI

/// Presents one document as its rendered preview.
struct DocumentViewModeContent: View {
    @EnvironmentObject private var documentManager: DocumentManager
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    let document: MarkdownDocument
    @Binding var selectedHeadingId: String?

    var body: some View {
        MarkdownTextView(
            content: document.content,
            baseURL: document.url,
            directoryBookmark: document.directoryBookmarkData,
            documentId: document.id,
            scrollToHeadingId: $selectedHeadingId,
            searchText: documentManager.isSearching ? documentManager.searchText : "",
            currentMatchIndex: documentManager.currentMatchIndex,
            mainFontID: settings.mainPreviewFontID,
            fixedFontID: settings.fixedPreviewFontID,
            theme: PreviewThemeCatalog.resolve(
                lightID: settings.lightPreviewThemeID,
                darkID: settings.darkPreviewThemeID,
                colorScheme: colorScheme
            ),
            zoomLevel: settings.zoomLevel,
            initialScrollPosition: documentManager.getScrollPosition(for: document.url),
            onScrollPositionChanged: { position in
                documentManager.setScrollPosition(position, for: document.url)
            },
            onMatchCountChanged: { count in
                documentManager.setRenderedMatchCount(count)
            },
            contentAlignment: settings.contentAlignment,
            contentWidth: settings.contentWidth,
            pageMargin: settings.pageMargin,
            tableColumnConfiguration: settings.tableColumnConfiguration,
            showsFrontmatter: settings.showsFrontmatter
        )
        .onAppear {
            DispatchQueue.main.async {
                PreviewFocus.focusPreviewIfIdle()
            }
        }
    }
}

/// Gives the preview keyboard focus (Space, arrows and Page keys scroll it) when it appears,
/// unless the user is working in a text field or a list. Without this the window's first key
/// view, the toolbar's sidebar toggle, took focus and Space toggled the sidebar.
enum PreviewFocus {
    static func focusPreviewIfIdle() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }),
              let preview = firstPreview(in: window.contentView) else { return }
        let responder = window.firstResponder
        if responder is NSTextView || responder is NSTableView { return }
        window.makeFirstResponder(preview)
    }

    private static func firstPreview(in view: NSView?) -> PreviewTextView? {
        guard let view else { return nil }
        if let preview = view as? PreviewTextView { return preview }
        for subview in view.subviews {
            if let preview = firstPreview(in: subview) { return preview }
        }
        return nil
    }
}
