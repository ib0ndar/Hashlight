import SwiftUI

struct TabBar: View {
    @EnvironmentObject var documentManager: DocumentManager
    @Binding var showOutline: Bool
    @State private var addButtonHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    ForEach(documentManager.openDocuments) { document in
                        TabItem(
                            document: document,
                            isSelected: documentManager.selectedDocumentId == document.id
                        )
                        .transition(Motion.scaleOrFade())
                    }
                }
                .animation(Motion.standard, value: documentManager.openDocuments.map(\.id))
            }

            Spacer()

            // Add new tab button
            Button(action: {
                documentManager.openFile()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(addButtonHovered ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(addButtonHovered ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                    )
                    .scaleEffect(addButtonHovered && !Motion.reduceMotion ? 1.1 : 1.0)
            }
            .buttonStyle(PressableButtonStyle())
            .onHover { hovering in
                withAnimation(Motion.fast) {
                    addButtonHovered = hovering
                }
            }
            .padding(.horizontal, 4)
            .help("Open File")
            .accessibilityLabel("Open File")

            // Outline toggle button
            Button(action: {
                withAnimation(Motion.standard) {
                    showOutline.toggle()
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundStyle(showOutline ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PressableButtonStyle())
            .help("Toggle Outline")
            .accessibilityLabel("Toggle Outline")
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(.ultraThinMaterial)
    }
}

struct TabItem: View {
    @EnvironmentObject var documentManager: DocumentManager
    let document: MarkdownDocument
    let isSelected: Bool
    @State private var isDragTarget = false
    @State private var isHovered = false

    // Extracted from body: the inline ternaries pushed the older CI toolchain's type-checker
    // over its time budget ("unable to type-check this expression in reasonable time").
    private var titleColor: Color {
        if isSelected { return .primary }
        return isHovered ? Color.primary.opacity(0.8) : Color.secondary
    }

    private var tabFill: Color {
        if isDragTarget { return Color.accentColor.opacity(0.25) }
        if isSelected { return Color.accentColor.opacity(0.15) }
        return isHovered ? Color.accentColor.opacity(0.08) : Color.clear
    }

    private var tabStroke: Color {
        if isDragTarget { return Color.accentColor.opacity(0.6) }
        return isSelected ? Color.accentColor.opacity(0.3) : Color.clear
    }

    var body: some View {
        // A real Button (pattern proven on the command-palette rows): press-down highlight
        // and cancel-by-dragging-away come free, and VoiceOver gets a true button instead
        // of the tap-trait shim. The nested close Button still wins hits on itself, and
        // onDrag/onDrop/contextMenu attach outside the Button unchanged.
        Button {
            documentManager.selectedDocumentId = document.id
        } label: {
        HStack(spacing: 4) {
            Text(document.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(titleColor)

            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                withAnimation(Motion.standard) {
                    documentManager.closeDocument(document)
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PressableButtonStyle())
            .frame(width: 14, height: 14)
            .opacity(isHovered || isSelected ? 1.0 : 0.0)
            .accessibilityLabel("Close \(document.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(tabFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(tabStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        } // Button label
        .buttonStyle(PressableButtonStyle())
        .help(document.url.path)
        .onHover { hovering in
            withAnimation(Motion.fast) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(document.name)
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
    TabBar(showOutline: .constant(false))
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
