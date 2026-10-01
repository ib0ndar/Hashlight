# Plan 004: Adopt the Liquid Glass design (macOS 26/27) in the main window and Settings

- **Status**: DONE (approved by the owner, 2026-09-30; implemented and verified on macOS 26.7.1 on
  2026-09-30/10-01; not committed, awaiting the owner's review)
- **Created**: 2026-09-30
- **Source**: UI audit against Apple's Liquid Glass guidance,
  `artifacts/liquid-glass-audit-2026-09-30.md` (ignored; findings summarized below), and the
  rendered options in `artifacts/screens/liquid-glass-audit/` (comparison page
  `artifacts/screens/liquid-glass-audit-options.html`)
- **Requested by**: the owner, 2026-09-30 ("analyze the app's interface and Settings … according to
  the latest Apple Liquid Glass guidances for macOS 27 … I need your plan and suggestions")

## Decisions (owner, 2026-09-30)

Three options were rendered for the main window (A1 navigator sidebar, A2 sidebar + inspector,
A3 minimal change) and two for Settings (S1 three panes, S2 two panes). The owner chose:

1. **Main window: A1.** One leading `NavigationSplitView` sidebar that switches between **Files**
   and **Outline**; a real window toolbar; Find as a toolbar search field; document tabs as a plain
   strip in the content layer; the status bar kept as a bottom bar registered with the system.
2. **Settings: S1.** Three panes, **General · Preview · Tables**. About leaves Settings and becomes
   the standard App-menu About panel.
3. **Deployment target stays macOS 13.** macOS 26-only APIs (`safeAreaBar`, `ToolbarSpacer`,
   `.glass` button styles, `glassEffect`) and macOS 14-only ones (`inspector`, `Reorderable`) are
   gated with `if #available` and get a plain fallback below. Code must still build with Xcode 26.6
   on CI (`macos-26` runner) and Xcode 27 locally.

## Guidance this plan follows

Priority order of sources, with the rules applied. Quotes are from Apple.

1. **Adopting Liquid Glass** (Technology Overviews): "Reduce your use of custom backgrounds in
   controls and navigation elements … Prefer to remove custom effects and let the system determine
   the background appearance", especially for `titleBar`, `toolbar`, `NavigationSplitView`.
   "Consider using split views to build sidebar layouts with an inspector panel." "If you use a
   custom bar … register those views to use a scroll edge effect with … `safeAreaBar`." "Avoid
   overusing Liquid Glass effects" on custom controls. "Leverage new button styles … `glass`,
   `glassProminent`." "Check capitalization in section headers … title-style." "Adopt forms … with
   the grouped form style."
2. **HIG Materials**: "Don't use Liquid Glass in the content layer." "Use Liquid Glass effects
   sparingly." Standard materials belong to the content layer.
3. **HIG Toolbars (macOS)**: "the toolbar resides in the frame at the top of a window"; "Make every
   toolbar item available as a command in the menu bar"; "Prefer system-provided symbols without
   borders"; "aim for a maximum of three" groups; "Don't title windows with your app name."
4. **HIG Sidebars (macOS)**: show/hide from a toolbar button and View-menu commands; "Avoid putting
   critical information or actions at the bottom of a sidebar"; sidebar icons use the accent
   colour.
5. **HIG Settings (macOS)**: "a custom settings window contains a toolbar that includes buttons
   for switching between … panes"; "a settings window accommodates the size of the current pane";
   "Update the window's title to reflect the currently visible pane"; "Restore the most recently
   viewed pane"; "Put general, infrequently changed settings in your custom settings area";
   "prefer letting people modify task-specific options without going to your settings area";
   "Minimize the number of settings you offer."
6. **WWDC26-289 Modernize your AppKit app** (macOS 27): sidebars extend to the window's edges,
   selection uses semibold text, the automatic scroll-edge effect becomes hard-edged under
   free-floating text, glass gains an interactive "bounce", concentric corners via
   `cornerConfiguration` / `ConcentricRectangle`. All automatic for system components.
7. **WWDC26-269 What's new in SwiftUI**: the Liquid Glass slider retints all system glass; menu
   bar icons are minimal by default (opt in per key action with `labelStyle(.titleAndIcon)`);
   `visibilityPriority`, `ToolbarOverflowMenu`, `Reorderable`, `appearsActive`.
8. **WWDC25-323 Build a SwiftUI app with the new design**: toolbar items are grouped on glass;
   `ToolbarSpacer(.fixed)` separates groups; toolbar icons are monochrome; "If your app has any
   extra backgrounds or darkening effects behind the bar items, make sure to remove them."
9. Xcode 27's bundled guides (`IDEIntelligenceChat.framework/…/AdditionalDocumentation/
   SwiftUI-Implementing-Liquid-Glass-Design.md`, `SwiftUI-New-Toolbar-Features.md`).

## Findings being fixed

Main window (`artifacts/screens/liquid-glass-audit/01–04, 11–13`):

- M1 `TabBar`, `StatusBarView`, `OutlineView`, `FolderSidebarView` each paint `.ultraThinMaterial`.
- M2 No window toolbar; Open and Toggle Outline live in a custom 32 pt strip.
- M3 Sidebars are fixed-width `HStack` panes with hand-drawn `Divider`s (folder 220 pt, outline
  250 pt); they cannot float, resize, or extend to the window edges.
- M4 Find is a custom rounded box in the content column (`SearchBar`).
- M5 The status bar is a material strip without the scroll-edge effect.
- M6 Tab, outline and file rows use accent-tinted 4 pt selection fills and all-caps headers.
- M7 Command palette dims the content with `Color.black.opacity(0.3)` and uses five hard-coded
  category colours; Quick Open paints `windowBackgroundColor` on a layer.
- M8 Welcome screen draws its own accent pill button and an all-caps "RECENT FILES" label.
- M9 Focus-mode pill is `.ultraThinMaterial` + `Capsule` + shadow instead of a glass button.
- M10 `PressableButtonStyle` and `onHover` scale/tint effects stack on the system's own feedback.
- M11 `HelpView` sheet has a hand-drawn title/close row.
- M13 Two different window minimums (600×400 and 700×550) and a hand-positioned 1000×700 default.

Settings (`artifacts/screens/liquid-glass-audit/05–10`):

- S1 `SettingsView` fixes every pane at 480 × 620; Appearance overflows and scrolls, About is
  mostly empty.
- S2 One pane mixes app-wide, preview, and layout settings, a Zoom stepper that duplicates
  ⌘+/⌘−/⌘0 and the status-bar menu, and an "Advanced…" sheet.
- S3 About is a Settings pane.
- S4 The table-categories sheet is an iOS-style `NavigationStack` with chevron reordering; "Done"
  renders on the leading side; the category editor labels "Weight" twice.
- S5 Footnotes are plain rows instead of `Section` footers (extra divider above them).
- S6 Custom zoom stepper; a whole "Advanced" section for one button.

## Work plan

Order matters: the structural steps (1–3) remove most custom chrome at once; later steps are
independent polish and can be split into their own commits.

### 1. Main window structure (A1)

1. **`ContentView` → `NavigationSplitView`.** Replace `NormalContentView`'s `HStack` with
   `NavigationSplitView(columnVisibility:) { sidebar } detail: { … }`. The sidebar column hosts a
   new `NavigatorSidebar` view: a segmented `Picker` ("Files" / "Outline", `.labelsHidden()`) at
   the top and either the folder tree or the outline below. Column width `min 200, ideal 240`.
   Persist the chosen mode and column visibility in `SettingsManager`/`@AppStorage`
   (replace `DefaultsKeys.showOutline` with `navigatorMode` + `navigatorVisible`; migrate the old
   Bool: `showOutline == true` → visible, mode Outline).
   - Files mode when no folder is open: an empty state with an "Open Folder…" button (system
     `.bordered` style) instead of hiding the mode.
   - `FolderManager.isShowingFolderSidebar` becomes "a folder is open"; it no longer drives layout.
2. **Lists.** Rewrite `OutlineView` and `FolderSidebarView` bodies as `List(selection:)` with
   `.listStyle(.sidebar)`; remove their `.frame(width:)`, `.background(.ultraThinMaterial)`,
   custom headers, `Divider`s, hover state, `PressableButtonStyle`, and accent-tinted row fills.
   Outline rows: `Text` indented by level (`padding(.leading, (level-1)*14)`), level-1 rows
   `.fontWeight(.medium)`; selection drives `selectedHeadingId`. File rows: `Label(name,
   systemImage: folder ? "folder" : "doc.text")` inside `DisclosureGroup`/`OutlineGroup` on
   `FileTreeItem`; selection loads the document. Keep the existing context menus.
   Remove the "Close Folder" `xmark` from the sidebar header (HIG: no critical actions in sidebar
   headers/bottoms); File → Close Folder and a context-menu item on the root row remain.
3. **Toolbar.** Add `.toolbar { … }` to the detail view (SwiftUI adds the sidebar toggle itself):
   - group 1 (`.navigation`): `Open…` (`folder`);
   - group 2: `Focus Mode` (`arrow.up.left.and.arrow.down.right`) and an `Export` `Menu`
     (`square.and.arrow.up`) holding PDF/HTML/HTML without styles/DOCX/RTF and Print;
   - `.searchable(text:isPresented:placement: .toolbar, prompt: "Find in document")` bound to
     `DocumentManager.searchText` / `isSearching`; `onSubmit(of: .search)` → `nextMatch()`;
     ⌘F focuses the field (`searchPresentationToolbarBehavior`/`isPresented` binding), ⌘G/⇧⌘G stay
     as menu commands. Show the match counter as a trailing `Text("\(i)/\(n)")` toolbar item only
     while searching.
   - On macOS 26+ separate groups with `ToolbarSpacer(.fixed)`; below, rely on default grouping.
   - Every toolbar item already exists as a menu command (HIG). Add View → Show/Hide Sidebar and
     View → Navigator → Files / Outline commands (⌘⌥1 / ⌘⌥2 follow Xcode's navigator shortcuts;
     confirm no collision with existing bindings).
   - Set `.navigationTitle(document.name)` and `.navigationDocument(url)` on the detail view and
     delete the manual `window.title` / `representedURL` mirroring in `WindowCloseDelegate`
     (keep the delegate for close behaviour). The window title stays the document name; the
     welcome screen titles the window "Hashlight" only because nothing is open (HIG accepts that
     for an empty window; do not show "Hashlight" as a toolbar title otherwise).
4. **Document tab strip.** Keep `TabBar` as an in-content strip (Xcode/Safari pattern) but: remove
   `.background(.ultraThinMaterial)`, use `Color(nsColor: .windowBackgroundColor)` with a bottom
   `Divider`, selection as `.background(.quaternary, in: RoundedRectangle(cornerRadius: 6))`,
   unselected text `.secondary`, no stroke, no accent tint, no scale-on-hover; drop the "+" and
   outline buttons (they move to the toolbar). Keep drag reordering, close button, context menu.
   The strip hides in focus mode as today.
5. **Status bar.** Keep the content (stats, layout menu, zoom menu, encoding) but remove
   `.background(.ultraThinMaterial)` and `.frame(height: 24)`. On macOS 26+ attach it with
   `.safeAreaBar(edge: .bottom) { StatusBarContent() }` on the *detail* view so it gets the
   scroll-edge effect and spans only the document column; below 26 use
   `.safeAreaInset(edge: .bottom)` with `.background(.bar)`.
6. **Find bar.** Delete `SearchBar.swift` once the toolbar search field works (step 3). Keep
   `DocumentManager`'s find state and `MarkdownTextView`'s highlighting unchanged.
7. **Window sizing.** One `minWidth: 700, minHeight: 500` on the root; `.defaultSize(width: 1000,
   height: 700)` on the `Window` scene; delete the manual `setFrame` in `onAppear`. Frame
   persistence stays with SwiftUI/AppKit.

### 2. Settings (S1)

1. **Three panes** in `SettingsView`'s `TabView`:
   - **General** (`gearshape`): `Section { Picker("Appearance") }`, `Section { Picker("Dock icon")
     } footer: { Text(dockIconFootnote) }`.
   - **Preview** (`doc.richtext`): `Section("Theme")` light/dark theme menus; `Section("Fonts")`
     main/fixed menus + `LabeledContent("Sample")` with the two sample strings; `Section("Layout")`
     alignment / text width / page margin segmented pickers with the existing explanatory text as a
     real footer (add "Zoom is in the View menu (⌘+ / ⌘−).").
   - **Tables** (`tablecells`): title "Column categories", one-paragraph explanation, a
     `Table(categories, selection:)` with columns Category / Weight / Match words, a `ControlGroup`
     with + / − beneath (− disabled for `Other` and when nothing is selected), and buttons
     "Edit Category…" (opens the editor as a sheet) and "Restore Defaults" (confirmation dialog).
     Reordering: drag rows on macOS 14+ (`Reorderable`/`onMove`), with ⌥↑/⌥↓ "Move Up/Down" context
     menu items on every version (replaces the chevron buttons).
   - Category editor sheet: `Form(.grouped)` with `TextField("Name")`, `TextField("Weight",
     value:format:)` as one labelled row (fixes the duplicated label), a "Matching words" section
     with the word list, add field, and footer; toolbar `Done` as `.confirmationAction` (trailing),
     `Cancel` as `.cancellationAction`. No `NavigationStack`.
2. **Sizing.** Remove `.frame(width: 480, height: 620)` from the `TabView`. Give each pane its own
   `.frame(width: 520)` and a fixed height that fits its content (General ≈ 230, Preview ≈ 520,
   Tables ≈ 340; measure after building). The window then resizes per pane, as the HIG requires.
   Keep the pane title as the window title (automatic).
3. **Remember the last pane.** Bind `TabView(selection:)` to an `@AppStorage("settingsPane")`.
4. **Remove** the Zoom section, the "Advanced…" section, and `AboutTab`.
5. **Escape** handler: keep `EscapeKeyHandler` (harmless), or drop it for parity with system
   apps — owner's call; default keep.

### 3. About panel

- Add `Hashlight/Credits.rtf` (one line "Based on zMD by Zachary Rossmiller", MIT link) and a
  `CommandGroup(replacing: .appInfo)` button "About Hashlight" that calls
  `NSApplication.shared.orderFrontStandardAboutPanel(options:)` with `.applicationIcon:
  DockIconController.shared.image` (so About shows the chosen Dock icon, per plan 003),
  `.applicationVersion`, and `.credits` from the RTF. The AGENTS.md rule "keep the 'Based on zMD'
  line in Settings → About" moves to "in the About panel"; update the sentence.

### 4. Polish (independent commits)

1. **Focus-mode pill** (`ContentView`): on macOS 26+ `Button(...).buttonStyle(.glass)`; below,
   `.buttonStyle(.bordered)`; remove the manual material, capsule and shadow.
2. **Welcome screen**: `Button("Open File", systemImage: "folder")` with `.buttonStyle(.borderedProminent)`
   and `.controlSize(.large)`; "Recent Files" in title case; recent rows as a `List`-free
   `VStack` of `.plain` buttons with system hover (`.hoverEffect` is unavailable; keep a subtle
   `.quaternary` background on hover only). Keep the entrance animation.
3. **Command palette**: replace the black dimmer with no dimmer (the card already separates from
   content) and the card material with `.regularMaterial`; on macOS 26+ use
   `.glassEffect(.regular, in: .rect(cornerRadius: 12))` on the card only. Category badges become
   monochrome `.secondary` capsules; keep the text. Quick Open: same treatment.
4. **Hover/press feedback**: remove `PressableButtonStyle` from tab, outline, file rows and welcome
   button (system controls provide it); keep it nowhere unless a control has no system style.
5. **Help sheet**: `.navigationTitle("Hashlight Help")` + `.toolbar { Button("Done") }` with
   `.confirmationAction`; drop the custom header row.
6. **Menu icons**: give Open…, Open Folder…, Export, Print… `Label`s with SF Symbols. macOS 27
   shows them minimal by default; opt in only for Open… with `labelStyle(.titleAndIcon)`.

### 5. Docs and tests

- README (features: sidebar, toolbar, Settings panes, About), Help HTML ("outline button in the
  tab bar" → toolbar/sidebar; Settings paths), `CLAUDE.md` component list (new `NavigatorSidebar`,
  removed `SearchBar`), `AGENTS.md` (About line location; Settings invariants: three panes, last
  pane restored, no fixed window frame), `HANDOVER.md` (Settings-height known issue is resolved).
- Tests: `SettingsManager` migration of `showOutline` → navigator mode/visibility; the Settings
  pane persistence key; table-category reorder/remove/restore-defaults logic (pure functions on
  `MarkdownTableColumnConfiguration`). UI itself remains hands-on verified.

## Compatibility notes

- `NavigationSplitView`, `.searchable`, `.listStyle(.sidebar)`, `Table`, `ControlGroup`,
  `.navigationDocument`: macOS 13. `inspector`, `Reorderable`: macOS 14. `safeAreaBar`,
  `ToolbarSpacer`, `.glass`/`.glassProminent`, `glassEffect`, `backgroundExtensionEffect`:
  macOS 26. Gate the last group with `if #available(macOS 26, *)`; the fallbacks are
  `safeAreaInset` + `.background(.bar)`, default toolbar grouping, `.bordered`, `.regularMaterial`.
- CI builds with Xcode 26.6 (macOS 26.5 SDK); nothing here needs the macOS 27 SDK. Concentricity
  and the glass bounce are automatic for system controls on macOS 27.
- The `NSTextView` preview stays untouched: it is content, and content must not get glass.
- `MarkdownTextView`'s `scrollToHeadingId` binding keeps working with the `List` selection; make
  sure selecting the same heading twice still scrolls (reset the binding after use, as today).

## Verification (planned)

- `./scripts/xcodebuild-hashlight.sh -configuration Debug test`, count from the result bundle;
  unsigned Release compile; `git diff --check`; `plutil -lint` the project.
- Hands-on on macOS 26.7.1 (screenshots to `artifacts/screens/plan004-*.png`): light and dark;
  System Settings → Appearance → Liquid Glass "Clear" and "Tinted"; Reduce Transparency and
  Increase Contrast on; sidebar collapsed/expanded and resized; Files ↔ Outline switch; find via
  toolbar (⌘F, Return, ⌘G, Escape); status bar scroll-edge effect; focus mode; each Settings pane
  sizes the window and the last pane is restored; Tables +/−, reorder, edit, restore defaults;
  About panel shows the chosen Dock icon; welcome screen; command palette; Quick Open; Help.
- Unregister development registrations afterwards (`manage-dev-registrations.sh unregister`).

## Out of scope

- Amber accent colour from `design/BRIEF.md` §3 (separate owner decision; the HIG asks to be
  judicious with colour in controls, so it would apply to sidebar icons at most).
- Any change to Markdown rendering, Quick Look, export, or the parser.
- Raising the deployment target.

## What was done

Implemented 2026-09-30/10-01 in the order of the work plan, building after each step (Xcode 27, macOS
26.7.1). No commits; the working tree is left for the owner's review.

Files:

- **Added:** `Hashlight/NavigatorSidebar.swift` (sidebar navigator: Files / Outline picker and
  empty states), `Hashlight/ViewerToolbar.swift` (window toolbar, `ExportMenuItems` and
  `PrintMenuItem` shared with the menu bar, `FindField` focus helper), `Hashlight/Credits.rtf`
  (About credits, in the app's Resources phase), `HashlightTests/SettingsModelTests.swift`.
- **Deleted:** `Hashlight/SearchBar.swift`, `Hashlight/PressableButtonStyle.swift`,
  `Hashlight/RecentFileButtonStyle.swift` (no users left).
- **Changed:** `HashlightApp.swift`, `ContentView.swift`, `NormalContentView.swift` (now the detail
  column), `DocumentViewModeContent.swift`, `DocumentManager.swift`, `FolderManager.swift`,
  `FolderSidebarView.swift`, `OutlineView.swift`, `TabBar.swift`, `StatusBarView.swift`,
  `SettingsManager.swift`, `SettingsView.swift`, `SharedConstants.swift`, `WelcomeView.swift`,
  `CommandPaletteView.swift`, `QuickOpenView.swift`, `HelpView.swift`, `HelpHTML.swift`,
  `Hashlight.xcodeproj/project.pbxproj` (files added/removed by hand), `HashlightTests/InlineMarkdownTests.swift`
  (dropped the removed `isShowingFolderSidebar`), and the docs: `README.md`, `CLAUDE.md`,
  `AGENTS.md`, `HANDOVER.md`, `CONTRIBUTING.md` (version is under Hashlight → About Hashlight).

By work-plan step:

1. **Main window (A1).** `ContentView` is a `NavigationSplitView(columnVisibility:)`; the sidebar is
   `NavigatorSidebar` (segmented Files / Outline, `min 200, ideal 240`), the detail is the welcome
   screen or `NormalContentView`. `SettingsManager` persists `navigatorMode` and `navigatorVisible`
   and migrates `showOutline` once (`loadNavigatorState(from:)`); Open Folder switches to Files and
   shows the sidebar. `FolderManager.isShowingFolderSidebar` became the computed `isFolderOpen`.
   Outline and Files are `List(selection:)` with `.listStyle(.sidebar)`: indented heading rows
   (level 1 medium), and a `DisclosureGroup` tree of `Label` rows under a section header named after
   the folder. The toolbar has Open… (`.navigation`), Focus Mode and an Export menu (PDF, HTML,
   HTML without styles, Word .docx/.rtf, Print), a `ToolbarSpacer(.fixed)` on macOS 26, a match
   counter while searching, and `.searchable(placement: .toolbar, prompt: "Find in document")`
   with `onSubmit(of: .search)` → next match. View menu: Show/Hide Sidebar (⌃⌘S), Navigator → Files
   (⌘⌥1) / Outline (⌘⌥2); no collisions. `navigationTitle` / `navigationDocument` replace the manual
   title/`representedURL` mirroring; `WindowCloseDelegate` keeps only close behaviour. The tab strip
   is a plain content-layer strip (`windowBackgroundColor`, bottom divider, `.quaternary` selection,
   `.secondary` unselected text, no "+"/outline buttons). The status bar lost its material and fixed
   height; on macOS 26 it is a bottom-aligned `NSSplitViewItemAccessoryViewController` on the detail
   split view item (`StatusBarAccessory.swift`; AppKit insets the preview and draws the scroll edge
   effect under the bar; a plain inset is the fallback if the anchor cannot find the item), before
   that `safeAreaInset` + `.background(.bar)`. `SearchBar.swift` is gone. The window has one
   minimum (700 × 500) and `.defaultSize(width: 1000, height: 700)`; the manual `setFrame` is gone.
2. **Settings (S1).** `TabView(selection:)` bound to `@AppStorage("settingsPane")` with General
   (Appearance; Dock icon with a real footer), Preview (Theme, Fonts with a `LabeledContent`
   sample, Layout with the explanation and the zoom hint as a footer) and Tables (explanation,
   `Table` with Category / Weight / Match words, `ControlGroup` +/−, Edit Category…, Restore
   Defaults with a confirmation dialog, row context menu with Edit, Move Up ⌥↑, Move Down ⌥↓,
   Remove, double-click to edit, Delete key to remove, drag to reorder). The category editor is a
   grouped `Form` sheet on a draft copy: Name, one "Weight" row, Matching Words with an add field
   and footer, Cancel (`.cancellationAction`) and Done (`.confirmationAction`); no
   `NavigationStack`. Each pane sets its own size (520 wide; heights measured: General 200, Preview
   540, Tables 360), so the window resizes per pane. The Zoom and Advanced sections and `AboutTab`
   are gone; `EscapeKeyHandler` stays (the stated default). The editing logic is pure functions on
   `MarkdownTableColumnConfiguration` (`savingCategory`, `removingCategory`, `movingCategory`,
   `movingCategories(withIDs:to:)`, `isDefault`, `newCategory()`), Foundation-only in
   `SharedConstants.swift`.
3. **About panel.** `CommandGroup(replacing: .appInfo)` → `AboutPanel.show()` calls
   `orderFrontStandardAboutPanel(options:)` with `DockIconController.shared.image`, the short
   version, and `Credits.rtf` ("Based on zMD by Zachary Rossmiller", MIT License link).
4. **Polish.** Focus-mode exit button: `.buttonStyle(.glass)` on macOS 26, `.bordered` before.
   Welcome: `.borderedProminent` + `.controlSize(.large)` "Open File", "Recent Files" in title case,
   plain recent-file rows with a `.quaternary` hover background, entrance animation kept. Command
   palette and Quick Open: no dimmer (a clear click-outside layer instead), `glassEffect(.regular,
   in: .rect(cornerRadius: 12))` on macOS 26 and `.regularMaterial` + shadow before, monochrome
   `.secondary` capsule badges; Quick Open's NSView no longer paints `windowBackgroundColor`.
   `PressableButtonStyle` removed everywhere (rows use `.plain`). Help: `.navigationTitle` + a
   `.confirmationAction` Done; the custom header row is gone. Menu icons: Open… (`folder`,
   `.titleAndIcon`), Open Folder… (`text.below.folder`), Export (`square.and.arrow.up`), Print…
   (`printer`).
5. **Docs and tests** as listed above; tests below.

## Verification

- `./scripts/xcodebuild-hashlight.sh -configuration Debug test`: **121 tests, 121 passed, 0 failed,
  0 skipped** (from the result bundle; 104 before, 17 new in `SettingsModelTests.swift`:
  `NavigatorSettingsTests` 7 (the `showOutline` migration cases, saved values winning, persistence,
  and the autosave repair), `SettingsPaneTests` 3 (the `settingsPane` key and values, restoring the
  last pane through `AppStorage`, unknown values falling back to General, per-pane heights),
  `TableCategoryEditingTests` 5 (move up/down, drag insertion index, remove rules including Other's
  1.0 fallback, add/replace/reject invalid weight, restore defaults), `AboutPanelTests` 2 (credits
  keep the zMD line; the panel uses the Dock icon image and the bundle version)). Every Debug build
  and the test build had no compiler warnings (the only `warning:` lines are the pre-existing
  `appintentsmetadataprocessor` notes).
- Unsigned Release compile (`CODE_SIGNING_ALLOWED=NO …`): **BUILD SUCCEEDED**, no warnings;
  `Credits.rtf` is in `Hashlight.app/Contents/Resources`.
- `git diff --check`, `plutil -lint Hashlight.xcodeproj/project.pbxproj`, `ruby -c
  scripts/update-base16-themes.rb`: clean.
- Hands-on on macOS 26.7.1 with the Debug build and `fixtures/rendering-check.md`; the Files
  navigator used `fixtures/` (seeded with the throwaway-XCTest trick from `HANDOVER.md`, then
  removed). Screenshots, all scoped to Hashlight's windows, in `artifacts/screens/`:
  - `plan004-01-main-outline-light.png`: A1 layout after migrating `showOutline = true`: Outline
    navigator, toolbar (sidebar toggle, Open, title, Focus, Export, Find), tab strip, status bar.
  - `plan004-02-statusbar-scrolled-light.png`: the first version (`safeAreaBar`): the preview ended
    above the bar. Superseded by `plan004-34` (2026-10-01).
  - `plan004-02-statusbar-scroll-edge-light.png`: the rejected `ignoresSafeArea` experiment: text
    ran under the bar with no edge effect (see Notes).
  - `plan004-03-outline-selects-heading-light.png`: selecting "Code" scrolls the preview; system
    sidebar selection. Re-clicking the selected heading after scrolling away scrolled again
    (scroll position 0 → 0.74, checked through Accessibility).
  - `plan004-04-files-no-folder-light.png`: Files mode with no folder: "No Folder Open" and a
    bordered "Open Folder…".
  - `plan004-05-files-navigator-light.png`: Files tree; double-click expands `folder-search`;
    selecting `alpha.md` opened it in a new tab and retitled the window. Switching tabs moves the
    selection; ⌘⌥2 / ⌘⌥1 switch modes and keep expanded folders.
  - `plan004-06-find-toolbar-light.png`, `plan004-07-find-next-light.png`,
    `plan004-08-find-escape-cleared-light.png`: ⌘F focuses the toolbar field, "needle" shows 1/3
    with highlights, Return → 2/3, ⌘G advances from the field and from the preview (3/3 → 1/3 →
    2/3), ⌘⇧G goes back, Escape clears the field, highlights and counter.
  - `plan004-09-sidebar-hidden-light.png`, `plan004-10-sidebar-resized-light.png`: ⌃⌘S hides the
    sidebar (menu title flips, `navigatorVisible` saved), the toolbar button shows it again, and
    dragging its edge resized it 248 → 330 pt (autosaved).
  - `plan004-11-focus-mode-light.png`, `plan004-12-focus-mode-exit-button-light.png`: the first
    version of focus mode (title bar kept). Superseded by `plan004-35`/`36` (2026-10-01).
  - `plan004-13-settings-general-light.png` (520 × 288 window), `plan004-14-settings-preview-light.png`
    (520 × 628), `plan004-15-settings-tables-light.png` (520 × 448): each pane resizes the window.
  - `plan004-16-settings-tables-new-category-sheet.png`, `plan004-17-settings-tables-editor-filled.png`,
    `plan004-18-settings-tables-added-and-moved.png`, `plan004-19-settings-tables-dragged.png`,
    `plan004-20-settings-tables-edit-builtin.png`, `plan004-21-settings-tables-restore-confirm.png`,
    `plan004-22-settings-tables-restored.png`: + opens the editor; Done saved "vendor · 2 · 1";
    ⌥↑ twice and a row drag reordered it; − removed it; − is disabled for built-ins; Edit changed
    Compact's weight 0.65 → 0.8 (Done commits a weight still being typed); Cancel discards a draft;
    Restore Defaults asks, then restores the built-in set. Return in the word field adds the word.
  - Closing Settings with Escape and reopening it restored the Tables pane (`settingsPane = tables`).
  - `plan004-23-settings-general-dark.png`, `plan004-24-settings-preview-dark.png`,
    `plan004-25-main-files-dark.png`, `plan004-26-main-outline-dark.png`: Dark appearance applied
    live to Settings and the main window.
  - `plan004-27-about-panel-ember-dark.png`, `plan004-32-about-panel-frost-light.png`: the About
    panel shows the icon chosen in Settings → General → Dock icon (Ember, then Frost), version
    1.0.0 (1), and the zMD credit with links; its text adapts to Dark.
  - `plan004-28-welcome-dark.png`: welcome screen in the detail column (window titled "Hashlight",
    Ember icon, prominent Open File, "Recent Files").
  - `plan004-29-command-palette-dark.png`, `plan004-30-quick-open-dark.png`: glass panels without
    a dimmer; monochrome category capsules; new sidebar commands in the palette.
  - `plan004-31-help-sheet-dark.png`: Help sheet with a trailing Done; Escape closes it.
  - `plan004-33-settings-tables-no-stripes-light.png` (review fix, 2026-10-01): the Tables pane
    after `alternatingRowBackgrounds(.disabled)` (macOS 14+, gated). Screenshots 15 and 22 had
    shown the stripes running past the last row with the bottom one clipped by the buttons.
  - `plan004-34-statusbar-accessory-light.png`, `plan004-38-statusbar-accessory-dark.png`
    (2026-10-01): the status bar as a split-item accessory; the document scrolls under it and the
    last line fades into the bar through AppKit's scroll edge effect. Also checked: the bar follows a
    tab switch, survives close-all → welcome → reopen, and appears once.
  - `plan004-35-focus-mode-chrome-light.png`, `plan004-36-focus-mode-exit-hover-light.png`,
    `plan004-39-focus-mode-chrome-dark.png` (2026-10-01): focus mode with only the window controls
    left of the title bar; the document runs under the transparent bar; the glass "Exit Focus
    Mode" button on hover. `plan004-37-after-focus-mode-light.png`,
    `plan004-40-after-focus-mode-dark.png`: title, proxy icon, toolbar, tabs and status bar are back
    and the window frame is unchanged (1000 × 700 before, during and after, from `list-windows`).
  - Also checked without a screenshot: sidebar section-header menu (Reveal Folder in Finder, Close
    Folder) and file-row menu (Open, Reveal in Finder, …); quitting, or closing the window, in focus
    mode and relaunching keeps the window at 1000 pt with the sidebar shown.
- Afterwards: the app was quit, `manage-dev-registrations.sh unregister` run and `status` clean, and
  the Debug defaults domains deleted.

## Notes and left over

Deviations from the plan, each with the reason:

- **Status bar scroll-edge effect (1.5) — resolved 2026-10-01.** SwiftUI's `safeAreaBar` gives
  the effect only to SwiftUI scroll views, and the preview is an AppKit `NSScrollView`; letting it
  run under the bar (`ignoresSafeArea`) produced overlap with no effect
  (`plan004-02-statusbar-scroll-edge-light.png`). WWDC25-310 names the AppKit route: "Split item
  accessories, along with titlebar accessories, are the best way to incorporate floating content
  into the scroll edge effect. They influence the size and shape of the effect, and they inset the
  content safe area." The status bar is now an `NSSplitViewItemAccessoryViewController` added with
  `addBottomAlignedAccessoryViewController` to the detail `NSSplitViewItem` of the `NSSplitView`
  that `NavigationSplitView` creates (`StatusBarAccessory.swift`; the item is found by walking up
  from a zero-size `NSViewRepresentable` to the split view and asking its `NSSplitViewController`).
  AppKit insets the scroll view (`safeAreaInsets.bottom` = bar height) and draws the effect. The
  view walk depends on SwiftUI's private hierarchy, so the anchor reports whether it attached and
  the plain `.bar` inset is the fallback. `preferredScrollEdgeEffectStyle` (macOS 26.1) is left at
  automatic.
- **`Reorderable` (2.1, Compatibility notes).** It is a macOS 27 SDK API (`reorderable()`,
  `reorderContainer`), not macOS 14, so it cannot build on CI's Xcode 26.6. Drag reordering uses
  `TableRow.itemProvider` + `ForEach.dropDestination(for:)` (macOS 12/13), so it works on every
  supported version, not only 14+. ⌥↑/⌥↓ are in the row menu and also work as keyboard shortcuts.
- **"− disabled for Other" (2.1).** The model deliberately lets Other be removed (AGENTS.md: "if
  removed, the fallback is 1.0") and keeps the four other built-ins. − follows the model: disabled
  with no selection or for those four built-ins; Other stays removable, and Restore Defaults brings
  it back.
- **`if #available` in the toolbar (1.3).** `ToolbarContentBuilder.buildLimitedAvailability` needs
  macOS 14.5, so the macOS 26 grouping (`ToolbarSpacer`, `sharedBackgroundVisibility(.hidden)` on
  the counter) is chosen at the view level in `ViewerToolbar`.
- **⌘F (1.3).** `searchable(text:isPresented:)` needs macOS 14, so ⌘F focuses the field through
  AppKit (`NSSearchToolbarItem.beginSearchInteraction()`, `FindField`) on every version. Typing
  starts a find and clearing the field (Escape, its clear button) ends it; `DocumentManager`'s find
  state is unchanged.
- **Focus mode (1.3/1.4) — resolved 2026-10-01.** `toolbar(.hidden, for: .windowToolbar)` on
  macOS 26 removes the window controls with the toolbar, and `NSToolbar.isVisible = false` keeps
  them but shrinks the window by the toolbar height (552 → 532 pt, measured). Focus mode therefore
  keeps the toolbar object and instead makes the title bar transparent over full-size content
  (`FocusModeWindowChrome` in `HashlightApp.swift`: `titlebarAppearsTransparent`,
  `.fullSizeContentView`; `WindowCloseDelegate` applies it from `$isFocusModeActive` and restores the
  saved values on exit). The title and proxy icon are SwiftUI's, so they are cleared with
  `navigationTitle("")` and by dropping `navigationDocument` (`DocumentProxy`); setting
  `NSWindow.titleVisibility` was reverted by SwiftUI on the next update. The toolbar items and
  search field are removed as before, the sidebar toggle on macOS 14+ (`toolbar(removing:)`, inert
  on 13). The preview ignores the top safe area so the document runs under the bar, and AppKit
  applies the scroll edge effect there. The window frame is unchanged entering and leaving. The
  hover area for the exit button is a 56 pt band at the top (the old one covered the whole
  document).
- **Window widening (found while testing).** AppKit widens the window by the sidebar's width when
  the sidebar appears without animation, and it restored a sidebar that focus mode had collapsed
  that way at the next launch (1000 → 1330 pt). Fixes: every programmatic sidebar/focus change uses
  `Motion.sidebar` (never nil; near-instant under Reduce Motion; replaces the unused
  `Motion.morph`), `SidebarAutosave` corrects the autosaved "collapsed" flag on window close and
  app quit when the navigator should be visible, and focus mode ends when its window closes. A first
  attempt that delayed Quit was dropped because Quit must stay immediate
  (`CloseWithoutPromptTests.testQuitIsNeverHeldUp`). A crash while in focus mode can still widen the
  next window once.
- **Keyboard focus (found while testing).** The toolbar's sidebar toggle became the first key view,
  so Space toggled the sidebar instead of scrolling. The preview now takes focus when it appears,
  unless a text field or list has it (`PreviewFocus`).
- **Files navigator root row (1.2).** There was no root row; the folder name is the list's section
  header, whose menu has Reveal Folder in Finder and Close Folder (also in the file-row and
  empty-area menus). The old file tree had no context menu; rows now offer Open and Reveal in
  Finder. Expanded folders are kept in `FolderManager` for the session.
- **Migration (1.1).** Besides `showOutline == true` → visible Outline, an open folder with the
  outline hidden migrates to visible Files, because the old folder pane always showed.
- **Welcome (4.2).** `Button(_:systemImage:)` needs macOS 14, so it is `Button { } label: { Label }`.
  The ⌘O key-cap hint was kept (not in the work plan).
- **Help (4.5).** A macOS sheet does not display `navigationTitle`; the page's own "Hashlight Help"
  heading is the visible title. Escape still closes it (hidden cancel button). The sheet is
  760 × 520 (was 800 × 600) so it fits the default window.
- **Sizes (2.2).** Measured pane heights are 200 / 540 / 360 (estimates were 230 / 520 / 340). The
  category editor sheet (440 × 380) overhangs the 448 pt Tables window slightly, which macOS allows.
- **Texts.** The Layout footer says "(⌘= / ⌘− / ⌘0)", the key equivalents the View menu shows,
  instead of "(⌘+ / ⌘−)". The Layout pickers keep their "Content alignment" / "Content width"
  labels, matching the status-bar menu.
- **Extras.** The command palette gained Toggle Sidebar, Show Files, and Show Outline; File → Print
  and File → Export share their items with the toolbar's Export menu; the Export menu has an
  explicit "Export" accessibility label (the symbol read as "Share").

Left over / needs the owner's eyes:

- System Settings → Appearance → Liquid Glass **Clear** and **Tinted**, **Reduce Transparency**, and
  **Increase Contrast** were not checked: they change system-wide settings on the owner's Mac.
- The macOS 13–15 fallbacks (`safeAreaInset` + `.bar`, `.bordered`, `.regularMaterial`, default
  toolbar grouping, the inert sidebar toggle in focus mode on 13) compile but were not run.
- Hosted CI (Xcode 26.6) has not built this change yet; nothing here needs the macOS 27 SDK.
- **Open… placement:** the plan's `.navigation` puts it before the title; the A1 mock-up showed it
  with the trailing items. Owner's choice.
- The Dock-icon, KaTeX-dark and zMD-proxy-icon issues in `HANDOVER.md` are unchanged.
