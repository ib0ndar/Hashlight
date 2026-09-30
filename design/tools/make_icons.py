#!/usr/bin/env python3
"""Generate 10 Hashlight app-icon variants as 1024x1024 SVGs (macOS icon grid).

Canvas 1024, icon shape 824x824 centered (Apple macOS template), shadow included.
The '#' glyph is drawn geometrically (no font dependency) except the Terminal variant.
"""
import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "svg")
os.makedirs(OUT, exist_ok=True)

C = 1024            # canvas
S = 824             # squircle side
P = (C - S) / 2     # padding = 100
R = 185             # corner radius (~22.4 %)
CX = CY = C / 2


def squircle(fill, extra=""):
    return f'<rect x="{P}" y="{P}" width="{S}" height="{S}" rx="{R}" ry="{R}" fill="{fill}" {extra}/>'


def shadow():
    return (f'<rect x="{P}" y="{P + 12}" width="{S}" height="{S}" rx="{R}" ry="{R}" '
            f'fill="#000" opacity="0.35" filter="url(#shadow)"/>')


def defs_common():
    return f'''
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="14"/></filter>
  <clipPath id="clip"><rect x="{P}" y="{P}" width="{S}" height="{S}" rx="{R}" ry="{R}"/></clipPath>
'''


def hash_glyph(cx, cy, size, weight=None, slant=11, rx=None, fill="#fff", attrs="", skew=False):
    """Bold '#' from 4 bars. Round caps: verticals rotated by `slant`. Square caps (skew=True):
    verticals sheared so their ends stay horizontal, like a typographic '#'."""
    w = weight or size * 0.17
    rx = w / 2 if rx is None else rx
    L = size * 0.94
    H = size * 0.94
    dy = size * 0.19
    dx = size * 0.19
    parts = []
    for y in (cy - dy, cy + dy):
        parts.append(f'<rect x="{cx - L / 2:.1f}" y="{y - w / 2:.1f}" width="{L:.1f}" height="{w:.1f}" rx="{rx:.1f}"/>')
    for x in (cx - dx, cx + dx):
        if skew:
            tf = f'translate({x:.1f} {cy:.1f}) skewX({-slant}) translate({-x:.1f} {-cy:.1f})'
        else:
            tf = f'rotate({slant} {x:.1f} {cy:.1f})'
        parts.append(f'<rect x="{x - w / 2:.1f}" y="{cy - H / 2:.1f}" width="{w:.1f}" height="{H:.1f}" rx="{rx:.1f}" '
                     f'transform="{tf}"/>')
    return f'<g fill="{fill}" {attrs}>' + "".join(parts) + "</g>"


def hash_bars(cx, cy, size, weight=None, slant=11, rx=None, skew=False):
    """The four bars only (no wrapping <g>), for use inside masks/clipPaths."""
    g = hash_glyph(cx, cy, size, weight, slant, rx, fill="#fff", skew=skew)
    return g[g.index(">") + 1: -4]


def hash_ring(mask_id, cx, cy, size, width, color, opacity=1.0, attrs="", rx=None, skew=False):
    """Outer outline of the '#' silhouette only (no interior seams), via a luminance mask."""
    bars = hash_bars(cx, cy, size, rx=rx, skew=skew)
    mask = (f'<mask id="{mask_id}"><g fill="#fff" stroke="#fff" stroke-width="{2 * width}" stroke-linejoin="round">'
            f'{bars}</g><g fill="#000">{bars}</g></mask>')
    rect = f'<rect x="0" y="0" width="{C}" height="{C}" fill="{color}" opacity="{opacity}" mask="url(#{mask_id})" {attrs}/>'
    return mask + rect


