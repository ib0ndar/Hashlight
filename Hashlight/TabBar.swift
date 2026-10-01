import SwiftUI

/// Document tabs as a plain strip in the content layer (Xcode/Safari pattern). Window-level
/// actions live in the toolbar, not here.
struct TabBar: View {
    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 2) {
                ForEach(documentManager.openDocuments) { document in
                    TabItem(
                        document: document,
                        isSelected: documentManager.selectedDocumentId == document.id
                    )
                    .transition(Motion.scaleOrFade())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .animation(Motion.standard, value: documentManager.openDocuments.map(\.id))
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct TabItem: View {
    @EnvironmentObject var documentManager: DocumentManager
    let document: MarkdownDocument
    let isSelected: Bool
    @State private var isDragTarget = false
    @State private var isHovered = false

    // Extracted from body: inline ternaries pushed the older CI toolchain's type-checker
    // over its time budget ("unable to type-check this expression in reasonable time").
    private var tabFill: AnyShapeStyle {
        if isDragTarget { return AnyShapeStyle(.tertiary) }
        if isSelected { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(.clear)
    }

    var body: some View {
        // A real Button: press-down highlight and cancel-by-dragging-away come free, and
        // VoiceOver gets a true button. The nested close Button still wins hits on itself, and
        // onDrag/onDrop/contextMenu attach outside the Button unchanged.
        Button {
            documentManager.selectedDocumentId = document.id
        } label: {
            HStack(spacing: 6) {
                Text(document.name)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    withAnimation(Motion.standard) {
                        documentManager.closeDocument(document)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isSelected ? 1.0 : 0.0)
                .help("Close Tab")
                .accessibilityLabel("Close \(document.name)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tabFill, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(document.url.path)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(document.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onDrag {
            documentManager.draggingDocumentId = document.id
            return NSItemProvider(object: document.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: $isDragTarget) { _ in
            guard let sourceId = documentManager.draggingDocumentId,
                  let targetIndex = documentManager.openDocuments.firstIndex(where: { $0.id == document.id }) else { return false }
            withAnimation(Motion.standard) {
                documentManager.moveDocument(withId: sourceId, toIndex: targetIndex)
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            documentManager.draggingDocumentId = nil
            return true
        }
        .contextMenu {
            Button("Refresh") {
                documentManager.reloadDocument(document)
            }

            Divider()

            Button("Close Tab") {
                documentManager.closeDocument(document)
            }

            Button("Close Other Tabs") {
                documentManager.closeOtherDocuments(except: document)
            }

            Divider()

            Button("Reveal in Finder") {
                documentManager.revealInFinder(document: document)
            }
        }
    }
}

#Preview {
    TabBar()
        .environmentObject({
            let manager = DocumentManager()
            manager.openDocuments = [
                MarkdownDocument(url: URL(fileURLWithPath: "/test1.md"), content: ""),
                MarkdownDocument(url: URL(fileURLWithPath: "/test2.md"), content: "")
            ]
            manager.selectedDocumentId = manager.openDocuments.first?.id
            return manager
        }())
}
