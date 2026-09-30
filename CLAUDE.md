# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Hashlight** is a lightweight, read-only macOS Markdown viewer built with SwiftUI, with a clean, Typora-inspired interface, tabs, an outline sidebar, folder search, and export. It never writes to a Markdown file: there is no source editor, split view, saving, or find & replace, and closing never prompts. It started from zMD Viewer, the read-only edition of zMD; see `AGENTS.md` for its identity, origin, and rules.

**Key Features:**
- Multi-tab document management
- Real-time markdown rendering with Typora-style formatting
- Hierarchical outline sidebar, Quick Open, folder search, and find in the rendered text
- Live reload when another app changes an open file (keeps the scroll position)
- Export to PDF, HTML, RTF, and DOCX, and native print
- Native macOS integration with keyboard shortcuts

## Build Commands

### Development
```bash
# Open in Xcode
open Hashlight.xcodeproj

# Build and run (⌘R in Xcode)
# Or via command line:
./scripts/xcodebuild-hashlight.sh -configuration Debug build

# Release build
./scripts/xcodebuild-hashlight.sh -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' build

# Tests
./scripts/xcodebuild-hashlight.sh -configuration Debug test

# Build output location
# build/Xcode/Debug/Hashlight.app or build/Xcode/Release/Hashlight.app
```

### Distribution
```bash
# Create an ad-hoc signed DMG (build/Hashlight.dmg)
./scripts/build-dmg.sh
```

**Note:** First launch on unsigned builds requires right-click → Open to bypass macOS Gatekeeper.

## Architecture

### State Management Pattern

The app uses SwiftUI's `@StateObject` / `@EnvironmentObject` pattern for centralized state:

- **DocumentManager** (`DocumentManager.swift`): Central source of truth for all document state
  - Manages array of `MarkdownDocument` objects (each with UUID, URL, content, detected encoding)
  - Tracks `selectedDocumentId` for active tab
  - Handles file loading, reloading, tab switching, and document lifecycle. Documents are read-only: nothing writes them back, so closing a tab or the window and quitting never prompt.
  - Watches each open file (`FileWatcher`): an external change reloads the tab silently; a deleted file asks before its tab closes
  - Holds the find-bar state; the preview computes the matches in its rendered text and reports their count
  - Injected into view hierarchy via `.environmentObject()` at app root
- **SettingsManager** (`SettingsManager.swift`): Persists application appearance, separate light/dark preview themes, preview fonts, layout, zoom, and the versioned Markdown table-column configuration. Preview themes are bundled Base16 palettes (`PreviewTheme.swift`); font menus are derived from installed proportional and monospaced families (`PreviewFont.swift`).

### View Hierarchy

```
HashlightApp (App entry point)
└── ContentView (Main container)
    ├── TabBar (Tab interface + controls)
    │   └── TabItem[] (Individual tabs with context menus)
    ├── SearchBar (Find in the rendered text - conditional)
    ├── NormalContentView / FocusModeContentView
    │   ├── FolderSidebarView (conditional)
    │   ├── OutlineView (Sidebar - conditional)
    │   └── DocumentViewModeContent
    │       └── MarkdownTextView (Rendered content via NSTextView)
    └── StatusBarView
```

### Markdown Rendering Architecture

**Two-layer rendering, one shared inline tokenizer:**
- `MarkdownParser.swift`: Single source of truth for *block*-level parsing (headings, paragraphs, lists, code blocks, tables, blockquotes, images, frontmatter).
- `InlineMarkdown.swift`: Shared *inline* tokenizer (bold/italic/code/strikethrough/links/images/math) consumed by all four rendering backends — `MarkdownParser` (HTML/PDF/RTF export), `MarkdownTextView` (preview), `ExportManager` (DOCX export), and `PrintManager` (print). This replaced four independently drifting inline-formatting implementations with a single one.
- `MarkdownTextView.swift` (NSViewRepresentable): Consumes `MarkdownParser`'s block-level `[Element]`s (and `InlineMarkdown` for inline formatting) to build NSAttributedString for NSTextView rendering. Handles headings, paragraphs, lists, code blocks (with syntax highlighting via SyntaxHighlighter), tables, blockquotes, images, frontmatter.
- `PreviewTheme.swift`: Loads the bundled, pinned Tinted Theming Base16 catalog and maps each palette to native preview and syntax-highlight roles. Light and dark selections are stored independently.
- `PreviewFont.swift`: Enumerates installed font families and keeps proportional body fonts separate from monospaced code fonts.
- `SharedConstants.swift`: Defines the versioned table-column category model and deterministic layout shared by the app and Quick Look. Category order controls matching priority; header matching uses whole words, and each category contributes a width weight.

