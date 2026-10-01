import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        if let selectedId = documentManager.selectedDocumentId,
           let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
            HStack(spacing: 0) {
                // Left: word count, char count, reading time
                DocumentStatsText(content: document.content)

                Spacer()

                // Right: layout, zoom, encoding
                HStack(spacing: 8) {
                    // Content alignment positions the preview's text column. An inline Picker
                    // gives native menu checkmarks plus a self-describing header row.
                    Menu {
                        Picker("Content Alignment", selection: $settings.contentAlignment) {
                            ForEach(SettingsManager.ContentAlignment.allCases, id: \.self) { alignment in
                                Label(alignment.displayName, systemImage: alignment.icon).tag(alignment)
                            }
                        }
                        .pickerStyle(.inline)

                        Picker("Content Width", selection: $settings.contentWidth) {
                            ForEach(SettingsManager.ContentWidth.allCases, id: \.self) { width in
                                Text(width.displayName).tag(width)
                            }
                        }
                        .pickerStyle(.inline)

                        Picker("Page Margin", selection: $settings.pageMargin) {
                            ForEach(SettingsManager.PageMargin.allCases, id: \.self) { margin in
                                Text(margin.rawValue).tag(margin)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: settings.contentAlignment.icon)
                            .foregroundStyle(settings.contentAlignment != .left ? .secondary : Color(NSColor.tertiaryLabelColor))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Content Alignment & Width")
                    .accessibilityLabel("Content Layout")
                    .accessibilityValue("\(settings.contentAlignment.displayName) aligned, \(settings.contentWidth.displayName) width, \(settings.pageMargin.rawValue) page margin")

                    Menu {
                        ForEach([50, 75, 90, 100, 110, 125, 150, 175, 200], id: \.self) { percent in
                            Button {
                                settings.zoomLevel = CGFloat(percent) / 100.0
                            } label: {
                                HStack {
                                    Text("\(percent)%")
                                    if Int(settings.zoomLevel * 100) == percent {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Reset to 100%") {
                            settings.resetZoom()
                        }
                        .disabled(settings.zoomLevel == 1.0)
                    } label: {
                        Text("\(Int(settings.zoomLevel * 100))%")
                            .foregroundStyle(settings.zoomLevel != 1.0 ? .secondary : Color(NSColor.tertiaryLabelColor))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Zoom")

                    Text(document.detectedEncoding)
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
        }
    }

}

/// Owns the word/char/reading-time computation so the O(content) split runs only when the
/// content actually changes. StatusBarView re-renders on every DocumentManager publish (find-bar
/// typing, match navigation, diagram renders) and previously re-split the ENTIRE document on
/// each of those renders.
private struct DocumentStatsText: View {
    let content: String
    @State private var stats: (words: Int, characters: Int, readingTime: Int) = (0, 0, 1)

    var body: some View {
        Text("\(stats.words) words  \u{00B7}  \(stats.characters) chars  \u{00B7}  \(stats.readingTime) min read")
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .onAppear { stats = Self.compute(content) }
            .onChange(of: content) { newContent in
                stats = Self.compute(newContent)
            }
    }

    private static func compute(_ content: String) -> (words: Int, characters: Int, readingTime: Int) {
        let characters = content.count
        let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let readingTime = max(1, (words + 199) / 200) // ~200 wpm, minimum 1 min
        return (words, characters, readingTime)
    }
}
