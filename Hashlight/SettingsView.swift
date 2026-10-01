import SwiftUI

/// The Settings panes. The raw value is persisted, so Settings reopens on the last pane.
enum SettingsPane: String, CaseIterable {
    case general
    case viewing
    case tables

    static let width: CGFloat = 520

    /// Each pane sizes the window to its own content (HIG: a settings window accommodates the
    /// size of the current pane).
    var height: CGFloat {
        switch self {
        case .general: return 320
        case .viewing: return 690
        case .tables: return 440
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @AppStorage(DefaultsKeys.settingsPane) private var pane: SettingsPane = .general

    var body: some View {
        TabView(selection: $pane) {
            GeneralSettingsPane(settings: settings)
                .frame(width: SettingsPane.width, height: SettingsPane.general.height)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsPane.general)

            ViewingSettingsPane(settings: settings)
                .frame(width: SettingsPane.width, height: SettingsPane.viewing.height)
                .tabItem {
                    Label("Viewing", systemImage: "doc.richtext")
                }
                .tag(SettingsPane.viewing)

            TablesSettingsPane(settings: settings)
                .frame(width: SettingsPane.width, height: SettingsPane.tables.height)
                .tabItem {
                    Label("Tables", systemImage: "tablecells")
                }
                .tag(SettingsPane.tables)
        }
        .background(EscapeKeyHandler())
    }
}

/// Invisible helper that closes the enclosing window when Escape is pressed.
/// The Settings scene's NSWindow is created by AppKit itself, so there's no
/// SwiftUI `@State isPresented` to flip — we have to reach the real window.
private struct EscapeKeyHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        EscapeKeyHandlingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class EscapeKeyHandlingView: NSView {
    // nonisolated(unsafe): all live access is on the main actor; the annotation exists
    // solely so nonisolated deinit can remove the monitor (deinit has exclusive access).
    nonisolated(unsafe) private var escapeMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        guard let window else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard event.keyCode == 53, event.window === window else { return event }
            window?.performClose(nil)
            return nil
        }
    }

    deinit {
        // No assumeIsolated (traps if the last release happens off-main).
        // NSEvent.removeMonitor is documented as callable from any thread for
        // local monitors; deinit has exclusive access to the stored token.
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    @ObservedObject var settings: SettingsManager

    private var appAppearance: Binding<ColorScheme?> {
        Binding(
            get: { settings.colorScheme },
            set: { colorScheme in
                settings.colorScheme = colorScheme
                ApplicationAppearance.apply(colorScheme)
            }
        )
    }

    private var dockIconFootnote: String {
        if DockIconController.systemStylesAppIcon {
            return "System follows the icon style set in System Settings → Appearance. Frost and Ember change only the Dock and app switcher icon, while Hashlight runs."
        }
        return "System uses Frost in Light mode and Ember in Dark mode. Each choice changes only the Dock and app switcher icon, while Hashlight runs."
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: appAppearance) {
                    Text("System").tag(nil as ColorScheme?)
                    Text("Light").tag(ColorScheme.light as ColorScheme?)
                    Text("Dark").tag(ColorScheme.dark as ColorScheme?)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Dock icon", selection: $settings.dockIconMode) {
                    ForEach(SettingsManager.DockIconMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(dockIconFootnote)
            }

            Section {
                Toggle("Hide the tab bar when only one document is open", isOn: $settings.hidesTabBarForSingleDocument)
            } header: {
                Text("Tabs")
            } footer: {
                Text("The tab bar returns when a second document opens. Close Tab (⌘W) still closes the document.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Viewing

/// How documents are shown: theme, fonts, and the text column's layout.
struct ViewingSettingsPane: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Light mode", selection: $settings.lightPreviewThemeID) {
                    Text(PreviewThemeCatalog.systemLight.name).tag(PreviewTheme.systemLightID)
                    Divider()
                    ForEach(PreviewThemeCatalog.bundledLight) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Dark mode", selection: $settings.darkPreviewThemeID) {
                    Text(PreviewThemeCatalog.systemDark.name).tag(PreviewTheme.systemDarkID)
                    Divider()
                    ForEach(PreviewThemeCatalog.bundledDark) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Fonts") {
                Picker("Main font", selection: $settings.mainPreviewFontID) {
                    ForEach(PreviewFontCatalog.mainOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Fixed font", selection: $settings.fixedPreviewFontID) {
                    ForEach(PreviewFontCatalog.fixedOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Sample") {
                    HStack(spacing: 10) {
                        Text("Markdown text")
                            .font(PreviewFontCatalog.swiftUIFont(
                                id: settings.mainPreviewFontID,
                                size: 13,
                                monospaced: false
                            ))
                            .foregroundStyle(.primary)
                        Text("code --help")
                            .font(PreviewFontCatalog.swiftUIFont(
                                id: settings.fixedPreviewFontID,
                                size: 12,
                                monospaced: true
                            ))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker("Content alignment", selection: $settings.contentAlignment) {
                    ForEach(SettingsManager.ContentAlignment.allCases, id: \.self) { alignment in
                        Label(alignment.displayName, systemImage: alignment.icon).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Content width", selection: $settings.contentWidth) {
                    ForEach(SettingsManager.ContentWidth.allCases, id: \.self) { width in
                        Text(width.displayName).tag(width)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Page margin", selection: $settings.pageMargin) {
                    ForEach(SettingsManager.PageMargin.allCases, id: \.self) { margin in
                        Text(margin.rawValue).tag(margin)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Layout")
            } footer: {
                Text("Set the text column's maximum width, horizontal page margin, and alignment. Full uses the available pane width; every preset shrinks to fit a narrow pane. Zoom is in the View menu (⌘= / ⌘− / ⌘0).")
            }

            Section {
                Toggle("Show frontmatter", isOn: $settings.showsFrontmatter)
            } header: {
                Text("Document")
            } footer: {
                Text("A YAML block at the top of a file is shown as a folded card labelled with its title. Off, the document starts at its first heading or paragraph.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tables

struct TablesSettingsPane: View {
    @ObservedObject var settings: SettingsManager
    @State private var selectedID: String?
    @State private var editorRequest: CategoryEditorRequest?
    @State private var isConfirmingRestore = false

    private var configuration: MarkdownTableColumnConfiguration {
        settings.tableColumnConfiguration
    }

    private var selectedCategory: MarkdownTableColumnCategory? {
        selectedID.flatMap { configuration.category(withID: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Size columns by header category")
                        .font(.headline)
                    Text("Off, each column gets the width its content needs, and in a table too wide for the page the longest columns share the space left. On, the categories below give each column its room.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Size columns by header category", isOn: $settings.tableColumnWeightsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider()
                .padding(.vertical, 4)

            categoriesSection
                .disabled(!settings.tableColumnWeightsEnabled)
        }
        .padding(20)
        .background {
            // ⌥↑ / ⌥↓ move the selected category (also listed in the row menu).
            Group {
                Button("Move Up") { moveSelected(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: .option)
                Button("Move Down") { moveSelected(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: .option)
            }
            .opacity(0)
            .accessibilityHidden(true)
            .disabled(!settings.tableColumnWeightsEnabled)
        }
        .sheet(item: $editorRequest) { request in
            TableColumnCategoryEditorView(category: request.category, isNew: request.isNew) { category in
                settings.tableColumnConfiguration = configuration.savingCategory(category)
                selectedID = category.id
            }
        }
        .confirmationDialog("Restore the default column categories?", isPresented: $isConfirmingRestore) {
            Button("Restore Defaults", role: .destructive) {
                settings.tableColumnConfiguration = .defaults
                selectedID = nil
            }
        } message: {
            Text("Your categories, weights, and match words are replaced by the defaults.")
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Column categories")
                .font(.headline)
                .modifier(DimmedWhenDisabled())
            Text("Table columns get room in proportion to the weight of the first category whose words match the header. Other supplies the weight for unmatched headers; if removed, the fallback weight is 1.0. Drag rows to change the order.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            categoryTable

            HStack(spacing: 8) {
                ControlGroup {
                    Button {
                        editorRequest = CategoryEditorRequest(category: MarkdownTableColumnConfiguration.newCategory(), isNew: true)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a category")
                    .accessibilityLabel("Add Category")

                    Button {
                        removeSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedCategory?.canBeRemoved != true)
                    .help("Remove the selected category")
                    .accessibilityLabel("Remove Category")
                }
                .fixedSize()

                Spacer()

                Button("Edit Category…") {
                    editSelected()
                }
                .disabled(selectedCategory == nil)

                Button("Restore Defaults") {
                    isConfirmingRestore = true
                }
                .disabled(configuration.isDefault)
            }
        }
    }

    // Alternating stripes continue past the last row and the bottom one is clipped by the
    // buttons; selection alone marks rows.
    @ViewBuilder private var categoryTable: some View {
        if #available(macOS 14, *) {
            baseCategoryTable.alternatingRowBackgrounds(.disabled)
        } else {
            baseCategoryTable
        }
    }

    private var baseCategoryTable: some View {
        Table(of: MarkdownTableColumnCategory.self, selection: $selectedID) {
            TableColumn("Category") { category in
                Text(category.name.isEmpty ? "Untitled Category" : category.name)
                    .modifier(DimmedWhenDisabled())
            }
            TableColumn("Weight") { category in
                Text(category.weight.formatted(.number.precision(.fractionLength(0...3))))
                    .monospacedDigit()
                    .modifier(DimmedWhenDisabled())
            }
            .width(70)
            TableColumn("Match words") { category in
                Text("\(category.words.count)")
                    .monospacedDigit()
                    .modifier(DimmedWhenDisabled())
            }
            .width(90)
        } rows: {
            ForEach(configuration.categories) { category in
                TableRow(category)
                    .itemProvider {
                        NSItemProvider(object: category.id as NSString)
                    }
            }
            .dropDestination(for: String.self) { index, ids in
                settings.tableColumnConfiguration = configuration.movingCategories(withIDs: ids, to: index)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let category = configuration.category(withID: id) {
                Button("Edit Category…") {
                    editorRequest = CategoryEditorRequest(category: category, isNew: false)
                }
                Divider()
                Button("Move Up") {
                    settings.tableColumnConfiguration = configuration.movingCategory(withID: id, by: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: .option)
                .disabled(configuration.categories.first?.id == id)
                Button("Move Down") {
                    settings.tableColumnConfiguration = configuration.movingCategory(withID: id, by: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: .option)
                .disabled(configuration.categories.last?.id == id)
                Divider()
                Button("Remove") {
                    settings.tableColumnConfiguration = configuration.removingCategory(withID: id)
                }
                .disabled(!category.canBeRemoved)
            }
        } primaryAction: { ids in
            if let id = ids.first, let category = configuration.category(withID: id) {
                editorRequest = CategoryEditorRequest(category: category, isNew: false)
            }
        }
        .onDeleteCommand(perform: removeSelected)
        // A disabled SwiftUI Table still selects, drags, and opens its menus.
        .allowsHitTesting(settings.tableColumnWeightsEnabled)
    }

    private func editSelected() {
        guard settings.tableColumnWeightsEnabled, let category = selectedCategory else { return }
        editorRequest = CategoryEditorRequest(category: category, isNew: false)
    }

    private func removeSelected() {
        guard settings.tableColumnWeightsEnabled,
              let id = selectedID, configuration.category(withID: id)?.canBeRemoved == true else { return }
        settings.tableColumnConfiguration = configuration.removingCategory(withID: id)
        selectedID = nil
    }

    private func moveSelected(by offset: Int) {
        guard settings.tableColumnWeightsEnabled, let id = selectedID else { return }
        settings.tableColumnConfiguration = configuration.movingCategory(withID: id, by: offset)
    }
}

/// Dims a category table cell while the table is disabled; SwiftUI's Table keeps the text as is.
private struct DimmedWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder func body(content: Content) -> some View {
        if isEnabled {
            content
        } else {
            content.foregroundStyle(.tertiary)
        }
    }
}

private struct CategoryEditorRequest: Identifiable {
    let category: MarkdownTableColumnCategory
    let isNew: Bool
    var id: String { category.id }
}

/// Edits a copy of one category; Done saves it, Cancel discards it.
private struct TableColumnCategoryEditorView: View {
    let isNew: Bool
    let onSave: (MarkdownTableColumnCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MarkdownTableColumnCategory
    @State private var newWord = ""

    init(category: MarkdownTableColumnCategory, isNew: Bool, onSave: @escaping (MarkdownTableColumnCategory) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: category)
    }

    private var isValid: Bool {
        draft.weight.isFinite && draft.weight > 0
    }

    private var normalizedNewWord: String? {
        let words = MarkdownTableColumnLayout.tokens(in: newWord)
        guard words.count == 1 else { return nil }
        return words.first
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                TextField("Weight", value: $draft.weight, format: .number.precision(.fractionLength(0...3)))
            } header: {
                Text(isNew ? "New Category" : "Category")
            } footer: {
                Text("Higher weights give matching columns more room.")
            }

            Section {
                if draft.words.isEmpty {
                    Text("No matching words")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(draft.words.enumerated()), id: \.offset) { index, word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button {
                                draft.words.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(word)")
                            .accessibilityLabel("Remove \(word)")
                        }
                    }
                }

                HStack {
                    TextField("Add word", text: $newWord, prompt: Text("Add one word"))
                        .labelsHidden()
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(normalizedNewWord == nil)
                }
            } header: {
                Text("Matching Words")
            } footer: {
                Text("Matching uses whole words from table headers. Add one word at a time.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: save)
                    .disabled(!isValid)
            }
        }
    }

    private func save() {
        // Commit a weight still being typed: a number field updates its binding only when
        // editing ends. A word typed but not added yet is added too.
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async {
            guard isValid else { return }
            addWord()
            onSave(draft)
            dismiss()
        }
    }

    private func addWord() {
        guard let word = normalizedNewWord else { return }
        let existing = draft.words
        guard !existing.contains(where: { MarkdownTableColumnLayout.tokens(in: $0).contains(word) }) else {
            newWord = ""
            return
        }
        draft.words.append(word)
        newWord = ""
    }
}
