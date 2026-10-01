import SwiftUI

/// The navigator's Outline mode: the document's headings as a sidebar list.
struct OutlineView: View {
    let content: String
    /// A scroll request for the preview, which clears it once it has scrolled.
    @Binding var selectedHeadingId: String?

    /// Cached outline so we don't re-parse the entire document on every SwiftUI body evaluation.
    /// Rebuilt only when `content` actually changes, debounced by SwiftUI's natural update cadence.
    @State private var headings: [OutlineItem] = []
    /// The highlighted row. Kept apart from `selectedHeadingId`, which the preview resets.
    @State private var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(headings) { item in
                Text(item.text)
                    .fontWeight(item.level == 1 ? .medium : .regular)
                    .lineLimit(1)
                    .padding(.leading, CGFloat(item.level - 1) * 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // Clicking the already selected heading does not change the selection, but
                    // it should still scroll back to it.
                    .simultaneousGesture(TapGesture().onEnded {
                        selectedHeadingId = item.id
                    })
                    .help(item.text)
                    .tag(item.id)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if headings.isEmpty {
                NavigatorPlaceholder(title: "No Headings", message: "Headings in the document appear here.")
            }
        }
        .onChange(of: selection) { id in
            if let id {
                selectedHeadingId = id
            }
        }
        .onAppear { rebuildOutline() }
        .onChange(of: content) { _ in rebuildOutline() }
    }

    private func rebuildOutline() {
        // Delegate to MarkdownParser so the outline uses the same stable slug IDs as the
        // preview renderer's heading ranges — click targets stay accurate after edits above,
        // and `#` lines inside fenced code blocks do not appear as phantom entries.
        headings = MarkdownParser.shared.extractHeadings(content).map {
            OutlineItem(id: $0.id, level: $0.level, text: $0.text)
        }
        if let selection, !headings.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }
}

struct OutlineItem: Identifiable {
    let id: String
    let level: Int
    let text: String
}

#Preview {
    OutlineView(content: """
    # Main Title
    ## Section 1
    ### Subsection 1.1
    ### Subsection 1.2
    ## Section 2
    # Another Title
    """, selectedHeadingId: .constant(nil))
}
