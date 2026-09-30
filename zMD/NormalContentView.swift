import SwiftUI

struct NormalContentView: View {
    @EnvironmentObject private var documentManager: DocumentManager
    @EnvironmentObject private var folderManager: FolderManager
    @Binding var showOutline: Bool
    @Binding var selectedHeadingId: String?

    var body: some View {
        HStack(spacing: 0) {
            if folderManager.isShowingFolderSidebar {
                FolderSidebarView()
                    .fadeInUnderReduceMotion()
                    .transition(Motion.slideOrFade(edge: .leading))
                Divider()
            }

            if let selectedId = documentManager.selectedDocumentId,
               let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
                HStack(spacing: 0) {
                    if showOutline {
                        // .id(document.id) forces SwiftUI to create a fresh OutlineView when the
                        // active document changes, so the @State `headings` cache resets and gets
                        // rebuilt from onAppear. Without this, switching tabs sometimes left the
                        // outline showing the previous document's headings (onChange-of-content
                        // doesn't fire reliably across tab swaps on macOS 13).
                        OutlineView(content: document.content, selectedHeadingId: $selectedHeadingId)
                            .id(document.id)
                            .fadeInUnderReduceMotion()
                            .transition(Motion.slideOrFade(edge: .trailing))
                        Divider()
                    }

                    DocumentViewModeContent(
                        document: document,
                        selectedHeadingId: $selectedHeadingId
                    )
                }
                // showOutline is @AppStorage-backed; its write does not carry the toggle's
                // withAnimation transaction, so the outline appeared without its transition.
                .animation(Motion.standard, value: showOutline)
            } else {
                EmptyDocumentView()
            }
        }
    }
}