def hash_fill(clip_id, cx, cy, size, fill, attrs="", rx=None, skew=False):
    """Single-shape fill of the '#' silhouette (translucent fills without overlap darkening)."""
    clip = f'<clipPath id="{clip_id}">{hash_bars(cx, cy, size, rx=rx, skew=skew)}</clipPath>'
    rect = f'<rect x="0" y="0" width="{C}" height="{C}" fill="{fill}" clip-path="url(#{clip_id})" {attrs}/>'
    return clip + rect


def doc_lines(x, y, width, gap, weights, color="#fff", opacity=0.5, h=22):
    """Markdown-ish text lines: list of relative widths, first one is a heading (thicker)."""
    out = []
    for i, rel in enumerate(weights):
        hh = h * 1.5 if i == 0 else h
        out.append(f'<rect x="{x}" y="{y + i * gap:.1f}" width="{width * rel:.1f}" height="{hh:.1f}" rx="{hh / 2:.1f}" '
                   f'fill="{color}" opacity="{opacity}"/>')
    return "".join(out)


def wrap(name, defs, body):
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{C}" height="{C}" viewBox="0 0 {C} {C}">
<defs>{defs_common()}{defs}</defs>
{shadow()}
<g clip-path="url(#clip)">
{body}
</g>
</svg>'''
    path = os.path.join(OUT, f"{name}.svg")
    with open(path, "w") as f:
        f.write(svg)
    return path


# ---------------------------------------------------------------- 01 Beam
def v01_beam():
    defs = '''
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1e293b"/><stop offset="1" stop-color="#0b1120"/></linearGradient>
  <linearGradient id="cone" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fde68a" stop-opacity="0.85"/><stop offset="0.55" stop-color="#fde68a" stop-opacity="0.25"/><stop offset="1" stop-color="#fde68a" stop-opacity="0"/></linearGradient>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="10"/></filter>
  <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="22"/></filter>
  <clipPath id="coneclip"><polygon points="330,330 1000,520 1000,1000 560,1000"/></clipPath>
'''
    body = squircle("url(#bg)")
    # light cone from the hash toward lower-right
    body += '<polygon points="345,345 1024,470 1024,1024 500,1024" fill="url(#cone)" filter="url(#soft)"/>'
    # faint document lines everywhere, brighter inside the cone
    lines = doc_lines(470, 470, 520, 78, [0.55, 0.95, 0.8, 0.9, 0.6, 0.85, 0.7], "#fff", 0.10, 24)
    body += lines
    body += f'<g clip-path="url(#coneclip)">{doc_lines(470, 470, 520, 78, [0.55, 0.95, 0.8, 0.9, 0.6, 0.85, 0.7], "#fff7d6", 0.75, 24)}</g>'
    # hash with glow
    body += hash_glyph(340, 340, 300, fill="#fde68a", attrs='filter="url(#glow)" opacity="0.9"')
    body += hash_glyph(340, 340, 300, fill="#ffffff")
    return wrap("01-beam", defs, body)


# ---------------------------------------------------------------- 02 Glow
def v02_glow():
    defs = '''
  <radialGradient id="bg" cx="50%" cy="45%" r="65%"><stop offset="0" stop-color="#2a1d5e"/><stop offset="1" stop-color="#07061a"/></radialGradient>
  <linearGradient id="amber" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff1b8"/><stop offset="0.5" stop-color="#fbbf24"/><stop offset="1" stop-color="#f59e0b"/></linearGradient>
  <filter id="glow1" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="40"/></filter>
  <filter id="glow2" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="12"/></filter>
