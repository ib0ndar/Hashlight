import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        TabView {
            AppearanceSettingsTab(settings: settings)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        // Height fits the tallest tab (Appearance: Theme, Font, Layout, Zoom). The tabs are
        // non-scrolling forms, so an undersized window silently cuts rows off.
        .frame(width: 480, height: 620)
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

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @ObservedObject var settings: SettingsManager
    @State private var isShowingAdvanced = false

    private var appAppearance: Binding<ColorScheme?> {
        Binding(
            get: { settings.colorScheme },
            set: { colorScheme in
                settings.colorScheme = colorScheme
                ApplicationAppearance.apply(colorScheme)
            }
        )
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: appAppearance) {
                    Text("System").tag(nil as ColorScheme?)
                    Text("Light").tag(ColorScheme.light as ColorScheme?)
                    Text("Dark").tag(ColorScheme.dark as ColorScheme?)
                }
                .pickerStyle(.segmented)

                Picker("Light mode", selection: $settings.lightPreviewThemeID) {
                    ForEach(PreviewThemeCatalog.light) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Dark mode", selection: $settings.darkPreviewThemeID) {
                    ForEach(PreviewThemeCatalog.dark) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Font") {
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

                HStack {
                    Text("Preview")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Markdown text")
                        .font(PreviewFontCatalog.swiftUIFont(
                            id: settings.mainPreviewFontID,
                            size: 13,
                            monospaced: false
                        ))
                    Text("code --help")
                        .font(PreviewFontCatalog.swiftUIFont(
                            id: settings.fixedPreviewFontID,
                            size: 12,
                            monospaced: true
                        ))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Layout") {
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

                Text("Set the preview's maximum text width, horizontal page margin, and alignment. Full uses the available pane width; every preset shrinks to fit a narrow pane.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Zoom") {
                HStack {
                    Button {
                        settings.zoomOut()
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.zoomLevel <= 0.5)
                    .accessibilityLabel("Zoom Out")

                    Spacer()

                    Text("\(Int(settings.zoomLevel * 100))%")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .frame(width: 50)

                    Spacer()

                    Button {
                        settings.zoomIn()
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.zoomLevel >= 2.0)
                    .accessibilityLabel("Zoom In")
                }

                if settings.zoomLevel != 1.0 {
                    Button("Reset to 100%") {
                        settings.resetZoom()
                    }
                    .font(.system(size: 12))
                }
            }

            Section("Advanced") {
                Button("Advanced…") {
                    isShowingAdvanced = true
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isShowingAdvanced) {
            TableColumnCategoriesSettingsView(settings: settings)
        }
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Hashlight")
                .font(.system(size: 20, weight: .semibold))

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("A lightweight markdown viewer for macOS")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Text("Based on zMD by Zachary Rossmiller")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(.bottom, 12)
        }
    }
}


// MARK: - Advanced Appearance

private struct TableColumnCategoriesSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(settings.tableColumnConfiguration.categories.enumerated()), id: \.element.id) { index, category in
                    HStack {
                        NavigationLink {
                            TableColumnCategoryEditorView(settings: settings, categoryID: category.id)
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(index + 1))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(category.name.isEmpty ? "Untitled Category" : category.name)
                                        .foregroundStyle(.primary)
                                    Text("\(category.weight.formatted(.number.precision(.fractionLength(0...3)))) · \(category.words.count) match words")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer(minLength: 6)
                        VStack(spacing: 2) {
                            Button {
                                moveCategory(id: category.id, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(category.name) up")
                            Button {
                                moveCategory(id: category.id, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == settings.tableColumnConfiguration.categories.count - 1)
                            .accessibilityLabel("Move \(category.name) down")
                        }
                        .buttonStyle(.borderless)
                        if category.canBeRemoved {
                            Button(role: .destructive) {
                                removeCategory(id: category.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(category.name)")
                        }
                    }
                }
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .bottom) {
                Text("The first matching category wins. Other sets the weight for unmatched headers; if removed, the fallback weight is 1.0.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
            .navigationTitle("Table Categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addCategory()
                    } label: {
                        Label("Add Category", systemImage: "plus")
                    }
                    .help("Add a new table column category")
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    private func addCategory() {
        var configuration = settings.tableColumnConfiguration
        configuration.categories.append(
            MarkdownTableColumnCategory(
                id: UUID().uuidString.lowercased(),
                name: "New Category",
                weight: 1.0,
                words: []
            )
        )
        settings.tableColumnConfiguration = configuration
    }

    private func moveCategory(id: String, by offset: Int) {
        var configuration = settings.tableColumnConfiguration
        guard let index = configuration.categories.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard configuration.categories.indices.contains(destination) else { return }
        configuration.categories.swapAt(index, destination)
        settings.tableColumnConfiguration = configuration
    }

    private func removeCategory(id: String) {
        var configuration = settings.tableColumnConfiguration
        guard let index = configuration.categories.firstIndex(where: { $0.id == id }),
              configuration.categories[index].canBeRemoved else { return }
        configuration.categories.remove(at: index)
        settings.tableColumnConfiguration = configuration
    }
}

private struct TableColumnCategoryEditorView: View {
    @ObservedObject var settings: SettingsManager
    let categoryID: String
    @State private var newWord = ""

    private var category: Binding<MarkdownTableColumnCategory> {
        Binding(
            get: {
                settings.tableColumnConfiguration.categories.first(where: { $0.id == categoryID })
                    ?? MarkdownTableColumnCategory(id: categoryID, name: "Category", weight: 1.0, words: [])
            },
            set: { updatedCategory in
                var configuration = settings.tableColumnConfiguration
                guard let index = configuration.categories.firstIndex(where: { $0.id == categoryID }) else { return }
                configuration.categories[index] = updatedCategory
                settings.tableColumnConfiguration = configuration
            }
        )
    }

    private var weight: Binding<Double> {
        Binding(
            get: { category.wrappedValue.weight },
            set: { value in
                guard value.isFinite, value > 0 else { return }
                category.wrappedValue.weight = value
            }
        )
    }

    private var normalizedNewWord: String? {
        let words = MarkdownTableColumnLayout.tokens(in: newWord)
        guard words.count == 1 else { return nil }
        return words.first
    }

    var body: some View {
        Form {
            Section("Category") {
                TextField("Name", text: category.name)
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("Weight", value: weight, format: .number.precision(.fractionLength(0...3)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
                Text("Higher weights give matching columns more room.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                if category.wrappedValue.words.isEmpty {
                    Text("No matching words")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(category.wrappedValue.words.enumerated()), id: \.offset) { index, word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button {
                                category.wrappedValue.words.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(word)")
                        }
                    }
                }

                HStack {
                    TextField("Add one word", text: $newWord)
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(normalizedNewWord == nil)
                }
            } header: {
                Text("Matching words")
            } footer: {
                Text("Matching uses whole words from table headers. Add one word at a time.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.wrappedValue.name.isEmpty ? "Category" : category.wrappedValue.name)
    }

    private func addWord() {
        guard let word = normalizedNewWord else { return }
        let existing = category.wrappedValue.words
        guard !existing.contains(where: { MarkdownTableColumnLayout.tokens(in: $0).contains(word) }) else {
            newWord = ""
            return
        }
        category.wrappedValue.words.append(word)
        newWord = ""
    }
}
