# Plan 003: Dock-icon preference for macOS 13–15

- **Status**: TODO — the next task
- **Created**: 2026-09-30
- **Source**: `design/BRIEF.md` §4.2 ("Adaptive icon — decided behaviour")
- **Requested by**: the owner, 2026-09-30 ("I'd like to implement this in the future")

## Goal

On macOS 13, 14, and 15 only, add a preference **"Dock icon: Frost / Ember / Match appearance"**,
default **Frost**. It changes the running app's Dock tile and ⌘-Tab icon. Nothing else changes:
the bundle icon (Finder, Launchpad, the app while not running) stays Frost.

Rules from the brief:

- Change only `NSApp.applicationIconImage`. **Never rewrite the bundle's icon on disk** (breaks
  code signing and updates).
- **macOS 26+:** do nothing and **hide the preference**. The system already switches the icon
  (System Settings → Appearance → Icon & widget style); do not add an app-level toggle there.

## Background

- The app icon is `Hashlight/Hashlight.icon` (Icon Composer). On macOS 13–15, Finder and the Dock
  show Xcode's flattened Frost fallback from `Assets.car` (see plan 002). Setting
  `NSApp.applicationIconImage` from the designer's `.icns` files also brings their hand-tuned
  16/32 px renditions to the Dock tile and ⌘-Tab while the app runs, including in Frost mode.
  [`002-small-icon-comparison.png`](002-small-icon-comparison.png) shows the difference.
- `design/icon/Hashlight-Frost.icns` and `Hashlight-Ember.icns` each contain all ten sizes (16 to
  512 @2x). The 1024 px PNGs use the padded macOS grid (opaque area about 78–945 × 91–957 px), so
  they would also work as Dock images, but they lack the small renditions.
- `WelcomeView` and Settings → About draw `NSApp.applicationIconImage`, so they will follow
  whatever the Dock shows.

## Design

1. **Resources.** Copy the two `.icns` files from `design/icon/` into the app target as
   `Hashlight/DockIcon-Frost.icns` and `Hashlight/DockIcon-Ember.icns` (Resources phase). Do not
   name either `Hashlight.icns`: the asset compiler already writes that file. Keep them identical
   to `design/` (`cmp` after any change). Load them with
   `Bundle.main.image(forResource: "DockIcon-Frost")`.
2. **Setting.** In `SettingsManager.swift`, add
   `enum DockIconMode: String, CaseIterable { case frost, ember, matchAppearance }` with display
   names "Frost", "Ember", "Match Appearance"; a `DefaultsKeys.dockIconMode = "dockIconMode"`; and
   `@Published var dockIconMode: DockIconMode` (default `.frost`), persisted in `didSet` like the
   other settings.
3. **Controller.** New `Hashlight/DockIconController.swift`, following the brief's snippet:
   - `apply(_ mode:)` returns immediately on macOS 26+ (`if #available(macOS 26, *)`), leaving
     `applicationIconImage` untouched.
   - `.frost` and `.ember` set the matching image. `.matchAppearance` observes
     `NSApp.effectiveAppearance` (KVO, `.initial` and `.new`) and picks Ember for dark.
   - Keep the image-name choice in a pure function, `iconName(for:isDark:)`, so it can be
     unit-tested.
   - Setting `NSApp.applicationIconImage = nil` restores the bundle icon.
   - Adding the file means editing `Hashlight.xcodeproj/project.pbxproj` by hand: build file, file
     reference, group child, and the app target's Sources phase. Do the same for the two `.icns`
     (Resources phase).
4. **Wiring.**
   - Apply the saved mode in `AppDelegate.applicationDidFinishLaunching`, after
     `ApplicationAppearance.apply`, so `effectiveAppearance` already reflects the app's own
     Light/Dark choice.
   - Re-apply whenever `dockIconMode` changes.
5. **UI.** Settings → Appearance: a "Dock icon" segmented picker (Frost / Ember / Match
   Appearance). Show it only on macOS 13–15 (`if #unavailable(macOS 26.0)`), with a footnote such as
   "Changes the Dock and app switcher icon while Hashlight runs. Finder keeps the Frost icon."
   The Settings window is fixed at 480 × 620 pt and the Appearance tab is already the tallest.
   Check for clipping, and raise the height only when the row is shown.
6. **Docs.** README (features), in-app Help (Customizing Appearance), `AGENTS.md` (the "App icon
   and design assets" section says this is not implemented; update it), and this plan's execution
   notes.

## Questions for the owner before starting

1. **Match Appearance:** should it follow the app's appearance (Settings → Appearance: System /
   Light / Dark; `NSApp.effectiveAppearance` includes that override) or always the system's? The
   design above follows the app.
2. **Welcome screen and About:** should they follow the Dock choice (automatic, since they draw
   `applicationIconImage`), or always show the Frost bundle icon?
3. **Verification on macOS 13–15:** is there a Mac or VM running macOS 15 (or 13/14)? This Mac runs
   macOS 26.7.1, where the feature is hidden by design.

## Tests

- Unit: `iconName(for:isDark:)` for every mode and both appearances; the `dockIconMode` default
  (Frost) and persistence round trip; on macOS 26 (the local and CI test hosts), `apply` is a no-op.
- The suite must still pass on hosted CI (Xcode 26.6) and locally (Xcode 27). Count tests from the
  result bundle (see `AGENTS.md`).

## Verification (hands-on)

On macOS 13–15:

- each mode changes the Dock tile and ⌘-Tab icon at once, with no relaunch;
- Match Appearance follows a live Light/Dark switch;
- the chosen mode is applied again after relaunch;
- the Finder icon stays Frost;
- quitting leaves the Dock showing the bundle icon.

On macOS 26: the row is hidden and the Dock shows the system-styled icon. Finish with
`./scripts/manage-dev-registrations.sh unregister`.

## Done when

The preference works as above on a real macOS 13–15 system; all tests pass; the docs are updated;
and this plan's status is DONE with execution notes.