'''
    body = squircle("url(#bg)")
    body += hash_glyph(CX, CY, 520, fill="#f59e0b", attrs='filter="url(#glow1)" opacity="0.75"')
    body += hash_glyph(CX, CY, 520, fill="#fde68a", attrs='filter="url(#glow2)" opacity="0.9"')
    body += hash_glyph(CX, CY, 520, fill="url(#amber)")
    # sparkle dust
    import random
    random.seed(7)
    for _ in range(26):
        x = random.uniform(150, 880); y = random.uniform(150, 880); r = random.uniform(2, 6)
        body += f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r:.1f}" fill="#fde68a" opacity="{random.uniform(0.25, 0.8):.2f}"/>'
    return wrap("02-glow", defs, body)


# ---------------------------------------------------------------- 03 Torch
def v03_torch():
    defs = '''
  <linearGradient id="bg" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#0b1d3a"/><stop offset="1" stop-color="#132c5c"/></linearGradient>
  <linearGradient id="beam" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#fff9d6" stop-opacity="0.95"/><stop offset="0.5" stop-color="#fde68a" stop-opacity="0.45"/><stop offset="1" stop-color="#fde68a" stop-opacity="0.05"/></linearGradient>
  <linearGradient id="body" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4b5563"/><stop offset="1" stop-color="#111827"/></linearGradient>
  <linearGradient id="head" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9ca3af"/><stop offset="1" stop-color="#374151"/></linearGradient>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="8"/></filter>
  <clipPath id="beamclip"><polygon points="330,700 1024,80 1024,760 420,800"/></clipPath>
'''
    body = squircle("url(#bg)")
    # faint hash (unlit)
    body += hash_glyph(640, 420, 380, fill="#ffffff", attrs='opacity="0.10"')
    # beam
    body += '<polygon points="345,690 1024,60 1024,780 430,790" fill="url(#beam)" filter="url(#soft)"/>'
    # lit part of the hash
    body += f'<g clip-path="url(#beamclip)">{hash_glyph(640, 420, 380, fill="#ffffff")}</g>'
    # flashlight (rotated 45deg, pointing up-right), drawn in local coords then transformed
    torch = '''
    <g transform="translate(300 735) rotate(-45)">
      <rect x="-250" y="-46" width="270" height="92" rx="30" fill="url(#body)"/>
      <rect x="-250" y="-46" width="270" height="92" rx="30" fill="none" stroke="#000" stroke-opacity="0.25" stroke-width="3"/>
      <rect x="-40" y="-64" width="110" height="128" rx="26" fill="url(#head)"/>
      <rect x="60" y="-60" width="16" height="120" rx="6" fill="#fff7d6"/>
      <rect x="-175" y="-20" width="60" height="18" rx="9" fill="#111827" opacity="0.6"/>
    </g>'''
    body += torch
    return wrap("03-torch", defs, body)


# ---------------------------------------------------------------- 04 Spotlight page (light theme)
def v04_page():
    defs = '''
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#dbe2ec"/><stop offset="1" stop-color="#c3cdd9"/></linearGradient>
  <radialGradient id="spot" cx="0.32" cy="0.22" r="0.46"><stop offset="0" stop-color="#fff6d5"/><stop offset="0.45" stop-color="#fdecb3" stop-opacity="0.75"/><stop offset="1" stop-color="#fde68a" stop-opacity="0"/></radialGradient>
  <radialGradient id="vign" cx="0.32" cy="0.22" r="0.9"><stop offset="0.35" stop-color="#334155" stop-opacity="0"/><stop offset="1" stop-color="#334155" stop-opacity="0.28"/></radialGradient>
  <filter id="pshadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="16"/></filter>
  <clipPath id="pageclip"><path d="M250 150 H692 L802 260 V882 a28 28 0 0 1 -28 28 H250 a28 28 0 0 1 -28 -28 V178 a28 28 0 0 1 28 -28 Z"/></clipPath>
