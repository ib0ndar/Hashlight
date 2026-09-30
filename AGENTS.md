# Hashlight agent guide

This file is the repository-specific source of truth for coding agents working on Hashlight. Read
it before changing code, choosing a version number, creating a tag, or pushing anything.

Start with `HANDOVER.md` for the current state, open decisions, and hands-on testing notes, and with
`plans/README.md` for finished and upcoming work (plans 001–003 are done; no next task is planned).

## Repository identity and origin

- The authoritative repository is **https://github.com/ib0ndar/Hashlight** (public, default branch
  `main`). `origin` must point to `https://github.com/ib0ndar/Hashlight.git`. Push only there.
- The expected local checkout is `/Users/ivan/git/Hashlight`. The authenticated GitHub account is
  `ib0ndar`.
- Hashlight is an independent project, not a GitHub fork. It started from zMD Viewer, the
  read-only edition of zMD, at `ib0ndar/zMD@7cf0357` (the `viewer` branch); the first commit's
  tree is identical to that commit. zMD's history stays in https://github.com/ib0ndar/zMD, and zMD
  itself is https://github.com/umzcio/zMD by Zachary Rossmiller.
- Keep the attribution: the MIT notice for Zachary Rossmiller in `LICENSE.md`, the zMD section of
  `THIRD_PARTY_NOTICES.md`, and the "Based on zMD" line in Settings → About.
- To bring a specific fix over from zMD, add a read-only remote and cherry-pick deliberately:
  `git remote add zmd https://github.com/ib0ndar/zMD.git && git remote set-url --push zmd DISABLED`.
  Never push to `ib0ndar/zMD` or `umzcio/zMD` from this repository.

Verify this before any remote write:

```bash
git remote -v
gh repo view ib0ndar/Hashlight --json nameWithOwner,defaultBranchRef,viewerPermission,url
```

## Product identity

- The app is **Hashlight** (`Hashlight.app`; "Hashlight Debug" in Debug builds). Bundle IDs are
  `io.github.ib0ndar.hashlight` and `io.github.ib0ndar.hashlight.debug`.
- The Quick Look extension is `io.github.ib0ndar.hashlight.QuickLook` /
  `io.github.ib0ndar.hashlight.debug.QuickLook` ("Hashlight Quick Look"). Its table-layout
  preferences domain is `io.github.ib0ndar.hashlight.table-column-layout` /
  `io.github.ib0ndar.hashlight.debug.table-column-layout`, with matching read-only entitlements.
- The Xcode project is `Hashlight.xcodeproj` with the `Hashlight`, `HashlightQuickLook`, and
  `HashlightTests` targets; the scheme and Swift module are `Hashlight`.
- The document role is Viewer. Release declares `LSHandlerRank=Default`, Debug `None`.
- The version is 1.0.0. There are four `MARKETING_VERSION` values in
  `Hashlight.xcodeproj/project.pbxproj` (Debug and Release for the app and the Quick Look
  extension); change them together and check that the built app and embedded extension agree.
- The app icon is the official Hashlight icon, delivered as a design package in `design/` (read
  `design/BRIEF.md`). See "App icon and design assets" below.
