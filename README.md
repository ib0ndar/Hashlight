<p align="center">
  <img src="img/zMarkdown.png" alt="zMD Viewer" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/zMD_Viewer-Native_Markdown_Viewer-c8a96e?style=for-the-badge&labelColor=080a0f" alt="zMD Viewer" />
</p>

<p align="center">
  <strong>Native macOS Markdown viewer</strong><br/>
  A lightweight, Typora-inspired reader with tabs, an outline sidebar, folder search, and full export support. It never changes your files.<br/><br/>
  <a href="https://github.com/ib0ndar/zMD/tree/viewer">Source</a> · <a href="https://github.com/ib0ndar/zMD/issues">Issues</a> · <a href="https://github.com/ib0ndar/zMD/blob/viewer/CLAUDE.md">Developer Guide</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-c8a96e?style=flat-square" alt="Version 1.0.0" />
  <img src="https://img.shields.io/badge/platform-macOS_13%2B-4a9eff?style=flat-square" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/stack-SwiftUI%20%7C%20AppKit%20%7C%20NSTextView-34d399?style=flat-square" alt="Stack" />
</p>

---

## Origin

zMD Viewer is the read-only edition of [zMD](https://github.com/ib0ndar/zMD), a native macOS
Markdown editor and viewer. It keeps zMD's renderer, navigation and exports, and removes
everything that edits or writes a document: the source editor, split view, saving, find &
replace, and the prompts that came with unsaved changes. Open a file and it renders instantly;
when another app changes the file, the tab follows along.

It's a native SwiftUI app built around Apple's `NSTextView` rather than a web view — no
Electron, no Tauri. It lives on the `viewer` branch of the zMD repository, has its own app and
bundle identity, and installs next to zMD.

---

## How It Works

```
Open .md --> Rendered preview (reloads when the file changes) --> Export PDF/HTML/Word
```

1. **Open a file**: `⌘O`, drag and drop, double-click in Finder, Open Recent, or a folder in the sidebar
2. **Read**: headings, code blocks with syntax highlighting, tables, Mermaid diagrams, LaTeX math, clickable links
3. **Find your way**: outline, find in document, Quick Open, search across a folder, command palette
4. **Export anywhere**: PDF (paginated), HTML (with or without styles), Word (.docx / .rtf), native print

---

## Features

### Preview Rendering
- **Typora-style typography** — rendered headings, proper line-height, collapsed syntax markers
- **Emphasis via asterisks** — `*italic*` / `**bold**`; underscore emphasis (`_text_`) is not supported by design
- **Syntax highlighting** for Swift, Python, JavaScript, TypeScript, C/C++, Bash, SQL, JSON, HTML, XML, YAML
- **Mermaid diagrams** — flowcharts, sequence diagrams, class diagrams rendered inline
- **LaTeX math** — inline `$...$` and block `$$...$$` via KaTeX
- **Tables** — GitHub-flavored markdown tables with alignment and configurable column categories, matching words, priorities, and width weights
- **Nested lists** — proper indentation with different bullet styles (•, ◦, ▪, ▹)
- **YAML frontmatter** — displays document metadata from `---` blocks
- **Clickable links** — external URLs open in browser, relative `.md` links open as new tabs
- **Task lists** — `- [ ]` / `- [x]` rendered as read-only checkboxes
- **GitHub alerts** — `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]` callouts (preview and every export)
- **Code block copy** — hover a code block for a copy button, or right-click → Copy Code Block
- **Layout** — position the text column left / center / right and choose its width (Narrow → Full), from Settings or the status bar

### Navigation & Search
- **Multi-tab interface** — drag to reorder, right-click for tab options
- **Folder sidebar** — open a directory and browse all markdown files with FSEvents watching
- **Outline sidebar** — hierarchical heading navigation with click-to-scroll
- **Quick switcher** (`⌘⇧O`) — fuzzy search across open files, or `@file` / `#heading` targeted search
- **Command palette** (`⌘K`) — every app action, searchable
- **Find in document** (`⌘F`) — searches the rendered text, with match highlighting and next/previous navigation
- **Search in folder** (`⌃⇧F`, or type `>` in the quick switcher) — search file contents across the open folder; Enter opens the file on that exact match
- **Quick Look** — press Space on a `.md` file in Finder for a rendered preview
- **Reading position memory** — automatically remembers scroll position per document

### Export & Print
- **PDF export** — paginated, formatted, with syntax-highlighted code blocks
- **HTML export** — with or without embedded CSS styling
- **Word export** — both `.docx` (native XML) and `.rtf` formats
- **Native print** (`⌘P`) — macOS print dialog with full formatting
- **Mermaid and KaTeX** — included in exports with CDN script references

### File Handling
- **Live reload** — when another app saves an open file, its tab reloads silently and keeps your reading position; a deleted file asks before its tab closes
- **Read-only by design** — nothing in the app writes to your Markdown files, so closing a tab, closing the window and quitting never ask anything
- **Multi-encoding detection** — auto-decodes UTF-8, Windows CP1252, ISO Latin-1, Mac Roman, UTF-16
- **Reveal in Finder** — File → Open File Location, the tab's context menu, or the title bar's proxy icon
- **Open Recent** — last 10 files with bookmarks
- **Drag-and-drop** — drop `.md` files onto the window to open

### UX Polish
- **Focus mode** (`⌘⇧F`) — hides everything, centers content at 720px max, floating exit pill
- **Status bar** — word count, character count, reading time, layout, zoom, detected encoding
- **Zoom** — `⌘+` / `⌘−` / `⌘0`, pinch-to-zoom trackpad gesture
- **Themes** — System / Light / Dark application appearance, with separate drop-down menus for 102 light and 249 dark Base16 preview themes
- **Preview fonts** — independently select an installed proportional font for Markdown text and a monospaced font for code and commands

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI** | SwiftUI + AppKit interop |
| **Text engine** | `NSTextView` (Apple's native text system, not a web view) |
| **Parser** | Custom line-based markdown parser (single source of truth for preview + export) |
| **Syntax highlighting** | Regex-based, ~10 language grammars |
| **Diagrams / Math** | Headless `WKWebView` with Mermaid + KaTeX CDN scripts |
| **File watching** | `DispatchSourceFileSystemObject` + `FSEventStream` for directories |
| **Persistence** | `UserDefaults` + security-scoped bookmark data |
| **Distribution** | Built from source; an optional ad-hoc signed `.dmg` for local installs (main app is not sandboxed) |
| **Deployment target** | macOS 13.0+ |

---

## Quick Start

zMD Viewer has no published releases and no updater: build it from source.

### Build from Source

```bash
git clone https://github.com/ib0ndar/zMD.git
cd zMD
git switch viewer
open zMD.xcodeproj
```

Press `⌘R` in Xcode to build and run. The Xcode target and scheme are still called `zMD`; the
product is `zMD Viewer.app`.

For command-line builds and tests, use `./scripts/xcodebuild-zmd.sh` instead of invoking
`xcodebuild` directly. Debug builds have isolated app and Quick Look bundle IDs; when you finish
an Xcode GUI development session, run `./scripts/manage-dev-registrations.sh unregister` to
remove the development registrations without deleting the build.

**Requirements:** macOS 13.0+, Xcode 27+

### Build a DMG

```bash
./scripts/build-dmg.sh
```

Produces `build/zMD-Viewer.dmg` with the drag-to-Applications installer layout. The image is
ad-hoc signed and not notarized, so the first launch needs right-click → Open (or System
Settings → Privacy & Security → Open Anyway).

### Next to zMD

zMD Viewer (`com.zmd.viewer`) and zMD (`com.zmd.app`) are separate apps with separate settings;
the viewer starts with default settings and imports nothing from zMD. With both installed, both
offer to open Markdown files and both ship a Quick Look extension. Finder uses one Quick Look
extension for Markdown at a time; switch it in System Settings → General → Login Items &
Extensions → Quick Look.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘O` | Open file(s) |
| `⌘⌥O` | Open folder |
| `⌘⇧O` | Quick switcher (fuzzy search files + headings) |
| `⌃⇧F` | Search in folder |
| `⌘K` | Command palette |
| `⌘W` | Close tab |
| `⌘R` | Refresh the current tab |
| `⌘F` | Find in document |
| `⌘G` / `⌘⇧G` | Next / previous match |
| `⌘P` | Print |
| `⌘⇧F` | Focus mode |
| `⌘=` / `⌘−` / `⌘0` | Zoom in / out / reset |
| `⌘,` | Settings |
| `⌃Tab` / `⌃⇧Tab` | Next / previous tab |

---

## License

[MIT](LICENSE.md). Want to contribute? See [CONTRIBUTING.md](CONTRIBUTING.md).

---

<p align="center">
  <em>"It doesn't have to be a web view."</em><br/>
  <sub>-- every macOS user, every time they launch VS Code</sub>
</p>
