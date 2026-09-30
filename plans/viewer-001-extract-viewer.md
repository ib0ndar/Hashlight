# Plan viewer-001: extract zMD Viewer, a read-only product line

- **Status**: DONE — `viewer` pushed to `origin` at the user's request on 2026-09-30; hosted CI green
- **Created**: 2026-09-30
- **Base**: `master` at `c57f9b5` (the v2.12.3 line)
- **Product**: zMD Viewer 1.0.0 — no releases, no tags, never merged into `master`

## Decision

The user asked for a viewer-only edition of zMD and answered every open question before approval.
zMD Viewer lives on its own branch with its own identity, keeps zMD's renderer, navigation and
exports, and drops everything that edits or writes a document.

## Plan (as approved)

1. **Branch.** Create `viewer` locally from `master` at v2.12.3 (`c57f9b5`). Work goes in as a few
   logical commits and is pushed to `origin` only when the user says so. The branch is its own
   product line: it is never merged into `master` and never gets `vX.Y.Z` tags.
2. **App identity.** The app becomes "zMD Viewer" (`zMD Viewer.app`), with bundle IDs
   `com.zmd.viewer` and `com.zmd.viewer.debug`. The Quick Look extension becomes
   `com.zmd.viewer[.debug].QuickLook`, and its shared table-layout settings live in
   `com.zmd.viewer[.debug].table-column-layout`, with matching entitlements. The Xcode target,
   scheme and module stay named `zMD`. The document role changes from Editor to Viewer. All four
   version numbers are set to 1.0.0. The icon stays the same.
   - Side effects: settings start fresh, with no import from zMD. With both apps installed,
     macOS uses one Quick Look extension, which the user can switch in System Settings.
3. **Files deleted.** The source editor (`SourceEditorView`, `SourceEditorWithMinimap`,
   `EditorTextView`, `AutocompleteView`, `MultiCursorController`, `LineNumberGutter`,
   `MinimapView`, `MarkdownToolbarView`), the two-document split (`SplitPaneHeader`), and the
   updater (`UpdateManager` and the update sheet). `DocumentViewModeContent` shrinks to a plain
   preview view.
4. **`DocumentManager`.** Remove editing state and saving (view mode, split view, scroll sync,
   cursor line/column, auto-save, dirty/untitled state, `updateContent`, save and encoding
   write-back, New File, Duplicate/Rename/Move, find & replace, source-side regex matching) and
   the whole ask-before-close flow, so closing a tab, closing the window and quitting become
   immediate. Search covers the rendered preview only; folder-search hits still land on the right
   match. External changes reload the file silently and keep its scroll position. A deleted file
   still asks before its tab closes. "Ignore All" and "Resume File Watching" go away.
5. **Task checkboxes become read-only.** The click handler, `togglingTask` in the shared parser,
   and their tests are removed.
6. **Menus and command palette.** Removed: the Format menu, Save, Save As, New, Rename, Move,
   ⌘1/⌘2/⌘3, scroll sync, line numbers, minimap, editor toolbar, Find and Replace, and Check for
   Updates. Kept: Open, Open Recent, Quick Open, Search in Folder, the folder commands, Reveal in
   Finder, Export, Print, Focus Mode, ⌘K, zoom, Refresh, the Tab menu, Find/Next/Previous, and
   Help. "Search in Folder" stays at ⌃⇧F.
7. **UI.** The tab bar loses the mode picker, the unsaved-changes dot and "Open in Split View".
   The status bar loses Ln/Col and the mode label, and always shows the layout menu. The welcome
   screen says "Markdown Viewer" and has no New File button. Settings loses the General tab;
   Appearance stays, including the table categories under Advanced; About has no update button.
   `SettingsManager` loses the editor settings, their keys and timing constants.
8. **Tests.** Remove the tests for editing, saving, closing with unsaved changes, open-mode, the
   line-number gutter and the updater. Adapt the find and folder-search tests to preview-only
   search. Add tests that an external change reloads the file with no prompt, that clicking a
   checkbox never changes the content, and that closing or quitting never shows a prompt.
