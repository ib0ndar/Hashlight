# Plan 003: Dock-icon preference

- **Status**: DONE (verified on macOS 26.7.1; the macOS 13–15 path is covered by unit tests only)
- **Created**: 2026-09-30
- **Source**: `design/BRIEF.md` §4.2 ("Adaptive icon — decided behaviour")
- **Requested by**: the owner, 2026-09-30 ("I'd like to implement this in the future")

## Goal as planned

The brief's §4.2 asks for a macOS 13–15-only preference "Dock icon: Frost / Ember / Match
appearance", default Frost, hidden on macOS 26. It may change only the running app's Dock tile and
⌘-Tab icon (`NSApp.applicationIconImage`), never the bundle's icon on disk.

## Decisions (owner, 2026-09-30)

The plan's three questions, answered:

1. **Match Appearance** follows the **system's** Light/Dark setting, not the app's own Appearance
   override, and Settings must let the user pick the icon they want regardless.
2. **Welcome screen and About** show the chosen Dock icon.
3. **No macOS 13–15 machine.** Compatibility with 13–15 "is not important at the moment"; skip
   verifying it there.

Because the feature would otherwise never be visible on this Mac (macOS 26), the owner then chose
to offer the setting **on every macOS version, including 26**, overriding brief §4.2's "hide the
preference on macOS 26". The result:

- **Dock icon: System / Frost / Ember**, default **System** (the brief's default was Frost).
- **System** leaves the icon to macOS. On macOS 26 that is System Settings → Appearance → Icon &
  widget style (Default, Dark, Clear, Tinted). On macOS 13–15 it is Frost in Light mode and Ember
  in Dark mode (the brief's "Match appearance", following the system).
- **Frost** and **Ember** always show that icon while Hashlight runs, on every version.

## What was done

1. **Resources.** `design/icon/Hashlight-Frost.icns` and `Hashlight-Ember.icns` are copied byte for
   byte to `Hashlight/DockIcon-Frost.icns` and `Hashlight/DockIcon-Ember.icns` and added to the
   app target's Resources phase (file type `image.icns`). Each has all ten sizes, 16 to 512 @2x.
2. **Setting.** `SettingsManager.DockIconMode` (`system`, `frost`, `ember`; raw values "System",
   "Frost", "Ember"), `DefaultsKeys.dockIconMode = "dockIconMode"`, and
   `@Published var dockIconMode`, persisted in `didSet`; an unknown or missing value loads as
   System.
3. **Controller.** New `Hashlight/DockIconController.swift`:
   - `imageName(for:systemStylesAppIcon:systemIsDark:)` is the pure choice (nil = leave it to
     macOS) and is unit-tested.
   - `apply(_:)` sets `NSApp.applicationIconImage` to the bundled image, or to nil (the bundle
     icon) for System on macOS 26.
   - On macOS 13–15, System mode reads `AppleInterfaceStyle` from the global defaults domain and
     re-applies on `AppleInterfaceThemeChangedNotification` (a distributed notification). That
     way it ignores the app's own `NSApp.appearance` override, which `effectiveAppearance` would
     include.
   - `start(observing:)` subscribes to `settings.$dockIconMode`, so the saved mode applies at
     launch and every change applies at once. `AppDelegate.applicationDidFinishLaunching` calls
     it after `ApplicationAppearance.apply`.
   - It publishes `image` for the welcome screen and About. Reading `applicationIconImage` back
     returns one shared `NSImage` that AppKit redraws in place (a single snapshot rep), so
     SwiftUI would not see a change. The controller publishes the bundled image it loaded, or a
     copy of the app icon for System.
4. **UI.** Settings → Appearance has a new **Icon** section with a segmented "Dock icon" picker and
   a two-line footnote that differs between macOS 26 and 13–15. `WelcomeView` and `AboutTab`
   observe `DockIconController.shared`.
5. **Project.** The Swift file, the two `.icns`, and `HashlightTests/DockIconTests.swift` are added
   to `project.pbxproj` by hand.
6. **Docs.** README (features, Icon and Design), in-app Help (Customizing Appearance → Dock Icon),
   `AGENTS.md` (app icon section; the decision to override brief §4.2), `CLAUDE.md`, and
   `HANDOVER.md`.

## Verification

- `./scripts/xcodebuild-hashlight.sh -configuration Debug test`: 104 of 104 tests pass (counted
  from the result bundle; 98 before plus 6 new in `DockIconTests`), no compiler warnings.
- Release compile (unsigned): succeeds, no warnings.
- Hosted CI (`macos-26`, Xcode 26.6): build and tests pass for `64bb58a` (run 36719847957).
- The built app's `DockIcon-*.icns` are identical to `design/icon/` (`cmp`). `plutil -lint` of the
  project passes.
- Hands-on on macOS 26.7.1 (Debug build; screenshots in the ignored `artifacts/screens/`, e.g.
  `plan003-dock-strip.png`):
  - System: the Dock shows the system's Liquid Glass Frost icon.
  - Ember and Frost: the Dock tile changes at once. The welcome screen and About switch
    immediately, without a relaunch.
  - Ember is applied again after quitting and relaunching.
  - Back to System: the system icon returns.
  - System with the app's Appearance set to Dark: the icon stays the system's Frost (it follows
    the system, not the app).
  - The Settings footnote wraps to two lines.
- Not checked: the ⌘-Tab switcher (it uses the same `applicationIconImage`), macOS 13–15 (no
  machine), and System mode under a non-default icon style on macOS 26. The last was not checked
  because changing the owner's global icon style was out of scope. In that case the welcome screen
  and About draw the app icon AppKit reports, which may be the default (Frost) rendition rather
  than the styled one the Dock shows.

## Notes and left over

- **Settings height.** The Appearance tab was already taller than its fixed 480 × 620 pt window
  on macOS 26 (content about 770 pt; the grouped form scrolls, and Zoom and Advanced were already
  below the fold). The new section adds about 145 pt more, so now the end of Layout needs
  scrolling too. The window size was left unchanged. The comment in
  `SettingsView` saying the height fits the tallest tab is out of date on macOS 26.
- **macOS 13–15** remain unverified by hand. If a machine becomes available, check each mode, a
  live Light/Dark switch in System mode (including Auto), relaunch, and that Finder keeps Frost.
