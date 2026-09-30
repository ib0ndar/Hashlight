# Plan 002: import the official Hashlight icon

- **Status**: DONE
- **Created**: 2026-09-30
- **Input**: `Hashlight-handover.zip` (brand and icon package prepared 2026-09-30), now in `design/`

## Decision (user, 2026-09-30)

The package's icons are the official Hashlight icons. Import them and follow the package's
`README.md`, which points to `BRIEF.md` for the integration steps.

## What was done

1. **Package.** The whole package is in `design/`, byte for byte (README, BRIEF, manifest,
   `icon/`, `naming/`, `tools/`), so the brief's and manifest's relative paths stay valid.
2. **Brief §4.1 step 1.** `design/icon/Hashlight.icon` is copied to `Hashlight/Hashlight.icon`,
   beside `Assets.xcassets`, and added to the app target's Resources phase as a
   `folder.iconcomposer.icon` reference. The placeholder `AppIcon` set is gone from the catalog.
3. **Step 2.** `ASSETCATALOG_COMPILER_APPICON_NAME = Hashlight` in Debug and Release.
4. **Info.plist.** The hand-written `CFBundleIconFile`/`CFBundleIconName` (`AppIcon`) are removed;
   the asset compiler now writes both as `Hashlight`. The Markdown document type's icon points at
   `Hashlight`.
5. **Docs.** README shows `design/icon/Hashlight-Frost-1024.png` (the brief's canonical marketing
   image) and gains an "Icon and Design" section; the layout fixture uses the same image;
   `AGENTS.md` has an "App icon and design assets" section; `CLAUDE.md` lists the icon;
   `.gitignore` ignores the tools' regeneration output.

## Not done, and why

- **Step 3 (`CFBundleIconFile` = `Hashlight-Frost.icns` for macOS 13–15).** With an Icon Composer
  icon, current Xcode puts a flattened fallback into `Assets.car` under the icon name, and macOS
  uses that on every version; Apple told developers this is by design. A plain `CFBundleIconFile`
  therefore would not bring back the hand-tuned 16/32 px renditions. The workarounds people
  report need Xcode 26.0.1 or a checked-in prebuilt `Assets.car`, and this Mac cannot verify the
  result on macOS 15. [`002-small-icon-comparison.png`](002-small-icon-comparison.png) compares
  them, upscaled: top row Xcode's generated fallback, bottom row the designer's Frost `.icns`, at
  16 px, 32 px, 16 pt @2x, and 128 px. The fallback has less contrast and no 32 px @1x rendition.
- **Brief §4.2 optional Dock-icon preference for macOS 13–15.** Not done here; it is the next
  task, planned in [`003-dock-icon-preference.md`](003-dock-icon-preference.md).
- **Brief suggestions outside the icon:** the amber accent colour for UI (the app keeps the
  system accent) and the bundle identifier `app.hashlight.Hashlight` (the user chose
  `io.github.ib0ndar.hashlight`).

## Verification

- Clean Debug build: `Assets.car` holds the layered icon (Light, Dark, and Tintable stacks) and
  the flattened multi-size fallback; `Hashlight.icns` is generated; the built `Info.plist` has
  `CFBundleIconFile` and `CFBundleIconName` = `Hashlight`; no leftover `AppIcon.icns`.
- macOS 26.7.1: `NSWorkspace.icon(forFile:)` for the built app renders the Frost Liquid Glass
  icon at 256–16 px; the welcome screen shows it in both the app's light and dark appearance.
- `design/` and `Hashlight/Hashlight.icon` compared with the package using `diff -r`: identical.
- Debug tests, Release compile, `plutil -lint`, `git diff --check` (see the commit).
