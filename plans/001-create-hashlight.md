# Plan 001: create Hashlight from zMD Viewer

- **Status**: DONE
- **Created**: 2026-09-30
- **Source**: `ib0ndar/zMD@7cf0357` (the `viewer` branch: zMD Viewer 1.0.0)
- **Repository**: https://github.com/ib0ndar/Hashlight

## Decisions (user, 2026-09-30)

The user chose to continue zMD Viewer as an independent project called **Hashlight**:

- **Visibility:** public repository `ib0ndar/Hashlight`, default branch `main`.
- **History:** a fresh start. The first commit's tree is identical to `ib0ndar/zMD@7cf0357`; zMD's
  history, releases, and planning documents stay in `ib0ndar/zMD`. It is a standalone
  repository, not a GitHub fork.
- **Identity:** bundle IDs under `io.github.ib0ndar.hashlight` (a namespace the owner controls).
- **Rename depth:** full. No "zMD" is left except in attribution and notes about running next to
  zMD.

## What was done

1. **Import** (`5210c6e`): the viewer tree, byte for byte.
2. **Rename** (`c16a2ad`):
   - Project `Hashlight.xcodeproj`, targets `Hashlight`, `HashlightQuickLook`, `HashlightTests`,
     scheme and module `Hashlight`, and matching folders, entitlements, and `HASHLIGHT_*` build
     settings.
   - Bundle IDs `io.github.ib0ndar.hashlight[.debug]`, extension `….QuickLook`, and table-layout
     domain `io.github.ib0ndar.hashlight[.debug].table-column-layout`. Version 1.0.0, role Viewer.
   - Internal names that said zMD: attribute keys, queue label, math placeholders, table CSS class,
     system font IDs, and test fixtures' temporary names.
   - Scripts: `xcodebuild-hashlight.sh` (`HASHLIGHT_KEEP_REGISTRATION`), registration management
     for Hashlight's IDs only, and `build/Hashlight.dmg`. CI builds and tests `main`.
   - Settings → About credits "Based on zMD by Zachary Rossmiller".
3. **Icon** (`1cd3d4d`): the icon said "ZMD", so it became a generated placeholder (a glowing
   "#" on a dark tile). zMD's logo and screenshot were removed; the layout fixture uses the icon
   as its sample image.
4. **Docs** (this commit): new README, `AGENTS.md`, `CLAUDE.md`, and `CONTRIBUTING.md` for
   Hashlight; `LICENSE.md` keeps Zachary Rossmiller's MIT notice and adds Ivan Bondar's line;
   `THIRD_PARTY_NOTICES.md` records the zMD origin. zMD's `plans/`, `animation-plans/`, and
   `docs/superpowers/` were removed and remain in `ib0ndar/zMD`.

## Verification

- `./scripts/xcodebuild-hashlight.sh -configuration Debug test`: 98 of 98 tests pass (counted from
  the result bundle), no warnings.
- Release compile (unsigned): no warnings.
- Built bundles: Debug `io.github.ib0ndar.hashlight.debug` "Hashlight Debug", Release
  `io.github.ib0ndar.hashlight` "Hashlight", executable `Hashlight`, 1.0.0, role Viewer, ranks
  None/Default. Extensions `….debug.QuickLook` / `….QuickLook` 1.0.0, principal class
  `HashlightQuickLook.PreviewProvider`; the Debug extension's entitlement names
  `io.github.ib0ndar.hashlight.debug.table-column-layout`, and the Release binaries reference
  `io.github.ib0ndar.hashlight.table-column-layout`.
- `plutil -lint`, `git diff --check`, theme JSON, `ruby -c`, `bash -n` on the scripts, and YAML
  parsing of the workflow and Dependabot config.
- Development registrations cleaned with `manage-dev-registrations.sh unregister`.

## Open items

- ~~A designed app icon to replace the placeholder.~~ Done in plan 002 (official icon).
- The Release configuration still carries zMD's original signing settings (`Developer ID
  Application`, team `5JJ6G6A84S`); local compiles and `build-dmg.sh` override them.
- In the dark theme, KaTeX images have a white background (inherited from zMD; see `AGENTS.md`).
- No release process has been decided yet; the first release needs the user's decision.
