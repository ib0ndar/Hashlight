import SwiftUI

/// The main window's toolbar. SwiftUI adds the sidebar toggle itself; every item here is also a
/// menu command (HIG: toolbar items must be reachable from the menu bar).
struct ViewerToolbar: ViewModifier {
    @ObservedObject var documentManager: DocumentManager
    let hasDocument: Bool
    /// Focus mode keeps the title bar (title and window controls) but shows no toolbar items.
    var isFocusMode = false

    func body(content: Content) -> some View {
        // Toolbar builders can use `if #available` only from macOS 14.5, so the macOS 26
        // grouping is chosen here, at the view level.
        if #available(macOS 26, *) {
            content.toolbar {
                if !isFocusMode {
                    openItem
                }
                if hasDocument && !isFocusMode {
                    documentItems
                    ToolbarSpacer(.fixed)
                }
                if showsMatchCounter {
                    ToolbarItem {
                        matchCounter
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        } else {
            content.toolbar {
                if !isFocusMode {
                    openItem
                }
                if hasDocument && !isFocusMode {
                    documentItems
                }
                if showsMatchCounter {
                    ToolbarItem {
                        matchCounter
                    }
                }
            }
        }
    }

    private var showsMatchCounter: Bool {
        hasDocument && !isFocusMode && documentManager.isSearching && !documentManager.searchText.isEmpty
    }

    @ToolbarContentBuilder
    private var openItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                documentManager.openFile()
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .help("Open a Markdown file")
        }
    }

    @ToolbarContentBuilder
    private var documentItems: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                NotificationCenter.default.post(name: .toggleFocusMode, object: nil)
            } label: {
                Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Focus Mode")

            Menu {
                ExportMenuItems(documentManager: documentManager)
                Divider()
                PrintMenuItem(documentManager: documentManager)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export or print the document")
            .accessibilityLabel("Export")
        }
    }

    private var matchCounter: some View {
        let count = documentManager.renderedMatchCount
        let current = count > 0 ? documentManager.currentMatchIndex + 1 : 0
        return Text("\(current)/\(count)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityLabel("Match \(current) of \(count)")
    }
}

/// Export commands for the selected document, shared by File → Export and the toolbar.
struct ExportMenuItems: View {
    @ObservedObject var documentManager: DocumentManager

    var body: some View {
        Button("PDF...") {
            guard let document = documentManager.selectedDocument else { return }
            ExportManager.shared.exportToPDF(content: document.content, fileName: document.name, baseURL: document.url)
        }
        .disabled(documentManager.openDocuments.isEmpty)

        Divider()

        Button("HTML...") {
            guard let document = documentManager.selectedDocument else { return }
            ExportManager.shared.exportToHTML(content: document.content, fileName: document.name, includeStyles: true)
        }
        .disabled(documentManager.openDocuments.isEmpty)

        Button("HTML (without styles)...") {
            guard let document = documentManager.selectedDocument else { return }
            ExportManager.shared.exportToHTML(content: document.content, fileName: document.name, includeStyles: false)
        }
        .disabled(documentManager.openDocuments.isEmpty)

        Divider()

        Button("Word (.docx)...") {
            guard let document = documentManager.selectedDocument else { return }
            ExportManager.shared.exportToDOCX(content: document.content, fileName: document.name, baseURL: document.url)
        }
        .disabled(documentManager.openDocuments.isEmpty)

        Button("Word (.rtf)...") {
            guard let document = documentManager.selectedDocument else { return }
            ExportManager.shared.exportToWord(content: document.content, fileName: document.name, baseURL: document.url)
        }
        .disabled(documentManager.openDocuments.isEmpty)
    }
}

/// Print for the selected document, shared by File → Print and the toolbar's Export menu.
struct PrintMenuItem: View {
    @ObservedObject var documentManager: DocumentManager

    var body: some View {
        Button {
            guard let document = documentManager.selectedDocument else { return }
            PrintManager.shared.print(content: document.content, fileName: document.name)
        } label: {
            Label("Print...", systemImage: "printer")
        }
        .disabled(documentManager.openDocuments.isEmpty)
    }
}

/// Moves keyboard focus to the toolbar's search field (⌘F). SwiftUI can do this itself only
/// from macOS 14 (`searchable(text:isPresented:)`), so this goes through AppKit.
enum FindField {
    static func focus(in window: NSWindow? = nil) {
        guard let window = window
                ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })
                ?? NSApp.mainWindow else { return }
        if let item = window.toolbar?.items.lazy.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
        } else if let field = searchField(in: window.contentView?.superview) {
            window.makeFirstResponder(field)
        }
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = searchField(in: subview) { return field }
        }
        return nil
    }
}