- The Release configuration still carries zMD's original signing settings (`Developer ID
  Application`, team `5JJ6G6A84S`). Local release compiles and `build-dmg.sh` override them; do not
  rely on them.

## What the product is

Hashlight is a native macOS 13+ Markdown **viewer** written in Swift 6 with SwiftUI and AppKit. It
never writes to a user's Markdown file:

- There is no source editor, split view, saving, New File, Rename/Move, find & replace, or
  clickable task checkbox. Task checkboxes render read-only.
- There is no ask-before-close flow: closing a tab or the window and quitting are immediate.
- An external change reloads the tab silently and keeps its scroll position; a deleted file asks
  before its tab closes.
- Find searches the rendered preview only (literal, case-insensitive, like folder search).
- There is no updater.

The preview is an `NSTextView`, not a browser. A small headless `WKWebView` is used only for
Mermaid, KaTeX, and HTML fragments. There are no SwiftPM, CocoaPods, or Carthage dependencies.

Main components:

- `Hashlight/HashlightApp.swift`: app/scenes, commands, window lifecycle, app-wide appearance.
- `Hashlight/DocumentManager.swift`: documents, tabs, loading and silent reloads, file watching,
  find state, and closing.
- `Hashlight/SettingsManager.swift`: persisted appearance, Dock icon, preview, layout, zoom, and
  table settings.
- `Hashlight/DockIconController.swift`: applies the Dock icon setting to the running app's icon.
- `Hashlight/MarkdownParser.swift`: block parser and HTML generation shared with Quick Look.
- `Hashlight/InlineMarkdown.swift`: shared inline tokenizer.
- `Hashlight/MarkdownTextView.swift`: native rendered preview (including reload handling).
- `Hashlight/SyntaxHighlighter.swift`: preview code highlighting.
- `Hashlight/WebRenderer.swift`: Mermaid, math, and HTML fragment rendering.
- `Hashlight/PreviewTheme.swift`: bundled Base16 theme loading and semantic color mapping.
- `Hashlight/PreviewFont.swift`: installed proportional and monospaced preview-font catalogs.
- `Hashlight/SharedConstants.swift`: constants and table-column configuration/layout shared by the
  app and Quick Look extension.
- `HashlightQuickLook/`: sandboxed Finder Quick Look extension.
- `HashlightTests/`: XCTest target covering parsing, rendering behavior, the preview, file
  watching and closing, Quick Look, themes, fonts, table layout, and the Dock icon setting.

Read `CLAUDE.md` for the longer architecture guide and `CONTRIBUTING.md` for code conventions.

## App icon and design assets

`design/` holds the official brand and icon package exactly as delivered on 2026-09-30 (its
`README.md`, `BRIEF.md`, `manifest.json`, `icon/`, `naming/`, and `tools/`). It is the source of
truth: do not edit its files by hand; change the SVG masters or `design/tools/`, regenerate, and
copy the results.

- **The compiled icon** is `Hashlight/Hashlight.icon`, an Icon Composer bundle placed beside (not
  inside) `Assets.xcassets`, following `design/BRIEF.md` §4.1. It must stay identical to
  `design/icon/Hashlight.icon` (`diff -r` them after any change). Appearances: Default = Frost,
  Dark = Ember; Clear and Tinted are derived by the system.
- **Wiring.** The project reference has type `folder.iconcomposer.icon` and is in the app target's
  Resources phase; `ASSETCATALOG_COMPILER_APPICON_NAME = Hashlight` in both configurations. The
  asset catalog has no `AppIcon` set. `Hashlight/Info.plist` does not set `CFBundleIconFile` or
  `CFBundleIconName`: the asset compiler writes both as `Hashlight`, builds `Assets.car`, and
  generates a flattened `Hashlight.icns` fallback because the deployment target is macOS 13. The
  Markdown document type's `CFBundleTypeIconFile` points at that `Hashlight` icon.
- **macOS 26+** shows the layered icon and switches it with System Settings → Appearance → Icon &
  widget style. The app's own Light/Dark setting does not change the icon.
- **macOS 13–15** show Xcode's flattened Frost fallback from `Assets.car`, not the hand-tuned 16
  and 32 px renditions in `design/icon/Hashlight-Frost.icns`. Brief §4.1 step 3 suggests pointing
  `CFBundleIconFile` at that `.icns`, but with an Icon Composer icon, current Xcode makes the
  catalog icon win on every macOS version (Apple: "by design"), and the known workarounds need
  Xcode 26.0.1 or a checked-in prebuilt `Assets.car`. It is not done; revisit only with the user
  and a macOS 15 machine to verify on.
- **Dock icon setting** (plan 003): Settings → Appearance → Icon → Dock icon: System / Frost /
  Ember, default System, on **every** macOS version. The owner decided on 2026-09-30 to offer it on
  macOS 26 as well, overriding brief §4.2 ("hide the preference on macOS 26"); do not hide it
  again without asking.
  - System leaves the icon to macOS: on macOS 26 the icon style above; on macOS 13–15 Frost in
    Light mode and Ember in Dark mode. It follows the system's Light/Dark setting, not the app's
    own Appearance override (brief §4.2's "Match appearance", as the owner chose).
  - Frost and Ember always show that icon. `DockIconController` changes only
    `NSApp.applicationIconImage` (Dock tile and app switcher while the app runs). Never rewrite
    the bundle's icon on disk: Finder, Launchpad, and a quit app keep the bundle icon.
  - The images are `Hashlight/DockIcon-Frost.icns` and `DockIcon-Ember.icns`, byte-for-byte copies
    of `design/icon/Hashlight-Frost.icns` and `Hashlight-Ember.icns` (`cmp` them after any
    change). Do not name either `Hashlight.icns`: the asset compiler writes that file.
  - The welcome screen and Settings → About draw `DockIconController.shared.image`, so they show
    the same icon as the Dock. `applicationIconImage` returns one shared image that AppKit redraws
    in place, which SwiftUI would not notice; do not draw it directly.
  - The macOS 13–15 path (System mode following Light/Dark through
    `AppleInterfaceThemeChangedNotification`) is covered by unit tests only; it has not been run
    on a macOS 13–15 system.
- **Marketing image:** `design/icon/Hashlight-Frost-1024.png` (README, website, listings).
- The brief's suggested bundle identifier `app.hashlight.Hashlight` is not used; the user chose
  `io.github.ib0ndar.hashlight`. Changing it would reset users' settings.

## Settings and rendering invariants

- The app appearance choice (`System`, `Light`, or `Dark`) is applied through
  `NSApplication.appearance`. Do not restore root-level `preferredColorScheme` modifiers: clearing
  `preferredColorScheme(nil)` left the focused Settings content stale until focus changed.
- Light and dark preview theme IDs are persisted independently. The active `ColorScheme` chooses
  which saved palette is passed into `MarkdownTextView`.
- Main and fixed preview fonts are independent. Main font menus contain proportional installed
  families; fixed font menus contain monospaced families. Preserve legacy `fontStyle` migration.
- A preview cache key must include every setting that changes the attributed output: main font,
  fixed font, content width, active theme, and table-column configuration. Page margin and content
  alignment are layout-only.
- In `MarkdownTextView`, a content change for the document already on screen is a reload: it is
  debounced 150ms and keeps the reader's scroll position. Document switches, zoom, style changes,
  and diagram renders rebuild immediately.
- Table category order is matching priority. Matching uses whole header words and the first match
  wins. The `Other` category supplies the unmatched weight; if removed, the fallback is `1.0`.
- Table-category settings are stored as one versioned JSON snapshot. The app persists it to normal
  defaults and the shared preference domain above; the sandboxed Quick Look extension has a
  read-only temporary exception for that domain.
- `MarkdownParser.swift`, `InlineMarkdown.swift`, and `SharedConstants.swift` are compiled into
  both the app and Quick Look targets. Keep code they depend on Foundation-only or add matching
  target membership deliberately.

## Bundled themes and licensing

Hashlight bundles 351 Base16 palettes: 102 light and 249 dark. They come from
`tinted-theming/schemes` revision `50f6e3b93a8f62db9d839f8b79a709c1bbdaac53`.

- Catalog: `Hashlight/Resources/Base16Themes.json`
- Bundled license: `Hashlight/Resources/TintedTheming-LICENSE.txt`
- Project notice: `THIRD_PARTY_NOTICES.md`
- Reproducible importer: `scripts/update-base16-themes.rb`

When updating the catalog, pin and record the new upstream commit, regenerate the JSON with the
script, retain the license/notice, and update count assertions in `PreviewThemeTests.swift` only
after verifying the actual light/dark counts.

## Build and test

Local builds, tests, and DMGs use Xcode 27. Hosted CI (`.github/workflows/ci.yml`, pushes to and
pull requests into `main`) runs on the GA `macos-26` runner image with its default Xcode (26.6,
Swift 6.3.3, macOS 26.5 SDK at the time of writing), so the code has to build and pass its tests
with both toolchains. Local command-line builds and tests must use the repository wrapper, which
selects the installed Xcode, keeps one DerivedData location per checkout, and removes development
Launch Services/Quick Look registrations before and after `xcodebuild`. A normal local validation
is:

```bash
./scripts/xcodebuild-hashlight.sh -configuration Debug test
```

For a release-configuration compile without signing credentials:

```bash
./scripts/xcodebuild-hashlight.sh -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' build
```

Do not pass `-derivedDataPath`, call bare `xcodebuild` for local builds, or invent new
`/tmp/*-derived` roots. The project puts products under the ignored `build/Xcode/` tree; the
wrapper puts the remaining DerivedData under `build/Xcode/DerivedData`. CI may call `xcodebuild`
directly because its VM is disposable.

Count tests from the result bundle, not by grepping the log (parallel test output can interleave
result lines):

```bash
xcrun xcresulttool get test-results summary --path "$(ls -td build/Xcode/DerivedData/Logs/Test/*.xcresult | head -1)"
```

## Development bundle and Quick Look registration hygiene

Xcode 27 synthesizes an unconditional `RegisterWithLaunchServices` task for macOS app products.
Its `LSRegisterURL.xcspec` has no disable option. Deleting an app does not reliably remove its
Launch Services/PlugInKit record, and every copied app can contribute another System Settings
entry. The project contains several layers to contain that behavior:

- Debug builds have their own identities (`io.github.ib0ndar.hashlight.debug` and its
  `.QuickLook` extension), display names ("Hashlight Debug", "Hashlight Quick Look (Debug)"), and
  table-layout preferences domain.
- Debug declares `LSHandlerRank=None`, so it does not compete with an installed release as a
  Markdown document handler.
- `scripts/manage-dev-registrations.sh` audits or unregisters Hashlight records without deleting
  files. It only ever touches Hashlight's own bundle IDs.
- `scripts/xcodebuild-hashlight.sh` unregisters stale development copies before a build and
  unregisters the resulting copy on exit, including failed/interrupted builds where the shell
  receives EXIT.
- `scripts/build-dmg.sh` uses the wrapper and performs a final unregister on exit.
- Spotlight can re-register a freshly built app after the wrapper's cleanup; check with `status`
  when you finish.

Useful commands:

```bash
# Audit only; no mutation
./scripts/manage-dev-registrations.sh status

# Unregister every non-installed Hashlight development copy; deletes nothing
./scripts/manage-dev-registrations.sh unregister

# Intentionally leave exactly the current Debug extension registered for Finder testing
HASHLIGHT_KEEP_REGISTRATION=1 ./scripts/xcodebuild-hashlight.sh -configuration Debug build

# Mandatory after intentional Quick Look testing
./scripts/manage-dev-registrations.sh unregister
```

Before deleting a generated build directory, removing/archiving a worktree, or abandoning a test
checkout, run `manage-dev-registrations.sh unregister` first. Never delete a source checkout as a
Quick Look cleanup measure. The cleanup tool skips `/Applications` and `/System` by default and
does not delete apps, source, worktrees, DMGs, build directories, or Trash contents. Do not use
`--include-installed` unless the user explicitly wants the installed app unregistered.

With zMD or zMD Viewer also installed, Finder uses only one Markdown Quick Look extension at a
time; the user picks it in System Settings → General → Login Items & Extensions → Quick Look.

## Finder automation safety

When using GUI, Accessibility, or AppleScript automation with Finder, never resize, move, or zoom
any Finder window, never set its bounds, and never change its view mode, toolbar, or status bar.
This includes windows the automation opens itself.

This user's Mac has "Prefer tabs when opening documents: Always" (`AppleWindowTabbingMode =
always`). Finder therefore opens a disk or folder as a tab in the user's existing window, so a
change aimed at a "new" window lands on the user's window. Preserve every Finder window's exact
geometry. If a task truly requires Finder window changes, stop and ask the user first.

`build-dmg.sh` once laid out the disk image by scripting Finder, which moved the user's own Finder
window (zMD, 2026-09-29). It now uses `dmgbuild`, which writes the layout into the image's
`.DS_Store` without Finder. Never reintroduce Finder scripting in it.

Before committing, also run `git diff --check`, validate the project with `plutil -lint
Hashlight.xcodeproj/project.pbxproj`, validate the theme JSON, and run `ruby -c` on the theme
importer. Rendering changes require a manual preview check; export/parser changes also require an
export spot-check. Do not erase unrelated work or generated user files.

## Versions, DMGs, and releases

No Hashlight release has been published and no version tag exists yet. Before the first release,
confirm the version and the release process with the user; never reuse, move, or delete a
published tag.

The owner has no Apple Developer Program membership, so Developer ID signing and notarization are
out of scope: do not plan or propose that work, and never claim an artifact is signed or
notarized. Create the ad-hoc signed DMG with:

```bash
./scripts/build-dmg.sh
```

The script builds Release with ad-hoc signing, generates the background image, and lays out the
image with `dmgbuild`. It installs `dmgbuild` at pinned versions into the ignored
`build/dmg-venv`, which needs network access the first time; the settings live in
`scripts/dmg-settings.py`. It never opens Finder. This produces `build/Hashlight.dmg`. Before
publishing one, verify:

- app and embedded Quick Look versions match the intended release;
- the binary architectures match the release claim (`lipo -archs`);
- the Base16 catalog and license are inside the app bundle;
- the DMG mounts with `hdiutil attach -nobrowse`, contains `Hashlight.app`, and launches using the
  documented macOS unsigned-app flow;
- the image's `.DS_Store` holds the layout (check it with `ds_store` from `build/dmg-venv`);
- SHA-256 and file size are recorded.

A release is an annotated `vX.Y.Z` tag on `main`, pushed atomically with the branch
(`git push --atomic origin main refs/tags/vX.Y.Z`), and a GitHub release in `ib0ndar/Hashlight`
whose notes say the build is ad-hoc signed and not notarized. Verify it with `gh release view`.

## Known issues

- In the dark theme, KaTeX math images have a white background. On macOS 26.7.1 `WKWebView` does
  not respond to `setDrawsBackground:` (it responds to `_setDrawsBackground:`), so
  `WebRenderer.configureTransparentBackground` leaves the web view opaque. Inherited from zMD.
