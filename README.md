<p align="center">
  <img src="design/icon/Hashlight-Frost-1024.png" width="160" alt="Hashlight" />
</p>

<h1 align="center">Hashlight</h1>

<p align="center">
  <strong>Native macOS Markdown viewer</strong><br/>
  A fast, read-only Markdown reader with tabs, a files-and-outline sidebar, folder search, and export to PDF, HTML, and Word. It never changes your files.<br/><br/>
  <a href="https://github.com/ib0ndar/Hashlight/releases/latest">Download</a> · <a href="https://github.com/ib0ndar/Hashlight/issues">Issues</a> · <a href="https://github.com/ib0ndar/Hashlight/blob/main/CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.1.0-f5a524?style=flat-square" alt="Version 1.1.0" />
  <img src="https://img.shields.io/badge/platform-macOS_13%2B-4a9eff?style=flat-square" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/stack-SwiftUI%20%7C%20AppKit%20%7C%20NSTextView-34d399?style=flat-square" alt="Stack" />
  <a href="https://github.com/ib0ndar/Hashlight/actions/workflows/ci.yml"><img src="https://github.com/ib0ndar/Hashlight/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI" /></a>
</p>

---

## What It Is

Hashlight is a Markdown reader for macOS. Open a file and it renders instantly; when another app
changes the file, the tab follows along without asking. It reads and exports, and never writes to
your Markdown: there is no editor, no saving, and nothing to confirm when you close a tab or quit.

It's a native SwiftUI app built around Apple's `NSTextView` rather than a web view — no
Electron, no Tauri.

### Origin

