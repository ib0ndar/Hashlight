# Hashlight — handover

Read this first if you are picking up Hashlight development, then `AGENTS.md` (the rules, which
OpenCode loads automatically) and `plans/README.md` (what has been done and what is next).
Written 2026-09-30.

## In one paragraph

Hashlight is a native, read-only Markdown viewer for macOS 13+ (Swift 6, SwiftUI + AppKit, an
`NSTextView` renderer). It started as zMD Viewer, a read-only edition of the zMD editor, and is now
an independent project with its own identity, icon, and repository. The code builds, all 104 tests
pass locally (Xcode 27), and the official icon is wired in. Plan 003 added a Dock icon setting
(System / Frost / Ember) on every macOS version; hosted CI (Xcode 26.6) last passed before it, so
check the run after the next push. **Next task:** none planned; see "Open decisions" below.

## Where everything is

| What | Where |
|---|---|
| Working directory | `/Users/ivan/git/Hashlight` (branch `main`) |
| Repository | https://github.com/ib0ndar/Hashlight (public, default branch `main`, not a GitHub fork). Only `origin` is configured. |
| CI | `.github/workflows/ci.yml`: build and test on pushes to and PRs into `main`, runner `macos-26` (Xcode 26.6). Dependabot is on for GitHub Actions. |
| Agent rules | `AGENTS.md`: identity, build/test commands, registration hygiene, Finder safety, release rules, known issues |
| Architecture guide | `CLAUDE.md` |
| Plans | `plans/` (001 create, 002 icon, 003 Dock icon setting) |
| Official icon and brand | `design/` (start with `design/BRIEF.md`); compiled icon `Hashlight/Hashlight.icon` |
| Manual-test documents | `fixtures/` (see `fixtures/README.md`) |
| Scratch output (ignored) | `artifacts/`: screenshots of the Hashlight checks (`artifacts/screens/`) and build/test logs. Not in git. |
| zMD, the origin (read-only for this project) | https://github.com/ib0ndar/zMD, checkout `/Users/ivan/git/zMD`: `master` = zMD 2.12.3 (`c57f9b5`), `viewer` = zMD Viewer 1.0.0 (`7cf0357`, the tree Hashlight was imported from). Upstream: https://github.com/umzcio/zMD. Never push to either from here. |

## Identity (details in `AGENTS.md`)

- App `Hashlight.app`, version 1.0.0, document role Viewer.
- Bundle IDs: `io.github.ib0ndar.hashlight`, and `io.github.ib0ndar.hashlight.debug` for Debug
  builds, which display as "Hashlight Debug".
- Quick Look extension `io.github.ib0ndar.hashlight[.debug].QuickLook`, which reads the
  table-layout preferences domain `io.github.ib0ndar.hashlight[.debug].table-column-layout`.
- Project `Hashlight.xcodeproj`; targets `Hashlight`, `HashlightQuickLook`, `HashlightTests`;
  scheme and module `Hashlight`.
- License: MIT. `LICENSE.md` keeps Zachary Rossmiller's (zMD) notice and adds Ivan Bondar's line;
  keep the attribution (`THIRD_PARTY_NOTICES.md`, "Based on zMD" in Settings → About).

## How we got here

1. **zMD** (`ib0ndar/zMD`, a fork of `umzcio/zMD`): a Markdown editor and viewer, last release
   v2.12.3.
