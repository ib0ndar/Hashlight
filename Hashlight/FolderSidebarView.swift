import SwiftUI

/// The navigator's Files mode: the open folder's Markdown files as a sidebar outline list.
struct FolderSidebarView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @EnvironmentObject var folderManager: FolderManager
    @State private var selection: String?

    var body: some View {
        List(selection: $selection) {
            Section {
                FileTreeRows(items: folderManager.fileTree, expandedDirectories: $folderManager.expandedDirectoryIDs)
            } header: {
                Text(folderManager.folderURL?.lastPathComponent ?? "Folder")
                    .contextMenu { folderMenu }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: String.self) { ids in
            if let item = ids.first.flatMap({ folderManager.itemsByID[$0] }) {
                itemMenu(item)
            } else {
                folderMenu
            }
        } primaryAction: { ids in
            guard let id = ids.first, let item = folderManager.itemsByID[id] else { return }
            if item.isDirectory {
                toggleExpansion(of: id)
            } else {
                documentManager.loadDocument(from: item.url)
            }
        }
        .onChange(of: selection) { id in
            guard let id, let item = folderManager.itemsByID[id], !item.isDirectory,
                  item.url.standardizedFileURL != activeDocumentURL?.standardizedFileURL else { return }
            documentManager.loadDocument(from: item.url)
        }
        .onChange(of: activeDocumentURL) { url in
            syncSelection(to: url)
        }
        .onReceive(folderManager.$fileTree) { _ in
            // The tree loads after the view appears and reloads on file-system changes.
            DispatchQueue.main.async { syncSelection(to: activeDocumentURL) }
        }
        .onAppear { syncSelection(to: activeDocumentURL) }
    }

    private var activeDocumentURL: URL? {
        guard let selectedId = documentManager.selectedDocumentId else { return nil }
        return documentManager.openDocuments.first(where: { $0.id == selectedId })?.url
    }

    private func syncSelection(to url: URL?) {
        let id = url.flatMap { folderManager.itemID(for: $0) }
        // Leave a selected folder row alone while the active document is outside the tree.
        if id != nil || selection.flatMap({ folderManager.itemsByID[$0] })?.isDirectory != true {
            if selection != id { selection = id }
        }
    }

    private func toggleExpansion(of id: String) {
        withAnimation(Motion.standard) {
            if folderManager.expandedDirectoryIDs.contains(id) {
                folderManager.expandedDirectoryIDs.remove(id)
            } else {
                folderManager.expandedDirectoryIDs.insert(id)
            }
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: FileTreeItem) -> some View {
        if !item.isDirectory {
            Button("Open") {
                documentManager.loadDocument(from: item.url)
            }
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
        Divider()
        folderMenu
    }

    @ViewBuilder
    private var folderMenu: some View {
        if let folderURL = folderManager.folderURL {
            Button("Reveal Folder in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            }
        }
        Button("Close Folder") {
            folderManager.closeFolder()
        }
    }
}

/// One level of the file tree; folders nest the next level in a disclosure group.
private struct FileTreeRows: View {
    let items: [FileTreeItem]
    @Binding var expandedDirectories: Set<String>

    var body: some View {
        ForEach(items) { item in
            if item.isDirectory, let children = item.children {
                DisclosureGroup(isExpanded: expansion(of: item.id)) {
                    FileTreeRows(items: children, expandedDirectories: $expandedDirectories)
                } label: {
                    Label(item.name, systemImage: "folder")
                        .lineLimit(1)
                        .tag(item.id)
                }
            } else {
                Label(item.name, systemImage: "doc.text")
                    .lineLimit(1)
                    .help(item.url.path)
                    .tag(item.id)
            }
        }
    }

    private func expansion(of id: String) -> Binding<Bool> {
        Binding(
            get: { expandedDirectories.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedDirectories.insert(id)
                } else {
                    expandedDirectories.remove(id)
                }
            }
        )
    }
}
