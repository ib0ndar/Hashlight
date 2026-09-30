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
            tableColumnConfiguration: settings.tableColumnConfiguration
        )
    }
}
