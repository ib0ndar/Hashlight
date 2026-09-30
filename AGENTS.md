# zMD agent guide

This file is the repository-specific source of truth for coding agents working on zMD. Read it
before changing code, choosing a version number, creating a tag, or pushing a release.

## The `viewer` branch: zMD Viewer

This checkout is on the `viewer` branch if `git branch --show-current` says so. That branch is a
separate, read-only product line created from `master` at `c57f9b5` (the v2.12.3 line); the plan
is `plans/viewer-001-extract-viewer.md`. On it, the rules below override this guide's release
workflow and app identity. Everything else, including the remotes, the build wrapper, and
Finder safety, still applies.

- **Identity.** The product is "zMD Viewer" (`zMD Viewer.app`, display name "zMD Viewer Debug" in
  Debug). Bundle IDs are `com.zmd.viewer` and `com.zmd.viewer.debug`; the Quick Look extension is
  `com.zmd.viewer.QuickLook` / `com.zmd.viewer.debug.QuickLook`, and its table-layout preferences
  domain is `com.zmd.viewer.table-column-layout` / `com.zmd.viewer.debug.table-column-layout`
  with matching entitlements. The document role is Viewer. The Xcode target, scheme, and Swift
  module stay `zMD` (`PRODUCT_NAME = "zMD Viewer"`, `PRODUCT_MODULE_NAME = zMD`), so `-scheme zMD`
  and `@testable import zMD` are unchanged. The icon is zMD's.
- **Version.** All four `MARKETING_VERSION` values are 1.0.0 and change together.
- **Read-only.** Nothing may write to a user's Markdown file. There is no source editor, split
  view, saving, New File, Rename/Move, find & replace, or clickable task checkbox, and no
  ask-before-close flow: closing a tab or the window and quitting are immediate. An external
  change reloads the tab silently and keeps its scroll position; a deleted file still asks
  before its tab closes. Find searches the rendered preview only.
- **No releases, no updater.** Never create `vX.Y.Z` tags or GitHub releases from this branch,
  and do not add an updater. `./scripts/build-dmg.sh` builds `build/zMD-Viewer.dmg` for a local
  install only.
- **Never merge `viewer` into `master`.** Push the branch to `origin` only when the user asks.
- **Settings.** The viewer has its own defaults domain and starts with default settings; it
  imports nothing from zMD.
- **Registrations.** On this branch `manage-dev-registrations.sh` and the wrapper handle only the
  `com.zmd.viewer*` identities. They never touch zMD's `com.zmd.app*` records; clean those with
  the script from a `master` checkout.
- **Next to zMD.** zMD and zMD Viewer install side by side. Both claim Markdown documents, and
  Finder uses only one of their Quick Look extensions at a time; the user picks it in System
  Settings → General → Login Items & Extensions → Quick Look.
- **CI.** This branch's `.github/workflows/ci.yml` also triggers on pushes to `viewer` and on
  pull requests into it (GitHub reads a push's workflow from the pushed commit, so `master`'s
  copy is unaffected). A manual run works too: `gh workflow run ci.yml --repo ib0ndar/zMD --ref
  viewer`. Hosted CI uses the runner's default Xcode (26.6 at the time of writing), not Xcode 27,
  so still run the local checks below before committing.

## Repository identity and remotes

- The user's authoritative repository is **https://github.com/ib0ndar/zMD**.
- `origin` must point to `https://github.com/ib0ndar/zMD.git`. Push branches, tags, release
  commits, and GitHub releases only to this repository.
- The original project is **https://github.com/umzcio/zMD**. Configure it as `upstream` for
  read-only comparison and updates; do not push there unless the user explicitly says to.
