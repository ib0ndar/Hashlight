# Plan 025: Post-v2.12 release validation and repository handover

- **Status**: DONE — the first hosted CI run is green, and every P1 smoke test passes. The first
  L1 failure was reclassified as an environment limit (locked screen). P2 checks were run on
  2026-09-29 at the user's request, and they found four pre-existing bugs; fixing them needs a
  separate decision (2.12.1).
- **Created**: 2026-09-28 · **Revised**: 2026-09-28 (rev 2, re-verified against `e1c58de`)
- **Remaining scope**: Phase 1 (first hosted CI run) and Phase 2 P1 smoke tests. Everything else
  is deferred; see [Deferred](#deferred-not-part-of-this-pass).
- **Authoritative repository**: <https://github.com/ib0ndar/zMD> (public fork of `umzcio/zMD`)
- **Released version**: `v2.12.0` → `77de482ce8fe349abf33198f4741b0c43ac21427` (annotated tag
  object `c0bae6b`)
- **Current `master`**: `e1c58dea0173350e3bd3c49e3d4fdca750d8a598` (unreleased; development
  tooling only)
- **Release page**: <https://github.com/ib0ndar/zMD/releases/tag/v2.12.0>

> **Executor instructions**: Read the repository-root `AGENTS.md` completely before doing
> anything else. This plan authorizes read-only inspection, local builds and tests through
> `./scripts/xcodebuild-zmd.sh`, and evidence written under `artifacts/plan-025/`. Every other
> write needs the user's explicit approval at execution time, as listed in
> [Authorization gates](#authorization-gates). That includes GitHub settings, pushes, workflow
> re-runs, installing into `/Applications`, and changing preferences or system settings. The
> user works only in the fork: never open pull requests against `umzcio/zMD`. Pull requests
> inside `ib0ndar/zMD` are allowed, but the chosen flow is a direct push to `master`. Never rewrite
> release history, replace the published asset, delete local artifacts, rotate credentials, or
> write to `umzcio/zMD`.

## Goal

1. Produce the first hosted GitHub Actions `CI` run for the post-v2.12 tree, make it green
   without weakening tests, and record it.
2. Run the P1 smoke tests against the published v2.12.0 DMG with unambiguous results: window
   lifecycle and cold launch, appearance/themes/fonts, and tables/Quick Look.

Reproduce and diagnose failures; do not fix application code without separate approval. A
confirmed P1 application bug is a 2.12.1 patch candidate.

## Re-verified state (2026-09-28, about 13:20 +03:00)

Re-check anything that time-sensitive decisions depend on.

### Repository

- `origin` is `ib0ndar/zMD` (viewer permission `ADMIN`, active `gh` account `ib0ndar`).
  `upstream` is `umzcio/zMD` with push disabled. No `gh` default repository is set.
- `master` = `origin/master` = `e1c58de`, 0 ahead/0 behind, clean worktree.
- `e1c58de` ("Isolate development Quick Look registrations") is one commit after `v2.12.0`. It
  adds Debug-only bundle IDs and display names, Debug `LSHandlerRank=None`, the Debug shared
  preferences domain, the build wrapper and registration manager, docs, and this plan. Release
  values are unchanged: `ZMD_DISPLAY_NAME = zMD`, `ZMD_DOCUMENT_HANDLER_RANK = Default`,
  `ZMD_QUICKLOOK_DISPLAY_NAME = "zMD Quick Look"`, and the non-DEBUG shared domain remains
  `com.zmd.table-column-layout`. It does not by itself require a release.
- Other `origin` branches: `ivan/ui-rework` (v2.10.0), `ivan/editable-table-categories`
  (v2.11.0), `fix/single-window-lifecycle` (`2eb8fb7`), and
  `dependabot/github_actions/github-actions-640176b5ab` (`aa88bbd`, `actions/checkout@v4` →
  `@v7`, inherited from upstream at fork time; green on upstream). The fork has no pull requests.
- Upstream PR [umzcio/zMD#6](https://github.com/umzcio/zMD/pull/6) ("Fix single-window
  lifecycle", head `ib0ndar:fix/single-window-lifecycle`) is open. Its upstream CI run is
  `action_required`, which awaits the upstream maintainer. `git range-diff` shows its three commits
  are patch-identical to the fork's `0d40ae0`, `5415636`, and `3b0cdcb`. Any lifecycle bug found
  here therefore also applies to that PR. It was opened from the user's account on 2026-09-27.
  The user now works only in the fork; leave the PR untouched unless the user decides to close
  it.
- GitHub Issues are disabled and `master` has no branch protection. These are policy choices;
  do not change them.

### Release

- v2.12.0 is the latest release. Its single asset `zMD.dmg` is 3,311,650 bytes,
  `sha256:cf938400640fd875a94cfa9764dc80f1099e382238d98c2af3c77913059e1e59`. The notes
  declare macOS 13+, Apple silicon (`arm64`), ad-hoc signing, and no notarization.
- The local `build/zMD.dmg` is **not** the published file: 3,311,660 bytes, SHA-256
  `20f013e109f90a18c1f2a5f196a722c3745955dd421a4784d041ed2d5408d220`, rebuilt at 09:15 local
  after publication. Never upload it, and never use it for smoke tests.
- Verified at release time and not re-checked here: the DMG mounts; the app and extension report
  2.12.0 (1), are `arm64`, pass `codesign --verify`, and contain 351 themes plus the Tinted
  Theming license.

### CI

- `.github/workflows/ci.yml` has one job, `build-and-test`, on `runs-on: macos-26`, with an
  unsigned Debug Build step and Test step. It triggers on `push` and `pull_request` for `master`
  and has no `workflow_dispatch`.
- The fork has **zero** workflow runs, although `ib0ndar` pushed `master` twice:
  2026-09-28T05:28:57Z (`77de482`) and 09:45:43Z (`e1c58de`). Actions is enabled with
  `allowed_actions: all`. Workflow `CI` (id `368797170`) is `active` and was registered at the
  first `master` push. Neither commit message contains a skip-CI marker.
- **Probable root cause** (high confidence; the owner must confirm it visually): GitHub disables
  workflows on new forks until the owner accepts the banner "Workflows aren't being run on this
  forked repository" on the fork's Actions tab. No public API dismisses it, and the logged-out
  Actions page cannot show it.
- The workflow is proven upstream: [umzcio/zMD run
  35418791651](https://github.com/umzcio/zMD/actions/runs/35418791651) on `a4f6ff8` (v2.9.0),
  2026-09-19, succeeded. It used image `macos-26-arm64` 20260907.0351.1,
  `/Applications/Xcode_26.6.app`, and the macOS 26.5 SDK. Build took 64 s; Test took 34 s.
- **Toolchain mismatch**: the `ci.yml` comment "macos-26 ships Xcode 27" and `AGENTS.md`'s
  "Swift 6/Xcode 27-era settings used by CI" are wrong. The GA `macos-26` image defaults to
  Xcode 26.6, while releases and local work use Xcode 27.0 (27A266a). No recorded build of the
  v2.10–v2.12 code and tests added after `a4f6ff8` used Xcode 26.6. Xcode 27 is available only
  on the preview label `xcode-27`, whose base OS has been macOS 27 since 2026-09-16
  ([runner-images #14404](https://github.com/actions/runner-images/issues/14404)). Resolved:
  the first hosted run (see the execution notes) built and tested the post-v2.12 tree with
  Xcode 26.6.
- No shared scheme is committed (`zMD.xcodeproj/xcshareddata/` is absent). CI relies on
  xcodebuild's autogenerated `zMD` scheme, as the green upstream run did.
- The `gh` token scopes include `workflow`, which is required to push `.github/workflows`
  changes.

### Local smoke-test environment

- macOS 26.7 (25G229) on Apple silicon. Only `/Applications/Xcode.app` (27.0) is installed. The
  console session is active and unlocked.
- System appearance is Light without automatic switching. "Close windows when quitting an
  application" is off (`NSQuitAlwaysKeepsWindows = 1`), so window restoration is active.
- `/Applications/zMD.app` is absent. There are no zMD Launch Services or PlugInKit registrations,
  no zMD process, no `com.zmd.app` preferences, and no saved application state, so the release
  app has not run here. A `com.zmd.app.QuickLook` container shows that the release extension ran
  earlier from a build or DMG.
- The release shared domain `com.zmd.table-column-layout` exists with stale content from
  2026-09-27 21:35. The release app overwrites it on every launch
  (`SettingsManager.init` → `MarkdownTableColumnPreferences.persist`,
  `zMD/SettingsManager.swift:383-385`).
- User-chosen Launch Services handlers send `.md` to Xcode and `.txt` to Sublime Text.
  Installing zMD will not change them, so Finder double-click will not open zMD. Use Open With
  or `open -a`.
- `agent-desktop` has Accessibility permission. Screen Recording was granted to
  `/Applications/OpenChamber.app` on 2026-09-28, after this revision was drafted. OpenChamber is
  the responsible app for the agent's shell and `agent-desktop`. `agent-desktop status` reports
  `granted`, and `CGWindowListCopyWindowInfo` now returns window titles. Screenshots are sent to
  the model provider; turn the permission off again when P1 testing ends.

## Authorization gates

Ask immediately before each action and record the answer in the execution note.

| Gate | Action |
|---|---|
| G-CI-1 | Accept the fork workflow banner on the Actions tab. The user clicks it; the agent may do so only in the user's own Chrome after an explicit "use my Chrome" opt-in. |
| G-CI-2 | Push local `master` commits to `origin` (`ib0ndar/zMD`); the push triggers CI. Never open pull requests against `umzcio/zMD`. Pull requests inside the fork need the user's request. |
| G-CI-3 | Re-run failed jobs or push follow-up commits to `origin/master`. |
| G-QA-1 | Install v2.12.0 as `/Applications/zMD.app`. It is currently absent; nothing is overwritten. |
| G-QA-2 | Let the release app create `com.zmd.app` preferences and saved state and overwrite `com.zmd.table-column-layout` after a backup. Later restore, remove, or keep them as the user decides. |
| G-QA-3 | Drive zMD, its menus, and the Dock with `agent-desktop` Accessibility automation. Use headed input only when semantic actions cannot perform the step. |
| G-QA-4 | Done 2026-09-28: the user granted Screen Recording to `OpenChamber.app`. Only the user changes this privacy setting; ask the user to revoke it after testing. |
| G-QA-5 | Optional: install through a browser download so the first launch exercises Gatekeeper; the user acts in System Settings. |

## Phase 0: Preflight

```bash
cd /Users/ivan/git/zMD
git remote -v
git fetch --prune --tags origin
git fetch --prune --no-tags upstream
git status --short --branch --untracked-files=all
git rev-list --left-right --count master...origin/master
git log -1 --decorate --oneline
git rev-parse 'v2.12.0^{commit}'
xcode-select -p
xcodebuild -version
gh repo view ib0ndar/zMD --json nameWithOwner,defaultBranchRef,viewerPermission,url
gh release view v2.12.0 --repo ib0ndar/zMD --json tagName,targetCommitish,assets
gh run list --repo ib0ndar/zMD --limit 5
/Users/ivan/.local/bin/agent-desktop status
```

Expected: `master` equals `origin/master` at `e1c58de` or a fast-forward descendant. The only
local change should be this plan revision, which is committed with the Phase 1 change. The tag
peels to `77de482`, the asset digest is `cf938400…e59`, and Xcode is 27.0 (27A266a).

### STOP conditions

Stop and report before editing when any of the following is true:

- `origin` does not resolve to `https://github.com/ib0ndar/zMD.git`.
- The worktree contains changes other than this plan revision that the executing agent did not
  create.
- Local and remote `master` have diverged or remote `master` was rewritten.
- `v2.12.0` no longer peels to `77de482`, or the release asset digest differs.
- Xcode 27 is unavailable or `xcodebuild -checkFirstLaunchStatus` fails.

## Phase 1: First hosted CI run

1. **Clear the fork gate (G-CI-1).** Open <https://github.com/ib0ndar/zMD/actions> while signed
   in as `ib0ndar`. If the banner appears, accept "I understand my workflows, go ahead and enable
   them". If it does not appear, the diagnosis is wrong. Inspect Settings → Actions → General,
   report the finding, and STOP before pushing anything.
2. **Prepare the change on `master`.** The user authorized local commits on 2026-09-28; pushing
   falls under G-CI-2. Keep the build and test commands unchanged. In
   `.github/workflows/ci.yml`:
   - replace the incorrect Xcode comment with the verified facts: default Xcode 26.6 on image
     20260907, with Xcode 27 only on the `xcode-27` preview label;
   - add a `Show toolchain` step before Build that runs `sw_vers`, `xcodebuild -version`,
     `xcrun swift --version`, and `xcrun --sdk macosx --show-sdk-version`;
   - add `workflow_dispatch:` for later on-demand runs. GitHub accepts manual dispatch only after
     the workflow reaches `master`.

   Include this plan revision in the commit. Optionally, if the user wants it, also correct
   `.github/dependabot.yml`, whose comment places the `CDN` enum in `SettingsManager.swift`; it
   lives in `SharedConstants.swift`. See Decision D1 below for toolchain choices.
3. **Local preflight** on Xcode 27, with the CI overrides and the required wrapper:

   ```bash
   ./scripts/xcodebuild-zmd.sh -configuration Debug \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
     DEVELOPMENT_TEAM='' build
   ./scripts/xcodebuild-zmd.sh -configuration Debug \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
     DEVELOPMENT_TEAM='' test -destination 'platform=macOS'
   ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml"); puts "YAML OK"'
   git diff --check
   ./scripts/manage-dev-registrations.sh status
   ```

   A local pass does not prove that CI passes, because the hosted job compiles with Xcode 26.6.
4. **Push `master` (G-CI-2).** The `push` trigger runs CI on the pushed commit. Never open pull
   requests against `umzcio/zMD`.

   ```bash
   git push origin master
   ```

   Pass `--repo ib0ndar/zMD` to every `gh` command. No `gh` default repository is set, and a
   fork checkout can otherwise resolve to the parent.

5. **Observe the run.**

   ```bash
   gh run list --repo ib0ndar/zMD --workflow CI --branch master --limit 5
   gh run watch <run-id> --repo ib0ndar/zMD --exit-status
   gh run view <run-id> --repo ib0ndar/zMD \
     --json url,event,headSha,conclusion,createdAt,updatedAt,jobs
   ```

   Record the URL, event, tested SHA, runner image from "Set up job", Xcode and SDK from
   `Show toolchain`, step durations, and conclusion. If no run appears within about two minutes
   of the push, revisit step 1 and STOP.
6. **Diagnose failures from logs**, starting with
   `gh run view <run-id> --repo ib0ndar/zMD --log-failed`:
   - Xcode 26.6, Swift 6.3.3, or macOS 26.5 SDK errors that Xcode 27 does not raise: use
     Decision D1.
   - Timing-sensitive tests in `zMDTests/InlineMarkdownTests.swift`:
     - symlink-cycle scan: fixed 1.0 s wait, 3 s timeout (`:567-570`);
     - FSEvents lifecycle: 2.0 s initial wait, 12 s timeout (`:612-635`);
     - auto-save: 4 s timeouts around the 2 s debounce (`:409-413` polling; `:450-451`
       disabled-case wait);
     - FileWatcher: 4 s timeout (`:330-334`).

     Re-run failed jobs once after G-CI-3 approval to separate a flake from a deterministic
     failure, then propose focused hardening. Never silently lengthen, skip, or disable a test.
   - Environment failures, including installed fonts, the WindowServer needed by the off-screen
     `NSWindow` tests (`:1074`, `:1129`), or network access: report them with the relevant log
     excerpt.

   STOP and ask if a fix requires application-code changes.
7. **Record the green result** in a follow-up commit on `master`:
   - add the first hosted run URL, tested SHA, image, and Xcode version to Plan 006's note;
   - change `plans/README.md` row 006 to `DONE` and add a short Plan 025 entry;
   - correct `AGENTS.md`'s CI toolchain sentence;
   - append the execution note to this plan.

   Decide separately whether the README/CONTRIBUTING minimum remains "Xcode 27+". Push the
   commit after G-CI-3 approval; the resulting run must also pass.
8. **Later runs.** Once the workflow is on `master`, start an on-demand run with
   `gh workflow run CI --repo ib0ndar/zMD --ref master`.

### Decision D1: toolchain represented by CI

| Option | Description |
|---|---|
| **A** (recommended for the first run) | Keep `macos-26` and its default Xcode 26.6. This proves the GA path and leaves the build and test commands unchanged. If it passes, document CI as Xcode 26.6 and releases as Xcode 27.0. |
| B | Use A and add a second, non-blocking `runs-on: xcode-27` job (`continue-on-error: true`) for release-toolchain parity. It is a preview image, so queueing and instability are possible. |
| C | Move CI entirely to `xcode-27`. Consider this only if A fails for Xcode 26.6-only reasons and supporting both toolchains is not wanted. |

### Acceptance criteria

- At least one hosted `CI` run exists for the post-v2.12 tree, and both its Build and Test steps
  in the single `build-and-test` job succeed.
- The run URL, tested SHA, runner image, and Xcode version are recorded in Plan 006, in
  `plans/README.md`, and in this plan.
- `ci.yml` and `AGENTS.md` no longer misstate the CI toolchain.

## Phase 2: P1 smoke tests of the published v2.12.0 app

### 2.0 Preparation

1. Create the untracked evidence root `artifacts/plan-025/` with `release/`, `fixtures/`,
   `prefs-backup/`, `logs/`, `ql/`, `tools/`, and `p1-matrix.md`. Report it at handover; do not
   commit or ignore it without direction.
2. Choose an install path:
   - **Browser path** (preferred when the human is present; covers G-QA-5): the human downloads
     `zMD.dmg` in a browser, verifies its SHA-256 is `cf938400…e59`, and drag-installs it. The
     first launch then exercises Gatekeeper; see 2.4.
   - **CLI path** (G-QA-1): `gh` does not set the quarantine attribute, so this copy skips
     Gatekeeper.

     ```bash
     gh release download v2.12.0 --repo ib0ndar/zMD --pattern zMD.dmg \
       --dir artifacts/plan-025/release
     shasum -a 256 artifacts/plan-025/release/zMD.dmg
     ```

     Mount it read-only with `hdiutil attach -nobrowse -readonly`. Check the app and extension
     for version 2.12.0 (1), bundle IDs `com.zmd.app` and `com.zmd.app.QuickLook`, `arm64`
     architecture, and a passing `codesign --verify --deep --strict`. Then install with
     `ditto <mount>/zMD.app /Applications/zMD.app` and detach the image.
3. Before the first launch (G-QA-2), run
   `defaults export com.zmd.table-column-layout artifacts/plan-025/prefs-backup/com.zmd.table-column-layout.plist`.
   Record that `com.zmd.app` and `~/Library/Saved Application State/com.zmd.app.savedState` do
   not exist.
4. Record `sw_vers`, system appearance, `NSQuitAlwaysKeepsWindows`, and `agent-desktop status`.
5. Create scratch fixtures under `artifacts/plan-025/fixtures/`; never open user documents.
   - Copy `fixtures/reader-layout.md`.
   - Create `p1-tables.md` containing:
     - a table whose headers match each default category plus one unmatched header, for example
       `Interface | Status | Description | Documentation | Zebra`;
     - a table with only unmatched headers;
     - a raw HTML `<table>` block;
     - front matter;
     - body prose, inline code, a fenced code block, and a shell command for font-role checks.
   - Create `clean-a.md`, `clean-b.md`, and `dirty-scratch.md` for lifecycle tests.
6. Create tools under `artifacts/plan-025/tools/`:
   - `zmd-windows.swift` prints bounds and titles for on-screen layer-0 windows owned by `zMD`
     through `CGWindowListCopyWindowInfo`; run it with `swift`.
   - A small `main.swift` compiled with `zMD/SharedConstants.swift`, which is Foundation-only,
     prints `MarkdownTableColumnLayout.widthPercentages` for a header row and configuration. It is
     the width oracle for the T cases.
7. Before and after each lifecycle case, capture this evidence:
   - Accessibility: `agent-desktop list-windows --app zMD`
   - window server: `zmd-windows.swift`
   - process: `pgrep -lx zMD`

   "No window" requires all three sources to agree and a screenshot to show no zMD window. On any
   failure, also save:

   ```bash
   log show --last 5m --style compact --predicate 'process == "zMD"' \
     > artifacts/plan-025/logs/<case>.log
   ls -la ~/Library/Saved\ Application\ State/com.zmd.app.savedState
   ```

**Decision D2: execution mode.** The agent drives zMD with `agent-desktop` (G-QA-3). It verifies
state through window evidence, window titles, alerts, `defaults read com.zmd.app …`, and Quick
Look HTML, and captures screenshots of zMD windows as visual evidence in `artifacts/plan-025/`.
Capture only zMD, Settings, and Quick Look windows; avoid full-screen captures of unrelated
content. The human confirms subjective judgments, such as whether a change was immediate or an
animation felt natural.

Use these actions:

- Reopen a running app with `open -a /Applications/zMD.app`; it sends the same reopen event as a
  Dock click. Pressing the Dock item through Accessibility is a secondary check.
- Open files through the Open With path with `open -a /Applications/zMD.app <file>`, which uses the
  same `odoc` Apple event.
- Prefer menu items to synthesized shortcuts.

### 2.1 Window lifecycle and cold launch (highest priority)

These code facts at `e1c58de` shape the cases:

- The window opener is registered only in `ContentView.onAppear` (`zMD/ContentView.swift:205-211`).
  Without it, `DocumentManager.showMainWindow()` only activates the app
  (`zMD/DocumentManager.swift:55-58`). `loadDocument`, `createNewFile`, and Dock reopen all depend
  on that registration.
- `zMD/zMDApp.swift:50-69` binds `WindowCloseDelegate`, the title, the proxy icon, and edited
  state to `NSApplication.shared.windows.first`, not to the view's own window. It also resizes
  that window to 1000×700 when it is smaller than 900×650.
- zMD has no custom restoration code. The `Window("zMD", id: "main")` scene relies on
  SwiftUI/AppKit restoration, which is active on this Mac.

| ID | Case | Expected |
|---|---|---|
| L1 | First cold launch, with no preferences or saved state: `open -a /Applications/zMD.app` | Within 10 s, one visible main window appears with welcome content, about 1000×700 and centered. |
| L2 | After L1, press the red close button through Accessibility; then reopen with `open -a` and with the Dock item. | The window closes and the process stays alive; each reopen restores the welcome window. |
| L3 | Run `open -a … clean-a.md`, then choose Tab → Close Tab. | The window title is `clean-a.md` while open. Closing the last tab dismisses the window, the process stays alive, and reopening shows welcome content. |
| L4 | Open `clean-a.md` and `clean-b.md`, then press the red close button. | All tabs and the window close without prompts; the process stays alive. |
| L5 | With no window after L2 or L3: (a) run `open -a … clean-a.md`; (b) choose File → New File… from the menu bar. | (a) The window is recreated with `clean-a.md` selected. (b) A window appears with an Untitled document in Source mode. |
| L6 | Quit and relaunch: (a) quit with the window open; (b) close the window, choose zMD → Quit, and relaunch; (c) repeat (b) with `open -a /Applications/zMD.app --args -ApplePersistenceIgnoreState YES`, which requires zMD not to be running. | Every relaunch shows a visible main window. Case (c) separates restoration effects from launch behavior. |
| L7 | Make `dirty-scratch.md` and an Untitled document dirty; try Close Tab, the red close button, and zMD → Quit. | Each action shows Save / Don't Save / Cancel. Cancel keeps all tabs and the app. Use Don't Save only at the end, for scratch edits. |
| L8 | Test delegate binding after reopen: close the main window, open zMD → Settings…, and reopen the main window with `open -a … clean-a.md`. Make that document dirty and press the main window's red close button. | Settings keeps its size and title, the main window title shows `clean-a.md`, and the dirty alert appears. Any other result confirms the `windows.first` risk. |

If any case leaves a live process without a window, record the evidence and logs. Then try
`open -a`, the Dock item, File → New File…, and `open -a … file.md`, recording which path
recovers. A document that "opens" without a window is the key finding. Stop the remaining visual
checks only when no documented path produces a window. Report the issue as a release-blocking
2.12.1 candidate that also affects umzcio/zMD#6. Do not fix it without approval, and do not call
it fixed based only on unit tests.

### 2.2 Appearance, themes, and fonts

| ID | Case | Expected / evidence |
|---|---|---|
| A1 | Leave macOS in Light. With Settings → Appearance key and focused, choose Dark and then System. | Dark applies to Settings and the main window immediately. System returns both to Light immediately, with no click elsewhere; take a screenshot after each click, and have the human confirm the change was immediate. `defaults read com.zmd.app colorScheme` returns `system`. |
| A2 | Open the Light mode and Dark mode menus and list their items through Accessibility. | Their names match the 102 light and 249 dark themes in `zMD/Resources/Base16Themes.json` exactly (script set comparison). |
| A3 | With a document open, choose non-default light and dark themes, switch appearance between Light and Dark, then quit and relaunch. | The preview palette follows the appearance (screenshots). `lightPreviewThemeID` and `darkPreviewThemeID` persist, and the menus still show them after relaunch. |
| A4 | Choose a proportional Main font and a monospaced Fixed font, then spot-check menu membership, for example that Menlo is absent from Main and Georgia from Fixed. | Body text uses Main; fenced code, inline code, and commands use Fixed (screenshots; the human confirms if the typefaces are hard to tell apart). `mainPreviewFontID` and `fixedPreviewFontID` persist after relaunch. |

Test a live macOS appearance change only if the user flips and restores the system setting.

### 2.3 Tables and Quick Look

| ID | Case | Expected / evidence |
|---|---|---|
| T1 | Open `p1-tables.md` and `reader-layout.md` with default categories. | Tables fill the content width and column proportions match the oracle (screenshots). |
| T2 | In Advanced…, add a word, for example `zebra` to Compact. Reorder Compact and Operational / Documentation, which both contain `operational`. Change one weight. | The preview re-renders immediately, the first category in priority order wins, and widths follow the oracle. |
| T3 | Change the Other weight, then remove Other. | Unmatched headers use Other's weight; after removal they use `1.0`. |
| T4 | Quick Look the same file. Try `qlmanage -p -o artifacts/plan-025/ql <file>` to capture HTML; if the app extension produces no HTML, use `qlmanage -p` and a screenshot. The human also performs one Finder Space check. | The `.zmd-markdown-table` `<colgroup>` percentages match the oracle for the current configuration. `pluginkit -m -v -i com.zmd.app.QuickLook` lists only `/Applications/zMD.app`. |
| T5 | Check the raw HTML `<table>` and front matter. | The app preview renders raw HTML through HTML import, with no category widths. Quick Look shows raw HTML as escaped text by design (`zMD/MarkdownParser.swift:932-935`) without the `zmd-markdown-table` class. |

Never resize, move, or zoom an existing Finder window. The human performs the Finder check.

### 2.4 Gatekeeper first launch (browser path only, G-QA-5)

On macOS 15 and later, Apple states that Control-click → Open no longer bypasses Gatekeeper for
software that is not notarized. The expected path is System Settings → Privacy & Security → Open
Anyway. Verify what actually happens on macOS 26.7. If the user must use Open Anyway, the
right-click instructions in `README.md`, `CLAUDE.md`, and the v2.12.0 release notes are outdated.
That is a documentation follow-up, not a release blocker.

### 2.5 Deliverable

Write `artifacts/plan-025/p1-matrix.md` with ID, macOS 26.7 (25G229), zMD 2.12.0 (1), result
(`PASS`, `FAIL`, `INCONCLUSIVE`, or `ENV-LIMIT`), and evidence path for each case. Keep confirmed
bugs, environment limitations, and subjective observations in separate sections. State that
coverage is limited to macOS 26.7 on Apple silicon and that macOS 13–15 remain untested.

### 2.6 Cleanup

Report cleanup options; act only on direction. Quit zMD with no dirty documents and run
`./scripts/manage-dev-registrations.sh status`. Ask whether to keep `/Applications/zMD.app` and
the test-created `com.zmd.app` preferences and saved state. Also ask whether to restore
`com.zmd.table-column-layout` from the backup with `defaults import`.

## Deferred: not part of this pass

- **P2 rendering and feel checks**: a live Mermaid render after the Mermaid 11 update,
  split-mode typing, stale search highlighting, and the animation checks in plans 019–024. Leave
  those plan statuses unchanged: the files say `TODO` and `plans/README.md` says `DONE —
  feel-check pending`. Reconcile them when the checks run.
- **Signing and notarization**: out of scope. The fork owner has no Apple Developer Program
  membership, so releases stay ad-hoc signed and are not notarized, and the release notes say so.
  Plan 002's exposed notary key belongs to the upstream maintainer's Apple account (team
  `5JJ6G6A84S`); only upstream can revoke it. Do not replace published assets.
- **Local artifact hygiene**: report only, and delete nothing without explicit path-level
  direction.
  - Ignored `build/` contains the legacy pre-`SYMROOT` `build/Release/` and the unpublished
    `build/zMD.dmg`; `default.profraw` is also ignored.
  - Leftover preference domains: five `com.zmd.tests.app.*`, five `com.zmd.tests.ql.*`,
    `com.zmd.ui-rework-latest`, and `com.zmd.ui-rework-test`.
  - Leftover containers: `com.zmd.ui-rework-final`, `com.zmd.ui-rework-latest`,
    `com.zmd.ui-rework-test`, `com.zmd.quicklook.preference-probe2`, and
    `com.zmd.quicklook.preference-probe3`.
  - Unit tests leave `RecentMarkdownFiles` and `FolderBookmarkData` in the development domain
    `com.zmd.app.debug`.
- **Dependabot `actions/checkout@v7` branch**: evaluate it as a separate change. The first
  hosted run warned that `actions/checkout@v4` targets the deprecated Node.js 20 and was forced
  to run on Node.js 24.

## Code-read findings to triage after P1

These are not approved for fixing in this pass.

1. The main-window opener exists only after the first `onAppear`. L5 and L6 decide whether
   this is a bug.
2. `windows.first` delegate, chrome, and resize binding (`zMD/zMDApp.swift:53-68`). L8 decides
   whether this is a bug.
3. `handleGetURLEvent` iterates `1...numberOfItems` (`zMD/zMDApp.swift:554`). An `odoc` event
   with an empty list would trap.
4. `zMD/Info.plist` claims `public.plain-text`, inherited from upstream, but both open handlers
   silently ignore files other than `.md` and `.markdown`.
5. Every `onAppear` re-runs `folderManager.restoreFolder()` and the gated update check
   (`zMD/zMDApp.swift:71-75`).
6. Documentation drift appears in the `ci.yml` Xcode comment, the `AGENTS.md` CI toolchain
   claim, the CDN location in `.github/dependabot.yml`, and the Gatekeeper instructions, pending
   the 2.4 result.

## Validation after any code change

Use the commands and invariants in root `AGENTS.md`. At minimum, run:

```bash
xcode-select -p
xcodebuild -version
./scripts/xcodebuild-zmd.sh -configuration Debug test
git diff --check
plutil -lint zMD.xcodeproj/project.pbxproj
ruby -c scripts/update-base16-themes.rb
```

Local runs use Xcode 27. The hosted run is the only Xcode 26.6 signal. For rendering changes,
repeat the relevant Phase 2 checks. For Quick Look changes, build and inspect the embedded
extension. For release changes, mount and inspect the final DMG instead of validating only the
build directory. A post-v2.12.0 code fix requires version 2.12.1 or later, with all four
`MARKETING_VERSION` entries changed together. Never move or overwrite `v2.12.0`.

## Final handover report

Report the following:

- exact starting and ending commits;
- clean, ahead, and behind worktree state;
- authorization gates used and the answers given;
- CI run URLs, tested SHAs, runner image, Xcode version, and conclusions;
- the complete P1 matrix and evidence location;
- confirmed bugs, with reproduction steps and any fix scope, including whether umzcio/zMD#6 is
  affected;
- signing and notarization status: out of scope; releases are ad-hoc signed and not notarized;
- files committed, pushed, or intentionally left local, including `artifacts/plan-025/`;
- whether a new release is required and why.

Completion means the first hosted CI run is proven, the P1 matrix has unambiguous results, the
CI-related metadata matches reality, and the repository is left clean apart from reported
untracked artifacts.

## Execution notes

### 2026-09-28

**Gates and decisions**

- G-CI-1: the user accepted the fork workflow banner. No run was expected until the next event.
- G-QA-4: the user granted Screen Recording to `OpenChamber.app`.
- D1: the user chose option A, `macos-26` only.
- G-CI-2: the user first answered "Not yet". The user then authorized a local commit and
  directed that work stay in `ib0ndar/zMD`, with no new pull requests to `umzcio/zMD`. Pull
  requests inside the fork are acceptable. Finally, the user approved a direct push to `master`
  and chose to keep `artifacts/` local and uncommitted.

**Phase 0 preflight passed**

- `master` equals `origin/master` at `e1c58de`, 0 ahead/0 behind, and `v2.12.0` peels to
  `77de482`.
- The release asset digest is still `cf938400…e59`.
- Xcode 27.0 (27A266a) passed `-checkFirstLaunchStatus`.
- The fork still had no CI runs.

**Phase 1 step 2**: prepared the change from `e1c58de` and committed it on local `master`. A
temporary local branch, `ivan/plan-025-ci`, had no commits and was deleted. The commit contains:

- in `.github/workflows/ci.yml`, a corrected toolchain comment, a `Show toolchain` step, and
  `workflow_dispatch`, with valid YAML;
- this plan.

**Phase 1 step 3**: local preflight through the wrapper with the CI overrides.

- The build succeeded. It was incremental, with no Swift sources recompiled.
- The test action reported 118 passed, 0 failed, and `** TEST SUCCEEDED **`.
- Two existing `ld` warnings appear when linking `zMDTests`: Xcode 27's XCTest libraries are
  built for macOS 14.0, while the target deploys to 13.0.
- No development registrations remained afterwards.
- Logs are in `artifacts/plan-025/logs/`. `artifacts/plan-025/pr-body.md` is an unused draft
  from the abandoned pull-request approach.

**Phase 1 steps 4–6**: after G-CI-2 approval, pushed `e1c58de..4a986b3` to `origin/master`.

- CI run [36479648425](https://github.com/ib0ndar/zMD/actions/runs/36479648425), `push`
  event, tested `4a986b3df8fbc3b5c582c251980e96f48a8d3aab`, concluded **success**. It appeared
  within seconds of the push, which confirms the fork-gate diagnosis.
- Runner: image `macos-26-arm64` 20260907.0351.1 on macOS 26.6.2 (25G83).
- Toolchain: Xcode 26.6 (17F113), Apple Swift 6.3.3, macOS SDK 26.5.
- Timing: the Build step took 95 s and the Test step 52 s; the whole job took 2 min 43 s.
- Tests: 118 passed, 0 failed or skipped. The fresh build produced no Swift warnings. The only
  build warnings were the same two `zMDTests` `ld` warnings seen locally; Xcode 26.6's XCTest
  is also built for macOS 14.0.
- Annotation: `actions/checkout@v4` targets the deprecated Node.js 20 and was forced onto
  Node.js 24.
- The full log is in `artifacts/plan-025/logs/ci-36479648425.log`.

**Phase 1 step 7**: recorded the run in `plans/README.md` (row and note 006, plus a Plan 025
entry), corrected `AGENTS.md`'s CI toolchain sentence, and updated this plan in a local
follow-up commit. The README/CONTRIBUTING minimum stays "Xcode 27+" unless the user decides
otherwise; CI shows Xcode 26.6 also builds and tests the current tree.

### 2026-09-29

**Follow-up fixes requested by the user**

- `5a3a4c2`: raised `zMDTests` to macOS 14.0 in both configurations and added a note to
  CONTRIBUTING. A local test run passed 118 tests with 0 warnings. The test bundle now reports
  `LSMinimumSystemVersion` 14.0, while the app remains at 13.0.
- `9af7930`: updated to `actions/checkout@v7`; release v7.0.1 runs on `node24`.
- After the user approved the push, pushed `4a986b3..9af7930`.
- [CI run 36485193189](https://github.com/ib0ndar/zMD/actions/runs/36485193189) on `9af7930`
  succeeded with Xcode 26.6 and Swift 6.3.3: 118 tests passed, with 0 build warnings and no
  annotations.

**Gates**: the user approved G-QA-1 (install) and G-QA-2 (settings). G-QA-5, the browser and
Gatekeeper path, was not used.

**Phase 2 preparation**

- Downloaded the asset with `gh`. It has no quarantine attribute, and its SHA-256 matches
  `cf938400…e59`.
- Mounted the image read-only. The app and extension report `com.zmd.app` and
  `com.zmd.app.QuickLook` 2.12.0 (1), minimum macOS 13.0, and `arm64`. The ad-hoc signature is
  valid.
- `Contents/Resources/Resources/` contains `Base16Themes.json`, with 351 themes (102 light, 249
  dark), and `TintedTheming-LICENSE.txt`.
- Installed the app as `/Applications/zMD.app` with `ditto`.
- Backed up `com.zmd.table-column-layout`, whose contents equal the defaults.
- Created fixtures, the window lister, and the table-width oracle under `artifacts/plan-025/`.

**L1: first run failed; reclassified below as ENV-LIMIT.**

- `open -a /Applications/zMD.app` at 00:20:16 produced a foreground process with a full menu
  bar. For more than 60 s, the window server had no window for its PID on any layer or Space, and
  Accessibility reported 0 windows.
- The AppKit log (`artifacts/plan-025/logs/L1-cold-launch.log`) records the cause:
  - AppKit found persistent restoration state: `hasPersistentStateToRestore=1`.
  - It asked `SwiftUI.AppWindowsController` to restore identifier `main`.
  - SwiftUI completed with `window=0x0 error=(null)`, and no default window was created.
- The state came from an earlier run of `com.zmd.app`, through the
  `com.apple.appkit.restoration_storage` service. `~/Library/Saved Application State/` and the
  `com.zmd.app` defaults domain were both absent. The re-verified claim that the release app had
  never run here was therefore wrong in effect.
- A reopen event (`open -a` again, equivalent to a Dock click) recovered the window.

**Remaining lifecycle confirmation**, in an unlocked session:

- confirm the trigger with L6(b);
- test opening a file while zMD is not running;
- repeat L1 after the state is reproduced.

**Environment limit**

- From about 00:2x, the screen was locked and both displays were asleep (0 active of 2 online).
- In that state, screenshots fail, and Accessibility does not expose zMD windows that the window
  server reports. This probably explains the original inconclusive observation.
- Remaining GUI cases are paused. zMD was quit gracefully with `agent-desktop close-app`.

**Other findings**

- `pluginkit` lists the installed Quick Look extension with election `-` (user chose to ignore
  it), so T4 is blocked until the user re-enables it.
- The menu bar contains two **View** menus. The details are in
  `artifacts/plan-025/p1-matrix.md`.

**Phase 2 resumed, 08:26–08:55, with the screen unlocked.** The user re-enabled zMD Quick Look,
which `pluginkit` now shows as elected `+`.

- **L1 reclassified as ENV-LIMIT.** The `loginwindow` log shows a direct screen lock at 00:19:27
  and display sleep from 00:19:57, so the 00:20:16 launch ran on a locked Mac with sleeping
  displays.
  - Unlocked launches with the same saved-state pattern (SwiftUI restore of `main` returning no
    window) created a default window about 80 ms later.
  - A launch with `-ApplePersistenceIgnoreState YES` also produced a window.
  - This very likely explains the original inconclusive report too. It is not a P1 app bug.
- **Lifecycle cases L2–L8 pass**, plus opening a file while zMD is not running:
  - the red close button, Dock and `open -a` reopen, and last-tab close;
  - file open and File → New File… with no window;
  - quit and relaunch in three variants;
  - Save / Don't Save / Cancel from Close Tab, the red close button, and Quit;
  - the delegate stays bound to the main window while Settings is open.
- **A1–A4 pass.** An immediate System switch was captured within 0.4 s with Settings focused. The
  theme menus exactly match the 102/249 catalog, the font menus are split correctly, and the
  selections persist after relaunch.
- **T1–T3 pass** against the width oracle, within about 1 percentage point, covering priority,
  added words, weights, the Other weight, and removing Other. **T5** passes in the app and in the
  generated HTML.
- **T4 awaits a Finder Space check by the user.** `qlmanage -p` crashes inside Apple's
  ExtensionFoundation before reaching the extension, and it raised a crash-reporter dialog.
  - **T4 passed** later: the user's Finder Space screenshot showed the Quick Look columns at
    12.1 / 16.2 / 20.3 / 18.2 / 16.1 / 17.2 % against an oracle of
    12.1 / 16.1 / 20.3 / 18.2 / 16.1 / 17.1 %.
  - The sandboxed extension therefore reads the release shared domain. Quick Look also shows raw
    HTML as escaped text, completing T5.
- The full matrix, observations, and evidence paths are in `artifacts/plan-025/p1-matrix.md`.
- The test configuration is still active: Compact moved up, weighted 2, with `zebra`, and Other
  removed. It persists in `com.zmd.app` and `com.zmd.table-column-layout`, with Solarized Light,
  Dracula, Georgia, and JetBrains Mono also selected. Restore or keep it at cleanup (2.6).

**Follow-up (21:29):**

- At the user's direction, the two docs commits were pushed
  ([CI run 36612392045](https://github.com/ib0ndar/zMD/actions/runs/36612392045), green).
- zMD was quit, the theme, font, and table-category keys were deleted from `com.zmd.app`, and
  `com.zmd.table-column-layout` was re-imported from the backup, which holds the default
  configuration.
- An export of the post-test `com.zmd.app` is kept in `artifacts/plan-025/prefs-backup/`.

### 2026-09-29 P2 rendering and feel checks

The user asked for the deferred P2 checks. The motion checks were recorded with
`screencapture -v` and analyzed frame by frame. The user kept the LG display clear and did not
take focus. The details are in `artifacts/plan-025/p1-matrix.md`, and the videos and helper tools
are in `artifacts/plan-025/`.

**Passed**

- Split-mode typing: the preview showed the final text 134–161 ms after the last keystroke.
- Search Next/Previous and clearing the query. The stale-highlight issue from Plan 010 did not
  reproduce.
- Viewport-bounded highlighting after scrolling.
- 019: Quick Open appears in a single frame, like ⌘K.
- 021: the dirty dot springs in once, fades out on save in about 70 ms, and is never stuck
  oversized under rapid type/save.
- 022: tabs and toasts arrive near full size.
- 023: welcome recents are visible about 0.43 s after first paint, with one icon overshoot of about
  1 %.
- 024: press feedback on both buttons (Open File hover 1.031× then press ≈1.00×; New File press
  0.967×), with no bezel.

**Confirmed pre-existing bugs**, none introduced by the fork's v2.10–v2.12 work:

1. **Mermaid flowcharts never render** in the preview.
   - Their `foreignObject` labels taint the canvas, so `toDataURL` throws `SecurityError` inside an
     `img.onload` that has no `try` (`zMD/WebRenderer.swift:146-151`).
   - The watchdog then leaves "Rendering diagram…" in place.
   - Mermaid 10.9.1 behaves the same, and `htmlLabels: false` avoids it (`tools/mermaid-probe`).
2. **KaTeX glyphs are blank** for the first formula that uses each KaTeX font face in a session.
   - KaTeX's CSS declares `font-display:block`, and zMD snapshots 16 ms after `katex.render`
     (`zMD/WebRenderer.swift:437-442`), before the CDN fonts load.
   - The incomplete image is then cached for the session.
3. **Line numbers are missing** in the Source and Split gutter. `LineNumberGutter.swift` is
   unchanged since v2.9; the cause is not diagnosed.
4. **Reduce Motion (Plan 020):** the find bar and outline pop in instead of cross-fading.
   `slideOrFade` falls back to `.opacity`, but `Motion.standard` is `nil` under Reduce Motion. The
   toast fades correctly. Separately, the outline toggle is instant even with Reduce Motion OFF.

**Reduce Motion handling.** It was switched on through System Settings → Accessibility → Motion,
because the preference domain is write-protected. zMD was relaunched for the test, and the setting
was restored OFF afterwards (`accessibilityDisplayShouldReduceMotion == false`).

**False alarm.** An apparent dirty close without a prompt was my own cleanup script answering
**Don't Save**, confirmed by the log timestamps. A reproduction showed the prompt works.

**Plan metadata.** Plans 019 and 021–024 were set to DONE (feel-checked). Plan 020 is DONE with
its Reduce Motion gap noted. The rows in `plans/README.md` were updated to match.

### 2026-09-29 v2.12.1 patch

The user asked for a 2.12.1 patch. Its scope is the Mermaid and KaTeX rendering bugs; line
numbers and the Reduce Motion fades remain open.

**Changes in `zMD/WebRenderer.swift`**

1. **Mermaid labels.** Mermaid now uses SVG labels: `htmlLabels: false` and
   `flowchart.htmlLabels: false`.
   - `tools/mermaid-probe-current` shows that under the old config the flowchart, class, state,
     ER, and mindmap diagrams all contained `foreignObject` and failed `toDataURL`. Only sequence,
     Gantt, and pie diagrams rendered.
   - With the new config, all eight contain no `foreignObject` and convert
     (`logs/P2-1-mermaid-probe-fixed.txt`).
2. **Conversion errors.** `img.onload` now catches conversion errors and posts `ERROR:`, so a
   failed diagram finishes immediately instead of waiting for the 15 s watchdog.
3. **Mermaid queue (newly found).** The `mermaidResult` handler called the active completion and
   then cleared `activeMermaidCompletion`.
   - The completion synchronously starts the next queued diagram, so the clear erased the next
     item's completion. Its result was dropped, `isMermaidRendering` stayed true, and the
     watchdog had nothing to fail, so every later diagram in the session stayed "Rendering
     diagram…".
   - This was hidden in 2.12.0 because flowcharts failed through the watchdog path, which clears
     before calling.
   - The handler now takes the completion, clears the property, and then calls it. The KaTeX
     error paths had the same pattern and were fixed the same way.
4. **KaTeX fonts.** After `katex.render`, the page forces layout, then waits for
   `document.fonts.ready` (capped at 5 s) before measuring. The snapshot is therefore taken after
   the formula's KaTeX web fonts load.

**Verification (Debug build, Xcode 27)**

- Tests: 118 passed with 0 warnings.
- `tools/mermaid-app-probe` runs the app's exact `renderMermaid` JavaScript. The flowchart, class,
  state, ER, mindmap, and sequence diagrams all return PNGs in one page, in order.
- In a fresh app session, `fixtures/p2-render-2121.md` renders every item within 5 s: 0
  placeholders and 9 attachments (3 formulas and 6 diagrams). First-use `e^{iπ}`, `Σ`, and `∫`
  are complete (`screens/2121-debug-*`).
- All four `MARKETING_VERSION` values are now 2.12.1, and `AGENTS.md`'s release history was
  updated.

**Release**

- Tag `v2.12.1`, annotated, points to `b61b9f0`. It was pushed atomically with `master`
  (`7d2851e`).
- [CI run 36620843838](https://github.com/ib0ndar/zMD/actions/runs/36620843838) ran Xcode 26.6 on
  `7d2851e` and succeeded: 118 tests, no warnings.
- The DMG was built with `NOTARIZE=0 ./scripts/build-dmg.sh` after the user granted OpenChamber
  permission to control Finder. It is 3,312,017 bytes, SHA-256
  `3efe5df9afa128f87e7a02d3c61ff5de59ae019dba0e1455fb5d71ab549dd32d`.
- DMG checks:
  - the app and extension are 2.12.1 (1), minimum macOS 13.0, `arm64`;
  - the ad-hoc signature is valid;
  - the bundle contains 351 themes (102 light, 249 dark) and the license;
  - the binary contains both fixes;
  - launched from the mounted image, it rendered `fixtures/p2-render-2121.md` completely on first
    use (0 placeholders, 9 attachments).
- [GitHub release](https://github.com/ib0ndar/zMD/releases/tag/v2.12.1) published as Latest. Its
  single asset `zMD.dmg` has a matching digest. The notes disclose ad-hoc signing without
  notarization and give first-launch steps for macOS 15 and later.
- `/Applications/zMD.app` is still the 2.12.0 test install.
- **Incident:** the DMG layout step moved the user's existing Finder window, because Finder opens
  new windows as tabs on this Mac. `AGENTS.md` and the user's global agent instructions now forbid
  changing any Finder window's geometry or view. Do not run `build-dmg.sh` again until its layout
  step stops driving Finder or the user explicitly approves the run.

## Revision log

- **Rev 1 (2026-09-28)**: original post-release handover.
- **Rev 2 (2026-09-28)**:
  - re-verified the handover against `e1c58de`;
  - narrowed scope to hosted CI plus the P1 smoke tests;
  - identified the fork workflow gate as the probable cause of missing runs;
  - found that CI uses Xcode 26.6 while releases use Xcode 27;
  - reworked the smoke tests around code-read lifecycle risks and this Mac's constraints;
  - left this revision uncommitted until it rides on the Phase 1 branch.
- **Rev 2.1 (2026-09-28)**: the user granted Screen Recording to `OpenChamber.app`, and
  `agent-desktop status` confirmed it. Visual smoke-test evidence now comes from agent
  screenshots, with the human confirming only subjective checks.
- **Rev 2.2 (2026-09-28)**: the user chose to work only in `ib0ndar/zMD`, with no new pull
  requests to `umzcio/zMD`. Phase 1 therefore commits on `master` and pushes to the fork.