'''
    body = squircle("url(#bg)")
    # page with folded corner
    px, py, pw, ph = 222, 150, 580, 760
    body += f'<rect x="{px}" y="{py + 18}" width="{pw}" height="{ph}" rx="28" fill="#000" opacity="0.18" filter="url(#pshadow)"/>'
    fold = 110
    body += (f'<path d="M{px + 28} {py} H{px + pw - fold} L{px + pw} {py + fold} V{py + ph - 28} '
             f'a28 28 0 0 1 -28 28 H{px + 28} a28 28 0 0 1 -28 -28 V{py + 28} a28 28 0 0 1 28 -28 Z" fill="#f4f6fa"/>')
    body += f'<path d="M{px + pw - fold} {py} V{py + fold - 28} a28 28 0 0 0 28 28 H{px + pw} Z" fill="#dfe5ee"/>'
    # text lines
    body += doc_lines(px + 70, py + 270, 440, 62, [0.0, 0.85, 0.7, 0.9, 0.55, 0.8, 0.65, 0.4], "#8b9bb0", 0.85, 18)
    # heading line (dark bar) next to hash
    body += f'<rect x="{px + 205}" y="{py + 132}" width="330" height="34" rx="17" fill="#1e293b"/>'
    # warm spotlight + vignette, both confined to the page
    body += f'<g clip-path="url(#pageclip)"><rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#vign)"/>'
    body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#spot)" style="mix-blend-mode:soft-light"/>'
    body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#spot)" opacity="0.55"/></g>'
    # hash in orange
    body += hash_glyph(px + 130, py + 150, 150, fill="#f97316")
    return wrap("04-page", defs, body)


# ---------------------------------------------------------------- 05 Cutout
def v05_cutout():
    defs = '''
  <radialGradient id="light" cx="0.5" cy="0.5" r="0.6"><stop offset="0" stop-color="#ffffff"/><stop offset="0.35" stop-color="#fde047"/><stop offset="0.75" stop-color="#f97316"/><stop offset="1" stop-color="#b91c1c"/></radialGradient>
  <linearGradient id="slab" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1f2937"/><stop offset="1" stop-color="#030712"/></linearGradient>
  <filter id="bloom" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="30"/></filter>
  <mask id="cut"><rect x="0" y="0" width="1024" height="1024" fill="#fff"/>''' + hash_glyph(CX, CY, 540, fill="#000") + '''</mask>
'''
    body = squircle("url(#light)")
    body += squircle("url(#slab)", 'mask="url(#cut)"')
    # bloom leaking over the edges
    body += hash_glyph(CX, CY, 540, fill="#fde047", attrs='filter="url(#bloom)" opacity="0.55"')
    # bevel highlight on the cutout edge (outer ring only)
    body += hash_ring("cutring", CX, CY, 540, 6, "#ffffff", 0.35)
    return wrap("05-cutout", defs, body)


# ---------------------------------------------------------------- 06 Lantern
def v06_lantern():
    defs = '''
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1e1b4b"/><stop offset="1" stop-color="#0a0820"/></linearGradient>
  <linearGradient id="metal" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#3f3f46"/><stop offset="0.5" stop-color="#71717a"/><stop offset="1" stop-color="#27272a"/></linearGradient>
  <radialGradient id="glass" cx="0.5" cy="0.5" r="0.7"><stop offset="0" stop-color="#fff7d6"/><stop offset="0.6" stop-color="#fbbf24"/><stop offset="1" stop-color="#d97706"/></radialGradient>
  <filter id="glow" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="60"/></filter>