- Upstream PR [umzcio/zMD#6](https://github.com/umzcio/zMD/pull/6) ("Fix single-window
  lifecycle", from `ib0ndar:fix/single-window-lifecycle`) is intentionally left open. Do not
  modify, close, or raise it unless the user asks.
- The expected local checkout is `/Users/ivan/git/zMD`.
- The authenticated GitHub account for the authoritative fork is `ib0ndar`.

Verify this before any remote write:

```bash
git remote -v
gh repo view ib0ndar/zMD --json nameWithOwner,defaultBranchRef,viewerPermission,url
```

`viewerPermission` must allow the requested write. A 403 against `umzcio/zMD` is not a cue to
request access or push elsewhere; it means the wrong repository was targeted.

All product-facing repository links must also use the authoritative fork. This includes README
download/issues links, the About/update link in `zMDApp.swift`, and `UpdateManager`'s GitHub API
owner. Otherwise a build from this fork checks the upstream project's releases instead of its own.

## Release history is not the same as `master`

Do not assume the highest version or released code is at the tip of `master`. This fork has made
releases from feature branches and explicit commits:

- `v2.9.0` is the shared upstream base at `a4f6ff8`.
- `v2.10.0` was released from `ivan/ui-rework` at `5c6e87d`.
- `v2.11.0` was released from commit `43ce41b` on
  `ivan/editable-table-categories`; it includes the 2.10 UI/window/layout work and editable
  Markdown table-column categories.
- The theme/font consolidation following those releases is version `2.12.0` and must contain the
  full `v2.11.0` line, not merely the older `master` tip. It was released from `master` at
  `77de482`.
- `v2.12.1` is a patch release from `master` that fixes Mermaid and KaTeX rendering in the preview
  (see Plan 025).
- `v2.12.2` is a patch release from `master` covering the Finder-free DMG build, line numbers, the
  View menu, the outline animation, and Reduce Motion fades (see Plan 026).
- `v2.12.3` is a patch release from `master` that lets ad-hoc signed releases auto-update by
  trusting GitHub's published SHA-256 (see Plan 027).

Before choosing any future version or base, always refresh and inspect both refs and GitHub
releases:

```bash
git fetch --prune --tags origin
git fetch --prune --no-tags upstream
gh release list --repo ib0ndar/zMD --limit 20
git log --graph --oneline --decorate --all --simplify-by-decoration --max-count=40
```

Also inspect the latest release's `targetCommitish`, body, and assets with `gh release view`.
Never reuse, move, or delete a published version tag. New features after 2.11.0 require at least
2.12.0.

There are four `MARKETING_VERSION` values in `zMD.xcodeproj/project.pbxproj`: Debug and Release
for both the app and Quick Look extension. Change all four together and verify the built app and
embedded extension report the same version.

## What the project is

zMD is a native macOS 13+ Markdown editor and viewer written in Swift 6 with SwiftUI and AppKit.
The preview is an `NSTextView`, not a browser. A small headless `WKWebView` is used only for
Mermaid, KaTeX, and HTML fragments. There are no SwiftPM, CocoaPods, or Carthage dependencies.

Main components:

- `zMD/zMDApp.swift`: app/scenes, commands, window lifecycle, app-wide appearance.
- `zMD/DocumentManager.swift`: documents, tabs, dirty state, save/load, find, and close flow.
- `zMD/SettingsManager.swift`: persisted app, preview, layout, editor, and table settings.
- `zMD/MarkdownParser.swift`: block parser and HTML generation shared with Quick Look.
- `zMD/InlineMarkdown.swift`: shared inline tokenizer.
- `zMD/MarkdownTextView.swift`: native rendered preview.
- `zMD/SyntaxHighlighter.swift`: preview code highlighting.
- `zMD/WebRenderer.swift`: Mermaid, math, and HTML fragment rendering.
- `zMD/PreviewTheme.swift`: bundled Base16 theme loading and semantic color mapping.
- `zMD/PreviewFont.swift`: installed proportional and monospaced preview-font catalogs.
- `zMD/SharedConstants.swift`: constants and table-column configuration/layout shared by the app
  and Quick Look extension.
- `zMDQuickLook/`: sandboxed Finder Quick Look extension.
- `zMDTests/`: XCTest target covering parsing, rendering behavior, settings, lifecycle, Quick
  Look, themes, fonts, and table layout.

Read `CLAUDE.md` for the longer architecture guide and `CONTRIBUTING.md` for code conventions.

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
- Table category order is matching priority. Matching uses whole header words and the first match
  wins. The `Other` category supplies the unmatched weight; if removed, the fallback is `1.0`.
- Table-category settings are stored as one versioned JSON snapshot. The app persists it to normal
  defaults and the `com.zmd.table-column-layout` shared preference domain; the sandboxed Quick
  Look extension has a read-only temporary exception for that domain.
- `MarkdownParser.swift`, `InlineMarkdown.swift`, and `SharedConstants.swift` are compiled into
  both the app and Quick Look targets. Keep code they depend on Foundation-only or add matching
  target membership deliberately.

## Bundled themes and licensing

zMD bundles 351 Base16 palettes: 102 light and 249 dark. They come from
`tinted-theming/schemes` revision `50f6e3b93a8f62db9d839f8b79a709c1bbdaac53`.

- Catalog: `zMD/Resources/Base16Themes.json`
- Bundled license: `zMD/Resources/TintedTheming-LICENSE.txt`
- Project notice: `THIRD_PARTY_NOTICES.md`
- Reproducible importer: `scripts/update-base16-themes.rb`

When updating the catalog, pin and record the new upstream commit, regenerate the JSON with the
script, retain the license/notice, and update count assertions in `PreviewThemeTests.swift` only
after verifying the actual light/dark counts.

## Build and test

Local builds, tests, and release DMGs use Xcode 27. Hosted CI (`.github/workflows/ci.yml`) runs on
the GA `macos-26` runner image with its default Xcode, which was Xcode 26.6 (Swift 6.3.3, macOS
26.5 SDK) on image 20260907.0351.1, so the code has to build and pass its tests with both
toolchains. Local command-line builds and tests must use the repository wrapper, which selects the
installed Xcode, keeps one DerivedData location per checkout, and removes development Launch
Services/Quick Look registrations before and after `xcodebuild`. A normal local validation is:

```bash
./scripts/xcodebuild-zmd.sh -configuration Debug test
```

For a release-configuration compile without signing credentials:

```bash
./scripts/xcodebuild-zmd.sh -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' build
```

Do not pass `-derivedDataPath`, call bare `xcodebuild` for local zMD app builds, or invent new
`/tmp/zMD-*-derived` roots. The project puts products under the ignored `build/Xcode/` tree; the
wrapper puts the remaining DerivedData under `build/Xcode/DerivedData`. CI may call `xcodebuild`
directly because its VM is disposable.

## Development bundle and Quick Look registration hygiene

Xcode 27 synthesizes an unconditional `RegisterWithLaunchServices` task for macOS app products.
Its `LSRegisterURL.xcspec` has no disable option. Deleting an app does not reliably remove its
Launch Services/PlugInKit record, and every copied app can contribute another System Settings
entry. The project contains several layers to contain that behavior:

- Debug app identity: `com.zmd.app.debug`, displayed as `zMD Debug`.
- Debug Quick Look identity: `com.zmd.app.debug.QuickLook`, displayed as
  `zMD Quick Look (Debug)`.
- Release identities remain `com.zmd.app` and `com.zmd.app.QuickLook`.
- Debug uses a separate table-layout preferences domain and entitlement:
  `com.zmd.debug.table-column-layout`.
- Debug declares `LSHandlerRank=None`, so it does not compete with the installed release as a
  Markdown document handler.
- `scripts/manage-dev-registrations.sh` audits or unregisters zMD records without deleting files.
- `scripts/xcodebuild-zmd.sh` unregisters stale development copies before a build and unregisters
  the resulting copy on exit, including failed/interrupted builds where the shell receives EXIT.
- `scripts/build-dmg.sh` uses the wrapper and performs a final unregister on exit.

Useful commands:

```bash
# Audit only; no mutation
./scripts/manage-dev-registrations.sh status

# Unregister every non-installed zMD development copy; deletes nothing
./scripts/manage-dev-registrations.sh unregister

# Intentionally leave exactly the current Debug extension registered for Finder testing
ZMD_KEEP_REGISTRATION=1 ./scripts/xcodebuild-zmd.sh -configuration Debug build

# Mandatory after intentional Quick Look testing
./scripts/manage-dev-registrations.sh unregister
```

Before deleting a generated build directory, removing/archiving a worktree, or abandoning a test
checkout, run `manage-dev-registrations.sh unregister` first. Never delete a source checkout as a
Quick Look cleanup measure. The cleanup tool skips `/Applications` and `/System` by default and
does not delete apps, source, worktrees, DMGs, build directories, or Trash contents. Do not use
`--include-installed` unless the user explicitly wants the installed release unregistered.

## Finder automation safety

When using GUI, Accessibility, or AppleScript automation with Finder, never resize, move, or zoom
any Finder window, never set its bounds, and never change its view mode, toolbar, or status bar.
This includes windows the automation opens itself.

This user's Mac has "Prefer tabs when opening documents: Always" (`AppleWindowTabbingMode =
always`). Finder therefore opens a disk or folder as a tab in the user's existing window, so a
change aimed at a "new" window lands on the user's window. Preserve every Finder window's exact
geometry. If a task truly requires Finder window changes, stop and ask the user first.

`scripts/build-dmg.sh` used to break this rule. Its AppleScript layout step opened the mounted
image in Finder and set the container window's bounds, view, toolbar, and status bar. On
2026-09-29, during the v2.12.1 build, that moved the user's existing Finder window, and the
layout never reached the image. The script now uses `dmgbuild` (Plan 026), which writes the
layout into the image's `.DS_Store` without Finder. Never reintroduce Finder scripting in it.

Before committing, also run `git diff --check`, validate the project with `plutil -lint
zMD.xcodeproj/project.pbxproj`, validate the theme JSON, and run `ruby -c` on the theme importer.
Rendering changes require a manual preview check; export/parser changes also require an export
spot-check. Do not erase unrelated work or generated user files.

## DMG and GitHub release workflow

The fork's releases disclose that their DMGs are not Developer ID signed or notarized. The owner
has no Apple Developer Program membership, so signing and notarization are out of scope: do not
plan or propose that work. This machine has no Developer ID identity and no local notary
configuration. Do not claim an unsigned artifact is signed or notarized.

Create the ad-hoc signed DMG with:

```bash
./scripts/build-dmg.sh
```

The script builds Release with ad-hoc signing, generates the background image, and lays out the
image with `dmgbuild`. It installs `dmgbuild` at pinned versions into the ignored
`build/dmg-venv`, which needs network access the first time; the settings live in
`scripts/dmg-settings.py`. It never opens Finder. This produces `build/zMD.dmg`. Before upload,
verify:

- app and embedded Quick Look versions match the intended release;
- the binary architectures match the release claim (`lipo -archs`);
- the Base16 catalog and license are inside the app bundle;
- the DMG mounts with `hdiutil attach -nobrowse`, contains `zMD.app`, and launches using the
  documented macOS unsigned-app flow;
- the image's `.DS_Store` holds the layout (check it with `ds_store` from `build/dmg-venv`);
- SHA-256 and file size are recorded.

Then commit, make an annotated tag, and atomically push the branch and tag to the user's fork:

```bash
git push --atomic origin master refs/tags/vX.Y.Z
```

Publish the GitHub release only after the DMG is ready, using `--repo ib0ndar/zMD`, and state in
the release notes that the build is ad-hoc signed and not notarized. Verify the resulting release and asset
with `gh release view`. The app updater expects a release asset named exactly `zMD.dmg`; publishing
a “latest” release without that asset breaks in-app updates. Since 2.12.3, the updater installs
only a DMG that matches the SHA-256 `digest` GitHub reports for that asset. It then requires the
bundle identifier, a valid signature, and the release version. Confirm the asset's digest in `gh
release view` equals the local DMG's SHA-256 before announcing a release.
