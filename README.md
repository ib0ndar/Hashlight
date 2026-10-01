<p align="center">
  <img src="design/icon/Hashlight-Frost-1024.png" width="160" alt="Hashlight" />
</p>

<h1 align="center">Hashlight</h1>

<p align="center">
  <strong>Native macOS Markdown viewer</strong><br/>
  A lightweight, Typora-inspired reader with tabs, a files-and-outline sidebar, folder search, and full export support. It never changes your files.<br/><br/>
  <a href="https://github.com/ib0ndar/Hashlight/issues">Issues</a> · <a href="https://github.com/ib0ndar/Hashlight/blob/main/CLAUDE.md">Developer Guide</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-f5a524?style=flat-square" alt="Version 1.0.0" />
  <img src="https://img.shields.io/badge/platform-macOS_13%2B-4a9eff?style=flat-square" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/stack-SwiftUI%20%7C%20AppKit%20%7C%20NSTextView-34d399?style=flat-square" alt="Stack" />
  <a href="https://github.com/ib0ndar/Hashlight/actions/workflows/ci.yml"><img src="https://github.com/ib0ndar/Hashlight/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI" /></a>
</p>

---

## Origin

Hashlight is a Markdown reader for macOS. Open a file and it renders instantly; when another app
changes the file, the tab follows along without asking. It reads and exports, and never writes to
your Markdown: there is no editor, no saving, and nothing to confirm when you close a tab or quit.

It's a native SwiftUI app built around Apple's `NSTextView` rather than a web view — no
Electron, no Tauri.

Hashlight grew out of [zMD](https://github.com/umzcio/zMD) by Zachary Rossmiller, by way of zMD
Viewer, a read-only edition of [the ib0ndar/zMD fork](https://github.com/ib0ndar/zMD). It keeps
zMD's renderer, navigation, and exports; the editor, the updater, and zMD's history stay behind.

---

## How It Works

```
Open .md --> Rendered preview (reloads when the file changes) --> Export PDF/HTML/Word
```

1. **Open a file**: `⌘O` or the toolbar's Open button, drag and drop, double-click in Finder, Open Recent, or a folder in the sidebar
2. **Read**: headings, code blocks with syntax highlighting, tables, Mermaid diagrams, LaTeX math, clickable links
3. **Find your way**: outline sidebar, find in the toolbar, Quick Open, search across a folder, command palette
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
- **Layout** — position the text column left / center / right and choose its width (Narrow → Full), from Settings → Preview or the status bar

### Navigation & Search
- **Window** — a resizable, collapsible sidebar and a toolbar with Open, Focus Mode, Export, and Find (Liquid Glass on macOS 26; a standard toolbar on macOS 13–15)
- **Multi-tab interface** — drag to reorder, right-click for tab options
- **Sidebar navigator** — one sidebar that switches between **Files** (`⌘⌥1`) and **Outline** (`⌘⌥2`); show or hide it with `⌃⌘S`
- **Files** — open a directory and browse all markdown files with FSEvents watching
- **Outline** — hierarchical heading navigation with click-to-scroll
- **Quick switcher** (`⌘⇧O`) — fuzzy search across open files, or `@file` / `#heading` targeted search
- **Command palette** (`⌘K`) — every app action, searchable
- **Find in document** (`⌘F`) — the toolbar's search field searches the rendered text, with match highlighting, a match counter, and next/previous navigation (`Return`, `⌘G`, `⌘⇧G`)
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
- **Reveal in Finder** — File → Open File Location, the tab's or sidebar's context menu, or the title bar's proxy icon
- **Open Recent** — last 10 files with bookmarks
- **Drag-and-drop** — drop `.md` files onto the window to open

### UX Polish
- **Focus mode** (`⌘⇧F`) — hides the sidebar, toolbar items, tabs, and status bar, centers content at 720px max; a floating (Liquid Glass) exit button appears on hover
- **Status bar** — word count, character count, reading time, layout, zoom, detected encoding
- **Zoom** — `⌘+` / `⌘−` / `⌘0`, pinch-to-zoom trackpad gesture
- **Themes** — System / Light / Dark application appearance, with separate drop-down menus for 102 light and 249 dark Base16 preview themes
- **Preview fonts** — independently select an installed proportional font for Markdown text and a monospaced font for code and commands
- **Adaptive icon** — a Liquid Glass `#` lit by an amber spark; on macOS 26 it follows the system's icon style (Frost by default, Ember in dark, plus Clear and Tinted)
- **Dock icon** — keep the system's choice or always show Frost or Ember in the Dock and app switcher (Settings → General)
- **Settings** — three panes: **General** (appearance, Dock icon), **Preview** (themes, fonts, layout), and **Tables** (column categories); Settings reopens on the pane you used last
- **About** — Hashlight → About Hashlight shows the version, the icon the Dock shows, and the zMD credit

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

There are no published releases yet, and Hashlight has no updater: build it from source.

### Build from Source

```bash
git clone https://github.com/ib0ndar/Hashlight.git
cd Hashlight
open Hashlight.xcodeproj
```

Press `⌘R` in Xcode to build and run.

For command-line builds and tests, use `./scripts/xcodebuild-hashlight.sh` instead of invoking
`xcodebuild` directly. Debug builds have isolated app and Quick Look bundle IDs; when you finish
an Xcode GUI development session, run `./scripts/manage-dev-registrations.sh unregister` to
remove the development registrations without deleting the build.

**Requirements:** macOS 13.0+, Xcode 27+

### Build a DMG

```bash
./scripts/build-dmg.sh
```

Produces `build/Hashlight.dmg` with the drag-to-Applications installer layout. The image is
ad-hoc signed and not notarized, so the first launch needs right-click → Open (or System
Settings → Privacy & Security → Open Anyway).

### Next to zMD

Hashlight (`io.github.ib0ndar.hashlight`) has its own settings and imports nothing from zMD or zMD
Viewer. With more than one of them installed, each offers to open Markdown files and each ships a
Quick Look extension. Finder uses one Markdown Quick Look extension at a time; switch it in System
Settings → General → Login Items & Extensions → Quick Look.

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
| `⌘F` | Find in document (toolbar search field) |
| `⌘G` / `⌘⇧G` | Next / previous match |
| `⌘P` | Print |
| `⌘⇧F` | Focus mode |
| `⌃⌘S` | Show / hide the sidebar |
| `⌘⌥1` / `⌘⌥2` | Sidebar: Files / Outline |
| `⌘=` / `⌘−` / `⌘0` | Zoom in / out / reset |
| `⌘,` | Settings |
| `⌃Tab` / `⌃⇧Tab` | Next / previous tab |

---

## Icon and Design

The official icon and brand package live in [`design/`](design/); start with
[`design/BRIEF.md`](design/BRIEF.md). The app compiles `Hashlight/Hashlight.icon`, an Icon Composer
bundle: macOS 26 renders it with the system's icon style, and Xcode generates a flattened Frost
fallback for macOS 13–15. Settings → General → Dock icon can instead pin the running app's Dock icon
to Frost or Ember, using the designer's `.icns` renditions; Finder always shows the bundle icon.
`design/icon/Hashlight-Frost-1024.png` is the canonical marketing image.

---

## License

[MIT](LICENSE.md). Hashlight keeps zMD's MIT notice (Zachary Rossmiller) alongside its own; bundled
third-party data is listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Want to
contribute? See [CONTRIBUTING.md](CONTRIBUTING.md).

---

<p align="center">
  <em>"It doesn't have to be a web view."</em><br/>
  <sub>-- every macOS user, every time they launch VS Code</sub>
</p>
