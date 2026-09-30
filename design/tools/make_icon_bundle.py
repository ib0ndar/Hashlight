#!/usr/bin/env python3
"""Build final/Hashlight.icon — an Icon Composer bundle for macOS 26 (Liquid Glass).

Default appearance = Frost (round caps), dark appearance = Ember. Artwork is re-projected from the
padded 824-in-1024 macOS grid to the edge-to-edge 1024 canvas that .icon uses (the system applies
the squircle, shadow and padding). Layer SVGs are flat and filter-free for CoreSVG.
"""
import json
import os
import shutil
import subprocess

from make_icons import hash_bars

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = os.path.join(HERE, "final", "Hashlight.icon")
ASSETS = os.path.join(ICON, "Assets")

K = 1024 / 824          # padded grid -> full canvas
OFF = 100


def proj(v):
    return (v - OFF) * K


def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{body}</svg>')


def write(name, content):
    with open(os.path.join(ASSETS, name), "w") as f:
        f.write(content)


def p3(hex_rgb, a=1.0):
    """'#rrggbb' -> Icon Composer extended-srgb colour string."""
    r, g, b = (int(hex_rgb[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},{a:.5f}"


def build():
    shutil.rmtree(ICON, ignore_errors=True)
    os.makedirs(ASSETS)

    # 1) glass: the '#' silhouette, flat white, round caps (Icon Composer supplies the material)
    write("glass.svg", svg(f'<g fill="#ffffff">{hash_bars(512, 512, 520 * K)}</g>'))

    # 2) spark: the light source (orb + soft halo via radial gradients, no filters)
    sx, sy = proj(752), proj(292)
    write("spark.svg", svg(
        f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{72 * K / 1.24:.1f}" fill="url(#halo)"/>'
        f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{30 * K:.1f}" fill="url(#orb)"/>',
        '<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fde68a" stop-opacity="0.85"/>'
        '<stop offset="0.45" stop-color="#fde68a" stop-opacity="0.35"/><stop offset="1" stop-color="#fde68a" stop-opacity="0"/></radialGradient>'
        '<radialGradient id="orb" cx="0.3" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#fde68a"/></radialGradient>'))

    # 3) warm glow in the top-right corner (both appearances)
    write("glow.svg", svg(
        '<rect x="0" y="0" width="1024" height="1024" fill="url(#warm)"/>',
        '<radialGradient id="warm" cx="0.8" cy="0.18" r="0.6"><stop offset="0" stop-color="#f59e0b" stop-opacity="0.55"/>'
        '<stop offset="1" stop-color="#f59e0b" stop-opacity="0"/></radialGradient>'))

    # 4) cool blue blob bottom-left (dark appearance only)
    write("cool.svg", svg(
        f'<circle cx="{proj(250):.1f}" cy="{proj(820):.1f}" r="{300 * K:.1f}" fill="url(#cool)"/>',
        '<radialGradient id="cool" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#0ea5e9" stop-opacity="0.35"/>'
        '<stop offset="1" stop-color="#0ea5e9" stop-opacity="0"/></radialGradient>'))

    icon = {
        "fill-specializations": [
            {"value": {"linear-gradient": [p3("#f7f5f0"), p3("#cfc9bd")]}},
            {"appearance": "dark", "value": {"linear-gradient": [p3("#232a36"), p3("#0b0e14")]}},
        ],
        "groups": [
            {   # top: the light source
                "name": "Spark",
                "layers": [{"image-name": "spark.svg", "name": "spark", "glass": False}],
                "specular": False,
                "shadow": {"kind": "neutral", "opacity": 0},
                "translucency": {"enabled": False, "value": 0},
            },
            {   # the glass '#'
                "name": "Glass",
                "layers": [{
                    "image-name": "glass.svg", "name": "glass", "glass": True,
                    "fill-specializations": [
                        {"value": {"solid": "extended-gray:1.00000,1.00000"}},
                        {"appearance": "dark", "value": {"solid": p3("#8a919c")}},
                    ],
                }],
                "lighting": "individual",
                "specular": True,
                "blur-material": 0.12,
                "shadow-specializations": [
                    {"value": {"kind": "neutral", "opacity": 0.45}},
                    {"appearance": "dark", "value": {"kind": "neutral", "opacity": 0.7}},
                ],
                "translucency-specializations": [
                    {"value": {"enabled": True, "value": 0.35}},
                    {"appearance": "dark", "value": {"enabled": True, "value": 0.55}},
                ],
            },
            {   # bottom: ambient light on the background
                "name": "Ambient",
                "layers": [
                    {"image-name": "glow.svg", "name": "warm glow", "glass": False},
                    {"image-name": "cool.svg", "name": "cool glow", "glass": False,
                     "hidden-specializations": [{"value": True}, {"appearance": "dark", "value": False}]},
                ],
                "specular": False,
                "shadow": {"kind": "neutral", "opacity": 0},
                "translucency": {"enabled": False, "value": 0},
            },
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    with open(os.path.join(ICON, "icon.json"), "w") as f:
        json.dump(icon, f, indent=2)
    print("wrote", ICON)

    # validate by compiling with actool for macOS 26
    out = os.path.join(HERE, "final", "actool-out")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    cmd = ["xcrun", "actool", ICON, "--compile", out, "--output-format", "human-readable-text",
           "--notices", "--warnings", "--errors", "--output-partial-info-plist", os.path.join(out, "partial.plist"),
           "--app-icon", "Hashlight", "--include-all-app-icons", "--enable-on-demand-resources", "NO",
           "--development-region", "en", "--target-device", "mac", "--minimum-deployment-target", "26.0",
           "--platform", "macosx"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    print(r.stdout.strip() or "(no actool output)")
    if r.returncode:
        print("actool FAILED", r.stderr.strip())
    else:
        print("actool OK ->", sorted(os.listdir(out)))


if __name__ == "__main__":
    build()