'''
    body = squircle("url(#bg)")
    # glow halo
    body += '<rect x="330" y="330" width="364" height="420" rx="60" fill="#fbbf24" opacity="0.55" filter="url(#glow)"/>'
    # hook & ring
    body += '<rect x="500" y="100" width="24" height="120" rx="12" fill="url(#metal)"/>'
    body += '<circle cx="512" cy="235" r="30" fill="none" stroke="url(#metal)" stroke-width="18"/>'
    # cap
    body += '<path d="M372 300 L652 300 L610 262 L414 262 Z" fill="url(#metal)"/>'
    body += '<rect x="360" y="296" width="304" height="30" rx="10" fill="#52525b"/>'
    # glass body
    body += '<rect x="372" y="322" width="280" height="400" rx="36" fill="url(#glass)"/>'
    # frame bars
    for x in (372, 636):
        body += f'<rect x="{x}" y="318" width="16" height="410" rx="6" fill="url(#metal)"/>'
    # hash inside glass
    body += hash_glyph(512, 522, 210, fill="#7c2d12", attrs='opacity="0.95"')
    # base
    body += '<rect x="360" y="716" width="304" height="34" rx="12" fill="#52525b"/>'
    body += '<path d="M400 750 L624 750 L596 800 L428 800 Z" fill="url(#metal)"/>'
    # ground light pool
    body += '<ellipse cx="512" cy="860" rx="260" ry="40" fill="#fbbf24" opacity="0.18" filter="url(#glow)"/>'
    return wrap("06-lantern", defs, body)


# ---------------------------------------------------------------- 07 Terminal
def v07_terminal():
    defs = '''
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#161b22"/><stop offset="1" stop-color="#0d1117"/></linearGradient>
  <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="18"/></filter>
'''
    body = squircle("url(#bg)")
    body += squircle("none", 'stroke="#30363d" stroke-width="6"')
    # traffic lights
    for i, col in enumerate(("#ff5f57", "#febc2e", "#28c840")):
        body += f'<circle cx="{200 + i * 62}" cy="200" r="22" fill="{col}"/>'
    # prompt chevron
    body += '<path d="M200 470 L260 530 L200 590" fill="none" stroke="#8b949e" stroke-width="26" stroke-linecap="round" stroke-linejoin="round"/>'
    # green monospace hash (SF Mono / Menlo)
    text_attrs = 'font-family="SF Mono, Menlo, monospace" font-weight="700" font-size="520" text-anchor="middle"'
    body += f'<text x="530" y="700" {text_attrs} fill="#3fb950" opacity="0.7" filter="url(#glow)">#</text>'
    body += f'<text x="530" y="700" {text_attrs} fill="#56d364">#</text>'
    # cursor block
    body += '<rect x="720" y="470" width="90" height="150" rx="10" fill="#56d364" opacity="0.9"/>'
    return wrap("07-terminal", defs, body)


# ---------------------------------------------------------------- 08 Sunrise
def v08_sunrise():
    defs = '''
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7dd3fc"/><stop offset="0.55" stop-color="#fde68a"/><stop offset="1" stop-color="#fb923c"/></linearGradient>
  <linearGradient id="sun" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fb7185"/><stop offset="1" stop-color="#ea580c"/></linearGradient>
  <linearGradient id="sea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1d4ed8"/><stop offset="1" stop-color="#1e3a8a"/></linearGradient>
  <clipPath id="above"><rect x="0" y="0" width="1024" height="690"/></clipPath>
'''
    body = squircle("url(#sky)")
    # rays
    rays = ""
    for i in range(16):
        a = i * 360 / 16
        rays += f'<polygon points="512,560 {512 + 900 * math.cos(math.radians(a - 4)):.0f},{560 + 900 * math.sin(math.radians(a - 4)):.0f} {512 + 900 * math.cos(math.radians(a + 4)):.0f},{560 + 900 * math.sin(math.radians(a + 4)):.0f}" fill="#fff" opacity="0.18"/>'
    body += f'<g clip-path="url(#above)">{rays}</g>'
    # hash-sun, cropped by horizon
    body += f'<g clip-path="url(#above)">{hash_glyph(512, 470, 520, fill="url(#sun)")}</g>'
    # sea
    body += '<rect x="0" y="690" width="1024" height="400" fill="url(#sea)"/>'
    # reflection
    body += '<rect x="372" y="720" width="280" height="22" rx="11" fill="#fde68a" opacity="0.6"/>'
    body += '<rect x="412" y="775" width="200" height="18" rx="9" fill="#fde68a" opacity="0.4"/>'
    body += '<rect x="452" y="824" width="120" height="14" rx="7" fill="#fde68a" opacity="0.3"/>'
    return wrap("08-sunrise", defs, body)


# ---------------------------------------------------------------- 09 Prism
def v09_prism():
    defs = '''
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#27272a"/><stop offset="1" stop-color="#09090b"/></linearGradient>
  <linearGradient id="white" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff" stop-opacity="0.9"/></linearGradient>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="6"/></filter>