9. **Docs and scripts.** Rewrite the README, `CLAUDE.md` and the in-app Help for the viewer, and
   give `AGENTS.md` a "viewer branch" section. Update `manage-dev-registrations.sh`,
   `xcodebuild-zmd.sh` and `build-dmg.sh` (which produces `build/zMD-Viewer.dmg`) for the new
   names. Save this plan here.
10. **Checks.** The wrapper's Debug tests, a Release compile, `plutil -lint`, `git diff --check`,
    and the theme JSON and `ruby -c` checks. Confirm the built bundles' IDs, versions and document
    role. By hand in the running app: light and dark themes, Mermaid and KaTeX, find, the outline,
    focus mode, folder search, and an export and print spot-check. Finish with
    `manage-dev-registrations.sh unregister`. `FuzzyMatcher.swift` is left alone.

## Execution notes

### 2026-09-30

**Commits on `viewer`** (after `c57f9b5`):

1. `viewer: rename the product to zMD Viewer 1.0.0` — identity, entitlements, shared preference
   domain, document role, and the three scripts. `PRODUCT_NAME = "zMD Viewer"` with
   `PRODUCT_MODULE_NAME = zMD`; the test host path follows.
2. `viewer: remove the updater`.
3. `viewer: remove the editor and make every document read-only` — items 3–8.
4. The docs commit (README, `CLAUDE.md`, `CONTRIBUTING.md`, `AGENTS.md`, Help, this plan) and a
   fixes commit for what the hands-on check found (see below).

**Decisions made while implementing** (consequences of the plan, not new scope):

- The Match Case and regex toggles lived only in the replace bar, so they went with find &
  replace. Find in the preview is literal and case-insensitive, as preview-mode find was before
  and as folder search is. `AccessibilityCopy.swift` served only those toggles and was removed
  with its test.
- `MarkdownTextView` lost the scroll-sync plumbing (`onScrollPercentChanged`, `scrollToPercent`,
  the programmatic-scroll and reflow flags), the regex/case flags, the checkbox click handler and
  the checkbox's pointing-hand cursor.
- Code that only existed for saves went too: `FileWatcher.ignoreNextChange` and
  `hasPendingExternalChange`, `FolderManager`'s self-write suppression (and
  `FolderManagerLifecycleTests`, which tested it), and `AlertManager`'s dirty-close,
  file-changed and save-error dialogs.
- Reload keeps the scroll position in `MarkdownTextView`: a content change for the document on
  screen is a reload, debounced 150ms, and restores the reader's Y instead of the remembered
  position.
- A folder-search hit opened while the find bar already shows the same query is now resolved
  against the preview's existing matches (previously it waited for a query change).
- Quit: `AppDelegate` no longer implements `applicationShouldTerminate(_:)`.
- `FuzzyMatcher.swift` is not unused — Quick Open and the command palette call `fuzzyMatch` — so
  leaving it alone was right for a different reason.
- `.github/workflows/ci.yml` on this branch also triggers on pushes to `viewer` and pull requests
  into it (added after the plan's execution, at the user's request). The first hosted run passed;
  see Tests below.

**Tests.** 98 pass, 0 failures, 0 warnings (123 on `master`: −6 updater, −25 editor/saving/
close-prompt/open-mode/gutter/checkbox-toggle, +6 new; counted from the `func test` declarations).
Hosted CI (run 36692218572: Xcode 26.6, Swift 6.3.3) passed all 98 on `2b0913b`. New tests:

- `RuntimeSmokeTests.testExternalChangeReloadsTheOpenDocumentWithoutAPrompt`,
  `testClosingATabIsImmediate`, and `testFileWatcherReportsEditsAcrossAtomicRenames` (adapted).
- `CloseWithoutPromptTests`: the red close button closes every tab and the window at once; Quit
  is not intercepted.
