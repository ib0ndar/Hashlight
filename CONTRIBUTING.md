# Contributing to Hashlight

Thanks for your interest in Hashlight — a native SwiftUI/AppKit markdown viewer
for macOS. Contributions of all kinds are welcome: bug reports, fixes, features,
and documentation. Keep it a viewer: nothing may write to a user's Markdown files.

## Getting started

**Requirements:** macOS 13+, Xcode 27+.

```bash
git clone https://github.com/ib0ndar/Hashlight.git
cd Hashlight
open Hashlight.xcodeproj  # then ⌘R
```

Or from the command line:

```bash
# Build
./scripts/xcodebuild-hashlight.sh -configuration Debug build

# Run the tests
./scripts/xcodebuild-hashlight.sh -configuration Debug test \
  -destination 'platform=macOS'
```

The wrapper keeps build products in `build/Xcode/` and unregisters development app/Quick Look
copies before and after the build. Do not create per-run `/tmp/...-derived` directories. Use
`HASHLIGHT_KEEP_REGISTRATION=1` only while deliberately testing Finder Quick Look, then run
`./scripts/manage-dev-registrations.sh unregister`.

There are no external dependencies — no SwiftPM packages, no CocoaPods. The
only web content is Mermaid/KaTeX, loaded in a hidden WKWebView. The in-app
updater is Hashlight's own code (GitHub's releases API, CryptoKit, `hdiutil`).

A clean build produces **zero warnings**. Please keep it that way.

## Project layout

The main pieces, all in `Hashlight/`:

- `DocumentManager.swift` — central document state (tabs, loading,
  reloading on external changes, find state). Always go through its
  methods; never mutate `openDocuments` directly.
- `MarkdownParser.swift` — the single source of truth for block-level
  parsing. Preview **and** all exports consume its `[Element]` output.
- `InlineMarkdown.swift` — the shared inline tokenizer (bold/italic/code/
  links/images/strikethrough). All four render backends (preview, HTML,
  DOCX, print) route through it.
- `MarkdownTextView.swift` — the NSTextView-based preview renderer.
- `ExportManager.swift` — PDF/HTML/RTF/DOCX export.
- `SoftwareUpdate*.swift` — the in-app updater: reading GitHub releases and
  verifying downloads (`SoftwareUpdate`), installing and relaunching
  (`SoftwareUpdateInstaller`), scheduling and the update window
  (`SoftwareUpdateController`).

### Adding new markdown syntax

Rendering and export must stay in sync:

1. Add a case to `MarkdownParser.Element` and parsing logic in
   `MarkdownParser.parse()` (block-level) or a token in
   `InlineMarkdown.tokenize()` (inline).
2. Add HTML conversion in `MarkdownParser.elementToHTML()`.
3. Add preview rendering in `MarkdownTextView`'s `renderElement()` dispatch.
4. Add DOCX/print handling in `ExportManager` / `PrintManager` if the
   element needs backend-specific output.
5. Add a test in `HashlightTests/` covering the new syntax.

## Code conventions

- Match the surrounding style; the codebase is plain Swift with no linter
  config (yet).
- **Deployment target is macOS 13.** No macOS 14+ APIs without an
  `if #available` check. Notably, `onChange(of:)` must use the
  one-parameter `{ _ in }` form — the zero-parameter form is macOS 14+.
  Only the `HashlightTests` target deploys to macOS 14.0, because Xcode's XCTest
  libraries are built for 14.0; the app and Quick Look extension stay at 13.0.
- Singletons (`DocumentManager.shared`, etc.) are observed with
  `@ObservedObject`, not `@StateObject`, since they are pre-existing shared
  instances.
- Comments should state invariants the code can't express — not narrate fix
  history.

## Submitting changes

1. Fork and create a topic branch off `main`.
2. Keep commits focused; explain *why* in the body when it isn't obvious.
3. Before opening a PR:
   - `./scripts/xcodebuild-hashlight.sh … build` succeeds with no new warnings
   - `./scripts/xcodebuild-hashlight.sh … test` passes
   - If you touched rendering or export, manually spot-check a markdown
     fixture in preview **and** at least one export format (they share the
     parser, but backend-specific bugs are the most common regression).
4. Open a PR against `main` with a clear description of the behavior
   change.

## Reporting bugs

Open an issue at <https://github.com/ib0ndar/Hashlight/issues> with:

- macOS version and Hashlight version (Hashlight → About Hashlight, or
  `defaults read /Applications/Hashlight.app/Contents/Info.plist CFBundleShortVersionString`)
- Steps to reproduce — a minimal markdown snippet that triggers the bug is
  worth a thousand words
- What you expected vs. what happened

## Releases

Hashlight releases are ad-hoc signed and disclose that they are not Developer ID signed or
notarized. Build the DMG with `./scripts/build-dmg.sh`; it builds a universal app from a clean
Release product (and stops if the app holds anything but the Quick Look extension or misses an
architecture), lays out the disk image with `dmgbuild`, installed on demand into
`build/dmg-venv`, and never scripts Finder.

The in-app updater reads the repository's GitHub releases (drafts and pre-releases are ignored)
and installs only what it can verify, so a release must follow this contract:

- the tag is `vX.Y.Z`, and the app inside is version `X.Y.Z`;
- the assets include `Hashlight-X.Y.Z.dmg` and its signature `Hashlight-X.Y.Z.dmg.sig`, which
  `build-dmg.sh` writes as `build/Hashlight.dmg.sig` with the maintainer's Ed25519 key
  (`scripts/update-signing.sh`; the matching public key is the `HASHLIGHT_UPDATE_PUBLIC_KEY`
  build setting);
- the update window shows the release notes up to a heading that starts with "Install" or the line
  `<!-- end of update notes -->`, so put installation steps after either.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE.md).