'''
    body = squircle("url(#bg)")
    # incoming white beam from the left into the hash
    body += '<polygon points="100,480 330,505 330,545 100,570" fill="url(#white)" filter="url(#soft)"/>'
    # hash (the prism)
    body += hash_glyph(430, 512, 300, fill="#ffffff")
    # rendered spectrum: bars fanning out to the right (heading, text, link, code, quote, list)
    colors = ["#f87171", "#fb923c", "#facc15", "#4ade80", "#38bdf8", "#a78bfa"]
    n = len(colors)
    x0, x1 = 560, 930
    y_top_in, y_bot_in = 470, 554
    y_top_out, y_bot_out = 250, 780
    for i, col in enumerate(colors):
        a_in = y_top_in + (y_bot_in - y_top_in) * i / n
        b_in = y_top_in + (y_bot_in - y_top_in) * (i + 1) / n
        a_out = y_top_out + (y_bot_out - y_top_out) * i / n
        b_out = y_top_out + (y_bot_out - y_top_out) * (i + 1) / n
        gap = 6
        body += (f'<polygon points="{x0},{a_in:.0f} {x1},{a_out + gap:.0f} {x1},{b_out - gap:.0f} {x0},{b_in:.0f}" '
                 f'fill="{col}" opacity="0.92"/>')
    return wrap("09-prism", defs, body)


# ---------------------------------------------------------------- 10 Glass
def v10_glass():
    defs = '''
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2563eb"/><stop offset="0.5" stop-color="#7c3aed"/><stop offset="1" stop-color="#db2777"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.18"/></linearGradient>
  <linearGradient id="spec" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></linearGradient>
  <filter id="gshadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="18"/></filter>
  <filter id="blur" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="30"/></filter>
  <filter id="spark" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="16"/></filter>
  <radialGradient id="orb" cx="0.3" cy="0.3" r="0.8"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#fde68a"/></radialGradient>
'''
    body = squircle("url(#bg)")
    # soft blurred blobs for depth
    body += '<circle cx="300" cy="300" r="220" fill="#60a5fa" opacity="0.5" filter="url(#blur)"/>'
    body += '<circle cx="760" cy="760" r="240" fill="#f472b6" opacity="0.5" filter="url(#blur)"/>'
    # glass hash: shadow, single-shape translucent body, outer-edge highlight
    body += hash_glyph(CX, CY + 26, 520, fill="#000", attrs='opacity="0.28" filter="url(#gshadow)"')
    body += hash_fill("gfill", CX, CY, 520, "url(#glassfill)")
    body += hash_ring("gring", CX, CY, 520, 5, "#ffffff", 0.8)
    # top specular sweep clipped to the hash
    body += '<g clip-path="url(#gfill)"><ellipse cx="440" cy="330" rx="330" ry="120" fill="url(#spec)" opacity="0.7"/></g>'
    # light spark at top-right of the hash
    body += '<circle cx="752" cy="292" r="58" fill="#fde68a" opacity="0.8" filter="url(#spark)"/>'
    body += '<circle cx="752" cy="292" r="30" fill="url(#orb)"/>'
    return wrap("10-glass", defs, body)


if __name__ == "__main__":
    targets = (v01_beam, v02_glow, v03_torch, v04_page, v05_cutout, v06_lantern, v07_terminal, v08_sunrise, v09_prism, v10_glass)
    import glass_variants  # noqa: E402  (10a–10e, defined alongside)
    targets = targets + tuple(glass_variants.ALL)
    for fn in targets:
        print("wrote", fn())