- `PreviewBehaviorTests` hosts the real `DocumentViewModeContent` → `MarkdownTextView` in an
  off-screen window: a real click on a checkbox changes neither the rendered text nor the
  document; a reload keeps the scroll position (the test fails if the keep-position path is
  disabled — checked); find counts rendered matches only, and a folder-search hit lands on its
  match both from a closed find bar and with the query already shown.
- `ReviewFixTests.testRevealRelocatesInTheLoadedTextAndIgnoresUnselectedFiles` (adapted).

**Automated checks.** Debug tests via the wrapper; Release compile (unsigned) with no warnings;
`plutil -lint` on the project, both Info.plists and all three entitlements; theme JSON parses;
`ruby -c scripts/update-base16-themes.rb`; `git diff --check`.

**Built bundles.** Debug: `com.zmd.viewer.debug`, "zMD Viewer Debug", executable `zMD Viewer`,
1.0.0, role Viewer, rank None; extension `com.zmd.viewer.debug.QuickLook` 1.0.0 with the
`com.zmd.viewer.debug.table-column-layout` read-only exception. Release: `com.zmd.viewer`,
"zMD Viewer", 1.0.0, role Viewer, rank Default; extension `com.zmd.viewer.QuickLook` 1.0.0;
the app and extension binaries reference `com.zmd.viewer.table-column-layout`.

**By hand** (Debug build, fixtures and screenshots in the ignored `artifacts/` tree):

- Light and dark: preview themes switch with the appearance; Settings has only Appearance and
  About; About shows "zMD Viewer", 1.0.0, no update button.
- Mermaid and KaTeX render as images (see the dark-mode finding below).
- Find: rendered-text matches with highlights, ⌘G moves 1/3 → 2/3, no replace row or toggles.
- Outline: headings list; clicking "Math" scrolls to it.
- Focus mode on and off.
- Folder search (⌃⇧F): two hits across the folder; Enter opened `beta.md` with the find bar on
  the hit.
- External change: an atomic rewrite of an open file (appending a line) reloaded the tab with no
  prompt and kept paragraphs 117–124 on screen.
- A deleted open file asked "File Deleted"; Close Tab closed only that tab.
- The red close button with two tabs closed the window at once, the app kept running, and
  reopening showed the welcome screen ("Markdown Viewer", Open File only).
- Quit with a document open exited at once.
- Menus match item 6; the tab bar and status bar match item 7.
- Exports: HTML (read-only ☐/☑ tasks, tables, inline math image, alerts) and PDF (2 pages, all
  elements) written; the Print dialog opened with the document and was cancelled — nothing was
  printed. The check document's checksum was unchanged afterwards.

**Found and fixed during the hands-on check:**

- The File menu showed two adjacent separators, because the replaced `saveItem` group was empty.
  Open File Location now sits in that group.
- The command palette kept showing the first rows of the unfiltered list after typing, while
  Enter ran the filtered command. Each row carried an index-based `.id` that overrode the
  `ForEach` identity; it is gone and `scrollTo` targets the command's id. The same code is on
  `master` (not verified there).

**Found, not fixed (pre-existing, outside this plan):**

- In the dark theme, KaTeX images have a white background. `WebRenderer.swift` is unchanged
  since 2.12.1. On macOS 26.7.1, `WKWebView` does not respond to `setDrawsBackground:` (it
  responds to `_setDrawsBackground:`), so `configureTransparentBackground` leaves the web view
  opaque. This affects `master` as well and should be fixed there first.

**Cleanup.** `manage-dev-registrations.sh unregister` leaves no zMD Viewer registrations. Before
switching the script to the viewer IDs, this checkout's stale zMD development registrations
(`build/Release/zMD.app`, `build/Xcode/{Debug,Release}/zMD.app`) were unregistered with the
`master` script; the installed `/Applications/zMD.app` was kept. The `com.zmd.viewer.debug` and
`com.zmd.viewer.debug.table-column-layout` defaults domains, which this session's test and
hands-on runs had created and pointed at the fixtures, were deleted; `com.zmd.viewer` was never
created.
