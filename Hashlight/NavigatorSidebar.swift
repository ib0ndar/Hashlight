import SwiftUI

/// The main window's sidebar: one navigator that switches between the open folder's files and
/// the selected document's outline (Xcode's navigator pattern).
struct NavigatorSidebar: View {
    @EnvironmentObject private var documentManager: DocumentManager
    @EnvironmentObject private var folderManager: FolderManager
    @EnvironmentObject private var settings: SettingsManager
    @Binding var selectedHeadingId: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Navigator", selection: $settings.navigatorMode) {
                ForEach(SettingsManager.NavigatorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            navigatorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var navigatorContent: some View {
        switch settings.navigatorMode {
        case .files:
            if folderManager.isFolderOpen {
                FolderSidebarView()
            } else {
                NavigatorPlaceholder(title: "No Folder Open", message: "Open a folder to browse its Markdown files.") {
                    Button("Open Folder…") {
                        folderManager.openFolder()
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .outline:
            if let selectedId = documentManager.selectedDocumentId,
               let document = documentManager.openDocuments.first(where: { $0.id == selectedId }) {
                // .id(document.id) gives each document a fresh OutlineView, so its cached
                // headings and selection never show the previous document's outline.
                OutlineView(content: document.content, selectedHeadingId: $selectedHeadingId)
                    .id(document.id)
            } else {
                NavigatorPlaceholder(title: "No Document", message: "Open a document to see its outline.")
            }
        }
    }
}

/// Empty state for a navigator mode that has nothing to list.
struct NavigatorPlaceholder<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            actions()
                .padding(.top, 6)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension NavigatorPlaceholder where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}