**Note:** The only renderer is `MarkdownTextView.swift`; there is no source editor.

**Reloads:** `MarkdownTextView` treats a content change for the document already on screen as a reload: the rebuild is debounced 150ms and keeps the reader's scroll position. Switching documents, zoom, style changes and diagram renders rebuild immediately.

**Task checkboxes** render as read-only glyphs; there is no click handler and nothing in `MarkdownParser` rewrites a document.

### Export System

**ExportManager** (`ExportManager.swift`) handles PDF, HTML, RTF, and DOCX exports:

1. **PDF Export**: Markdown → HTML (via MarkdownParser) → NSAttributedString → CGContext rendering with pagination
2. **HTML Export**: Markdown → HTML (via MarkdownParser) with optional CSS styling
3. **RTF Export**: Markdown → HTML → NSAttributedString → RTF data
4. **DOCX Export**: Custom XML generation with inline formatting, tables, lists, and hyperlinks

All exports use `NSSavePanel` and run on main thread. HTML conversion routes through `MarkdownParser.shared.toHTML()` for consistent, safe output.

### Quick Look Extension

`HashlightQuickLook/` is a separate app-extension target embedded in `Hashlight.app/Contents/PlugIns`. Release uses bundle id `io.github.ib0ndar.hashlight.QuickLook`; Debug uses the isolated `io.github.ib0ndar.hashlight.debug.QuickLook`. It previews `net.daringfireball.markdown` files in Finder (Space) as HTML. With another Markdown Quick Look extension installed (zMD's, for example), Finder uses one of them; the user picks it in System Settings → General → Login Items & Extensions → Quick Look.

- `PreviewProvider.swift`: `QLPreviewProvider` principal class (data-based preview). Reads ≤2 MB, decodes, calls `MarkdownParser.shared.toHTML`, post-processes, returns `QLPreviewReply` HTML.
- `QuickLookHTML.swift`: pure Foundation helpers — bounded read, decoding (UTF-8 → BOM UTF-16 → CP1252), and `makeOfflineSafe` (strips `<script>`/`<link>`, keeps display-math source visible, injects CSP + dark-mode CSS). Also compiled into `HashlightTests` (`QuickLookHTMLTests.swift`).
- Shared with the app by target membership (not copies): `MarkdownParser.swift`, `InlineMarkdown.swift`, and `SharedConstants.swift` (including `CDN` and table-column layout). Anything these files reference must stay Foundation-only and live in a file that is a member of both targets, or the extension stops compiling.
- Table-column settings are mirrored to `io.github.ib0ndar.hashlight.table-column-layout` in Release and `io.github.ib0ndar.hashlight.debug.table-column-layout` in Debug. The corresponding extension entitlement has a read-only temporary exception so Finder previews use the matching app's table layout without development settings changing the installed release.
- The extension **is sandboxed** (`HashlightQuickLook.entitlements`; required for app extensions) even though the app is not. No network, and it can only read the previewed file — so Mermaid/KaTeX render as source text and relative images do not load.
- `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` are set on the extension target too — keep them equal to the app's (1.0.0).
- Xcode unconditionally registers built macOS apps with Launch Services, which also exposes the embedded extension to PlugInKit. Local CLI work must use `scripts/xcodebuild-hashlight.sh`; inspect with `scripts/manage-dev-registrations.sh status`, and unregister non-installed development copies with `scripts/manage-dev-registrations.sh unregister`. For intentional Finder testing, build once with `HASHLIGHT_KEEP_REGISTRATION=1` and unregister immediately afterwards. The manager never deletes source or build files.

### Menu Commands & Shortcuts

Defined in `HashlightApp.swift` using SwiftUI's `.commands` modifier:

- File menu: Open (⌘O), Quick Open (⌘⇧O), Search in Folder (⌃⇧F), Open Folder (⌘⌥O), Close Folder, Open Recent, Open File Location, Print (⌘P)
- Export submenu: PDF, HTML (with/without styles), Word (.docx), Word (.rtf)
- Edit menu: Find (⌘F), Find Next (⌘G), Find Previous (⌘⇧G)
- View menu: Focus Mode (⌘⇧F), Command Palette (⌘K), Zoom In/Out/Reset (⌘= / ⌘- / ⌘0), Refresh (⌘R)
- Tab menu: Close (⌘W), Refresh Tab, Next (⌃Tab), Previous (⌃⇧Tab)
- Right-click tab menu: Refresh, Close Tab, Close Other Tabs, Reveal in Finder
- The `saveItem` group is replaced by an empty group so ⌘W stays Close Tab. There is no Format menu, Save, New File, view-mode switching, or Check for Updates.

## File Organization

```
Hashlight/
├── HashlightApp.swift     # App entry point, menu commands, keyboard shortcuts, window delegate
├── ContentView.swift      # Main view container and layout
├── DocumentManager.swift    # Document state, file watching, find state (@ObservableObject)
├── DocumentViewModeContent.swift # The preview for one document
├── MarkdownTextView.swift   # NSTextView-based markdown renderer
├── PreviewTheme.swift       # Bundled Base16 preview-theme catalog and palette mapping
├── PreviewFont.swift        # Installed proportional/monospaced preview-font catalogs
├── Resources/               # Pinned Base16 theme data and upstream license
├── SharedConstants.swift    # App/Quick Look constants and table-column layout model
├── MarkdownParser.swift     # Shared markdown parser for exports
├── TabBar.swift             # Tab bar UI and tab items
├── OutlineView.swift        # Hierarchical outline sidebar (cached headings)
├── ExportManager.swift      # PDF/HTML/RTF/DOCX export functionality
├── SyntaxHighlighter.swift  # Code block syntax highlighting
├── AlertManager.swift       # Centralized alert/error management
├── FileWatcher.swift        # File change monitoring (drives silent reloads)
├── FolderManager.swift      # Folder sidebar tree and folder-wide content search
├── QuickOpenView.swift      # Quick open dialog
├── Assets.xcassets/         # App icon and resources
└── Hashlight.entitlements   # Sandbox disabled; see Sandboxing Considerations below
```

## Development Notes

### Adding New Markdown Elements

To add support for new markdown syntax:

1. Add rendering logic in `MarkdownTextView.swift`'s `buildAttributedString()` method
2. Add a new case to `MarkdownParser.Element` enum in `MarkdownParser.swift`
3. Add parsing logic in `MarkdownParser.parse()` and HTML conversion in `elementToHTML()`
4. This ensures rendering and export stay in sync

### Working with Document State

Always access/modify documents through `DocumentManager` methods, never manipulate `openDocuments` array directly:
- Use `loadDocument(from:)` to open files
- Use `closeDocument(_:)` to close tabs
- Use `selectedDocumentId` binding for active document

### Sandboxing Considerations

The app currently ships **un-sandboxed** (direct `.dmg` distribution, not Mac App Store). See `Hashlight.entitlements` — `com.apple.security.app-sandbox` is `false`. The `com.apple.security.files.user-selected.read-write` and `com.apple.security.network.client` keys are present but inert outside the sandbox.

- There is no updater; nothing writes into `/Applications`.
- The security-scoped bookmark calls (`startAccessingSecurityScopedResource`, `.withSecurityScope` bookmark data) are still present in DocumentManager/FolderManager but are no-ops at runtime in the un-sandboxed configuration. They stay in place so a future sandbox re-enable is a smaller change.
- If you ever set `app-sandbox=true`, re-test: Open Recent, folder sidebar restore, relative images, drag-drop of .md files onto the window, file watching, and every export's save panel.

### Known Limitations

- Quick Look previews (sandboxed, no network): Mermaid/KaTeX show as source text; relative and remote images do not load
- Images/diagrams are sized once at build time, so one wider than a very narrow pane still overflows (text reflows; attachments don't)
- Text selection implementation is incomplete (partially works)
- Table rendering may overflow on very wide tables
- Markdown parser is simplified (doesn't support all CommonMark features)
- Remote images load asynchronously but don't trigger re-render when cached