2. **zMD Viewer** (zMD's `viewer` branch, plan `viewer-001` there):
   - removed the source editor, split view, saving, find & replace, close prompts, and the
     updater;
   - made task checkboxes read-only and made external changes reload silently while keeping the
     scroll position;
   - fixed the command palette's filtering and the File menu separators.
3. **Hashlight** (this repository):
   - `5210c6e` imports that tree unchanged (fresh history, by the owner's choice);
   - `c16a2ad` renames everything;
   - `518c4a2` rewrites the docs;
   - `7333e6b` wires in the official icon (plans 001 and 002);
   - plan 003 adds the Dock icon setting.

## What the product does (and must keep doing)

- It never writes to a Markdown file:
  - no editor or saving;
  - task checkboxes are read-only;
  - closing a tab or the window and quitting never prompt.
- Reloads: an external change reloads the tab silently and keeps its scroll position; a deleted
  file asks before its tab closes.
- Find searches the rendered text (literal, case-insensitive). Folder search (⌃⇧F) opens a hit on
  its exact match.
- Other features: tabs, outline, Quick Open (⌘⇧O), command palette (⌘K), focus mode, themes (351
  Base16 palettes) and fonts, Mermaid and KaTeX, and export to PDF, HTML, DOCX, and RTF plus
  print.
- A Dock icon setting (Settings → Appearance → Icon: System / Frost / Ember) on every macOS
  version. System leaves the icon to macOS; the welcome screen and About show the chosen icon.
- A Quick Look extension renders Markdown in Finder.
- There is no updater and no published release yet.

## Build, test, check

```bash
./scripts/xcodebuild-hashlight.sh -configuration Debug test          # 104 tests
./scripts/xcodebuild-hashlight.sh -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' build
xcrun xcresulttool get test-results summary --path "$(ls -td build/Xcode/DerivedData/Logs/Test/*.xcresult | head -1)"
./scripts/manage-dev-registrations.sh status        # then `unregister` when you finish
```

- **Always use the wrapper**, never bare `xcodebuild`. It also cleans Launch Services
  registrations of development builds.
- **Count tests from the result bundle.** Grepping the log undercounts, because parallel output
  interleaves result lines.
- **Before committing:** `git diff --check`, `plutil -lint Hashlight.xcodeproj/project.pbxproj`,
  and a hands-on check for UI or rendering changes (next section).

## Checking the running app by hand (what worked)

The agent-desktop CLI (`/Users/ivan/.local/bin/agent-desktop`) has Accessibility and Screen
Recording permission. The Debug app's name for it is **"Hashlight Debug"**.

- **Launch** with `open -a "$PWD/build/Xcode/Debug/Hashlight.app" "$PWD/fixtures/rendering-check.md"`.
  Launching registers the app; unregister afterwards.
- **Quit** with `osascript -e 'tell application id "io.github.ib0ndar.hashlight.debug" to quit'`;
  agent-desktop blocks `cmd+q`.
- **Screenshots:** `agent-desktop screenshot --app "Hashlight Debug" artifacts/screens/NAME.png`.
  Scope screenshots to the app; don't capture the whole screen, which shows the owner's other
  windows.
- **Menus:** agent-desktop's menu refs go stale as soon as the menu closes. Click menu items with
  System Events:
  `osascript -e 'tell application "System Events" to tell process "Hashlight" to click menu item "Print..." of menu "File" of menu bar 1'`.
  The Print dialog and some panels don't appear in agent-desktop's window list either; reach them
  through System Events.
- **Return key:** a Return sent by agent-desktop did not reach the command palette's text field.
  A System Events `key code 36`, sent after confirming the app is frontmost, did.
- **Folder sidebar:** security-scoped bookmarks made by another process are rejected, so a script
  can't pre-seed the folder. What worked: a throwaway XCTest that calls
  `FolderManager.shared.setFolder(URL(fileURLWithPath: …))` (it stores the bookmark in the Debug
  defaults), run once with `-only-testing:` and then deleted. The normal UI route is Open Folder
  (⌘⌥O).
- **Dock tile:** the Dock is not in agent-desktop's window list. Get the tile's frame with
  `osascript -e 'tell application "System Events" to tell process "Dock" to get {position, size} of (first UI element of list 1 whose name contains "Hashlight")'`
  and capture only that rectangle with `screencapture -x -R x,y,w,h artifacts/screens/NAME.png`.
- **Stale app icon** after changing the icon: run
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/Xcode/Debug/Hashlight.app`
  and relaunch.
- **Afterwards:**
  - quit the app;
  - run `./scripts/manage-dev-registrations.sh unregister` (Spotlight can re-register a fresh
    build, so check `status`);
  - reset any Debug settings you changed:
    `defaults delete io.github.ib0ndar.hashlight.debug` and
    `defaults delete io.github.ib0ndar.hashlight.debug.table-column-layout`.
- **Finder:** never move, resize, or re-style Finder windows. The owner's Finder opens new windows
  as tabs in their own window (see `AGENTS.md`).

## Known issues and quirks

- **KaTeX in the dark theme:** math images have a white background. On macOS 26.7.1 `WKWebView`
  has no `setDrawsBackground:` (only `_setDrawsBackground:`), so
  `WebRenderer.configureTransparentBackground` leaves it opaque. Inherited from zMD; not fixed.
- **Icon on macOS 13–15:** they show Xcode's generated Frost fallback, not the designer's
  hand-tuned small sizes. Apple's tooling makes the compiled icon win everywhere. See plan 002.
  While Hashlight runs, the Dock icon setting (plan 003) shows the designer's `.icns` in the Dock.
- **Dock icon setting on macOS 13–15:** never run on those systems (no machine); unit tests only.
- **Settings window height:** the Appearance tab is taller than its fixed 480 × 620 pt window on
  macOS 26 and scrolls (Zoom and Advanced were already below the fold before plan 003).
- **`xcodebuild clean`** via the wrapper fails ("Could not delete build/Xcode because it was not
  created by the build system"). To force a clean product, delete the product under
  `build/Xcode/<Config>/` instead. Inherited build layout.
- **Signing settings:** the Release configuration still carries zMD's Developer ID signing
  settings (team `5JJ6G6A84S`). Local compiles and `build-dmg.sh` override them.
- **Title-bar document icon:** the title bar shows the document icon of whichever app owns `.md`
  files. On this Mac that is the installed `/Applications/zMD.app`, so it shows zMD's icon. That
  isn't a Hashlight bug.
- **Coexistence with zMD:** both apps claim Markdown and both ship Quick Look extensions. Finder
  uses one; choose it in System Settings → General → Login Items & Extensions → Quick Look.

## Open decisions (owner)

- **From `design/BRIEF.md` §6:**
  - minimum macOS version (currently 13);
  - distribution (currently a direct, ad-hoc signed DMG; no notarization, since the owner has no
    Apple Developer Program membership);
  - feature scope;
  - registering `hashlight.app`. The brief suggests the bundle ID `app.hashlight.Hashlight`; the
    owner chose `io.github.ib0ndar.hashlight`, and changing it would reset users' settings.
- **Amber accent colour:** the brief suggests it for the UI; the app still uses the system accent.
- **First release:** version, tag, and GitHub release process (see `AGENTS.md`, "Versions, DMGs,
  and releases").

## Follow-ups that belong to zMD, not here

Both problems below also exist on zMD `master`. Fix them there only if the owner asks.

- **Command palette** (fixed on zMD's `viewer` branch and in Hashlight): rows kept an index-based
  `.id`, so filtering showed stale rows while Enter ran the filtered command.
- **KaTeX dark background:** the issue above.
