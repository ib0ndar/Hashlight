# Hashlight — handover package

Brand name and app icon for **Hashlight**, a Markdown viewer for macOS. Prepared 2026-09-30.

**Start with `BRIEF.md`** — it holds every decision taken so far, the icon integration steps, the
adaptive-icon behaviour and the open questions to confirm with the product owner.

```
BRIEF.md                      decisions, palette, Xcode wiring, code snippet, open items
manifest.json                 machine-readable index of this package
icon/
  Hashlight.icon/             Icon Composer bundle (macOS 26+): Default=Frost, Dark=Ember
  Hashlight-Frost.icns        classic icon, Default appearance (custom 16/32 px renditions)
  Hashlight-Ember.icns        classic icon, Dark appearance (runtime Dock switch on macOS 13–15)
  Hashlight-Frost-1024.png    marketing artwork (canonical)
  Hashlight-Ember-1024.png    marketing artwork, dark
  previews/                   Apple-engine renders of all six appearances + review sheets
  source/                     editable SVG masters; layers/ = flat layer SVGs used by the .icon
naming/
  name-clearance-report.md    how the name was cleared and ~60 alternatives eliminated
tools/
  make_icons.py, glass_variants.py, make_icon_bundle.py   regenerate SVGs and the .icon bundle
```

Chosen design: variant **A — round caps** of the Glass family (see `icon/previews/appearance-previews.png`).