Hashlight grew out of [zMD](https://github.com/umzcio/zMD) by Zachary Rossmiller, a Markdown
editor. It took only zMD's reading side — the renderer, the navigation, and the exports — and left
the editor and the updater behind. That foundation has since been reworked heavily: a new window
built around a navigator sidebar and a Liquid Glass toolbar, three Settings panes, System themes
drawn from macOS's own colors, rounded code and table cards, a folding frontmatter card, and more.
Hashlight shares nothing with zMD at run time; the two can be installed side by side (see
[Next to zMD](#next-to-zmd)).

---

## How It Works

```
Open .md --> Rendered document (reloads when the file changes) --> Export PDF/HTML/Word
```

1. **Open a file**: `⌘O` or the toolbar's Open button, drag and drop, double-click in Finder, Open Recent, or a folder in the sidebar
2. **Read**: headings, code blocks with syntax highlighting, tables, Mermaid diagrams, LaTeX math, clickable links
3. **Find your way**: outline sidebar, find in the toolbar, Quick Open, search across a folder, command palette
4. **Export anywhere**: PDF (paginated), HTML (with or without styles), Word (.docx / .rtf), native print

---

## Features

### Rendering
- **Reading typography** — styled headings with rules, comfortable line height, no raw Markdown syntax on screen
- **Emphasis via asterisks** — `*italic*` / `**bold**`; underscore emphasis (`_text_`) is not supported by design
- **Syntax highlighting** for Swift, Python, JavaScript, TypeScript, C/C++, Bash, SQL, JSON, HTML, XML, YAML
- **Mermaid diagrams** — flowcharts, sequence diagrams, class diagrams rendered inline
- **LaTeX math** — inline `$...$` and block `$$...$$` via KaTeX
- **Tables** — GitHub-flavored markdown tables with column alignment; columns sized to their content (long columns share the space in wide tables), or optionally by header category (configurable categories, matching words, priorities, and width weights; off by default)
- **Nested lists** — proper indentation with different bullet styles (•, ◦, ▪, ▹)
- **YAML frontmatter** — a leading `---` block folds into a card labelled with its `title` (or "Document Info" and the key names when there is none), as in Xcode; click the row to show the YAML, or turn the card off in Settings → Viewing → Show frontmatter
- **Clickable links** — external URLs open in browser, relative `.md` links open as new tabs
- **Task lists** — `- [ ]` / `- [x]` rendered as read-only checkboxes
- **GitHub alerts** — `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]` callouts (on screen and in every export)
- **Code block copy** — hover a code block for a copy button, or right-click → Copy Code Block
- **Layout** — position the text column left / center / right and choose its width (Narrow → Full), from Settings → Viewing or the status bar

### Navigation & Search
- **Window** — a resizable, collapsible sidebar and a toolbar with Open, Focus Mode, Export, and Find (Liquid Glass on macOS 26; a standard toolbar on macOS 13–15)
- **Multi-tab interface** — drag to reorder, right-click for tab options; Settings → General can hide the tab bar while only one document is open
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
- **Themes** — System / Light / Dark application appearance, with separate menus for the light and dark document theme: a **System** theme (the default) built from macOS's own colors (text background, labels, separators, your accent color for headings and links), plus 102 light and 249 dark Base16 palettes
- **Fonts** — independently select an installed proportional font for Markdown text and a monospaced font for code and commands, each with its own size (8–32 pt; Reset returns to 16 and 13 pt)
- **Adaptive icon** — a Liquid Glass `#` lit by an amber spark; on macOS 26 it follows the system's icon style (Frost by default, Ember in dark, plus Clear and Tinted)
- **Dock icon** — keep the system's choice or always show Frost or Ember in the Dock and app switcher (Settings → General)
- **Settings** — three panes: **General** (appearance, Dock icon, tabs), **Viewing** (themes, fonts, layout, frontmatter), and **Tables** (column sizing by header category, off by default); Settings reopens on the pane you used last
- **About** — Hashlight → About Hashlight shows the version, the icon the Dock shows, and credits zMD

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI** | SwiftUI + AppKit interop |
| **Text engine** | `NSTextView` (Apple's native text system, not a web view) |
| **Parser** | Custom line-based markdown parser (single source of truth for the window and every export) |
| **Syntax highlighting** | Regex-based, ~10 language grammars |
| **Diagrams / Math** | Headless `WKWebView` with Mermaid + KaTeX CDN scripts |
| **File watching** | `DispatchSourceFileSystemObject` + `FSEventStream` for directories |
| **Persistence** | `UserDefaults` + security-scoped bookmark data |
| **Distribution** | An ad-hoc signed, universal `.dmg` on [GitHub Releases](https://github.com/ib0ndar/Hashlight/releases) (not notarized), or build from source; the main app is not sandboxed |
| **Deployment target** | macOS 13.0+ |

---

## Quick Start

### Install

Download the `.dmg` from the [latest release](https://github.com/ib0ndar/Hashlight/releases/latest),
open it, and drag Hashlight to Applications. It runs on macOS 13 or later, on Apple silicon and
Intel Macs. Hashlight has no updater: new versions appear on the
[Releases](https://github.com/ib0ndar/Hashlight/releases) page.

The app is ad-hoc signed and not notarized (it has no Apple Developer ID), so macOS blocks its
first launch:

1. Open Hashlight. macOS says it can't verify the app; click **Done**.
2. In System Settings → Privacy & Security, go to Security and click **Open Anyway** (it is offered
   for about an hour after the blocked launch), then confirm with your password.

From then on Hashlight opens normally. On macOS 13 and 14 you can instead Control-click Hashlight
in Applications and choose **Open**.

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

Produces `build/Hashlight.dmg` with the drag-to-Applications installer layout: a universal
(Apple silicon and Intel) app built from a clean Release product. The image is ad-hoc signed and
not notarized, so its first launch goes through **Open Anyway** as described under
[Install](#install).

### Next to zMD

Hashlight (`io.github.ib0ndar.hashlight`) has its own settings and imports nothing from zMD. With
both installed, each offers to open Markdown files and each ships a Quick Look extension. Finder
uses one Markdown Quick Look extension at a time; switch it in System Settings → General → Login
Items & Extensions → Quick Look.

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
