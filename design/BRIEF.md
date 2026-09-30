# Hashlight — handover brief for the build agent

Product: **Hashlight**, a Markdown viewer for macOS.
This package contains the finished brand name (cleared), the final app icon in every format macOS
needs, and the decisions already taken with the product owner. Read this file first.

---

## 1. Identity

| Item | Decision |
|---|---|
| Name | **Hashlight** — one word, capital H. `#` (the Markdown heading mark) + light (a flashlight on your docs). |
| Pronunciation | HASH-light |
| App Store title suggestion | `Hashlight — Markdown Viewer` (subtitle carries the category for search) |
| Bundle identifier suggestion | `app.hashlight.Hashlight` *(pending registration of hashlight.app, see §2)* |
| Tagline suggestions | "Light on your Markdown." / "Read Markdown the way it was meant to look." *(suggestions only, not approved copy)* |

## 2. Name clearance (checked 2026-09-30)

- Mac App Store and iOS App Store: **no** app named Hashlight (incl. "Hash Light").
- USPTO: 0 records. TMview (EUIPO, UKIPO, WIPO, national offices): 0 records.
- Homebrew, PyPI, crates.io: free. **npm `hashlight` is taken** — use `hashlight-cli` or similar for any JS package.
- GitHub user `hashlight` is taken (use `hashlight-app` or the owner's account).
- Domains **free** at check time: `hashlight.app`, `hashlight.io`, `hashlight.dev`, `hashlight.net`, `hashlight.md`. `hashlight.com` is on the aftermarket.
- Only noise found: a dead 2022 NFT site (hashlight.org) and a 2014 jQuery plugin. Nothing in software.

**Action for the owner before launch:** register `hashlight.app` (and optionally `.io`/`.dev`). Full elimination log of ~60 alternative names: `naming/name-clearance-report.md`.

## 3. Visual identity

The mark is a rounded-cap `#` rendered as frosted **Liquid Glass**, lit by a small warm **spark** at
the top-right, with an amber glow in that corner. Two appearances share identical geometry:

| | Frost (Default) | Ember (Dark) |
|---|---|---|
| Background | vertical gradient `#F7F5F0 → #CFC9BD` | diagonal gradient `#232A36 → #0B0E14` |
| Glass `#` | white, translucent (≈0.35) | grey-white `#8A919C`, translucent (≈0.55) |
| Light | amber spark `#FDE68A` core / `#FBBF24` halo, warm glow `#F59E0B` | same, plus a cool blue glow `#0EA5E9` bottom-left |
| Accent colour for UI use | **Amber** `#F59E0B` / `#FBBF24` | same |

**Do not** drift toward a white `#` on a blue→violet→pink gradient: that is the house style of
Instagram hashtag-generator apps (a dozen near-identical icons) and of Clearly Markdown, a direct
competitor. The palette above was chosen specifically to avoid it. Six Mac Markdown apps already use a
`#` glyph; ours is distinct by material (glass) and light (amber), not by the glyph.

## 4. Icon deliverables (`icon/`)

| File | Use |
|---|---|
| `Hashlight.icon/` | **Icon Composer bundle, macOS 26+.** Default = Frost, Dark = Ember; Clear and Tinted are derived by the system. Validated with `xcrun actool` (Xcode 27). Groups: *Spark* / *Glass* / *Ambient*. |
| `Hashlight-Frost.icns` | Classic icon, Default appearance; 16 px and 32 px slots use a higher-contrast rendition. For macOS 13–15 and `CFBundleIconFile`. |
| `Hashlight-Ember.icns` | Classic icon, Dark appearance — for the optional runtime Dock switch on macOS 13–15. |
| `Hashlight-Frost-1024.png`, `Hashlight-Ember-1024.png` | Marketing / App Store artwork. **Frost is the canonical marketing image** (website, screenshots, listing). |
| `previews/` | Apple-engine renders of all six system appearances + `appearance-previews.png`. |
| `source/` | Editable SVG masters (no font dependency) and the flat layer SVGs used by the `.icon`. |

### 4.1 Xcode wiring

1. Drag `Hashlight.icon` into the project **beside** `Assets.xcassets` (not inside it). Remove any `AppIcon` set from the asset catalog.
2. Target → Build Settings → *App Icon Set Name* (`ASSETCATALOG_COMPILER_APPICON_NAME`) = `Hashlight`.
3. Xcode compiles the `.icon` for macOS 26 and auto-generates a flattened fallback for earlier systems. To ship the custom small-size renditions instead, set `CFBundleIconFile` to `Hashlight-Frost.icns` for the pre-26 icon.

### 4.2 Adaptive icon — decided behaviour

- **macOS 26+:** nothing to implement. *System Settings → Appearance → Icon & widget style* switches Frost/Ember (and Clear/Tinted) everywhere. Do **not** add an app-level toggle on 26.
- **macOS 13–15 (if supported):** optional preference **"Dock icon: Frost / Ember / Match appearance"**, default **Frost**. Only the running app's Dock tile (and Cmd-Tab) can change; the bundle icon in Finder/Launchpad stays Frost. Do not rewrite the bundle's icon on disk (sandbox, updates, code-signing strictness). Hide the preference on macOS 26.

```swift
enum DockIconMode: String { case frost, ember, matchAppearance }

final class DockIconController {
    private var observation: NSKeyValueObservation?

    func apply(_ mode: DockIconMode) {
        observation = nil
        switch mode {
        case .frost: NSApp.applicationIconImage = NSImage(named: "DockIcon-Frost")
        case .ember: NSApp.applicationIconImage = NSImage(named: "DockIcon-Ember")
        case .matchAppearance:
            observation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { app, _ in
                let dark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                app.applicationIconImage = NSImage(named: dark ? "DockIcon-Ember" : "DockIcon-Frost")
            }
        }
    }
    // NSApp.applicationIconImage = nil restores the bundle icon.
}
```
`DockIcon-Frost` / `DockIcon-Ember` are image sets made from the two 1024 PNGs (or the `.icns`).

## 5. Regeneration (`tools/`)

`make_icons.py` writes all SVG variants (the chosen ones are `pair-round-frost`, `pair-round-ember`,
`pair-round-frost-small`); render SVG → PNG with a Chromium/WebKit renderer that supports
`omitBackground`; `make_icon_bundle.py` rebuilds `Hashlight.icon` and validates it with `actool`.
Requires Python 3 + Pillow; Xcode 26+ for `actool`.

## 6. Not yet decided — confirm with the owner

- Minimum macOS version (drives whether §4.2's pre-26 preference is needed at all).
- Distribution: Mac App Store (sandboxed) vs direct/notarised — affects Quick Look extension design and file access.
- Feature scope beyond "Markdown viewer" (Quick Look extension, Mermaid/KaTeX, live reload, PDF export, themes). Competitive context: viewers such as MacMD Viewer, Imark, Readdown, QuickMD, Marked 2, Marklet exist; the name and icon work is done, the product spec is not part of this package.
- Registration of `hashlight.app` and choice of bundle identifier.
