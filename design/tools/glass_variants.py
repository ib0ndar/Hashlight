"""Glass sub-variants 10a–10e: same Liquid-Glass material as #10, but with palettes and a warm,
directional light source that keep Hashlight away from the hashtag-app cliché (white '#' on a
blue→violet→pink gradient) and from Clearly Markdown's blue-violet crystal.
"""
from make_icons import (C, CX, CY, P, S, doc_lines, hash_bars, hash_fill, hash_glyph, hash_ring, squircle, wrap)


def glass_core(cx, cy, size, fill_id, ring_color, ring_alpha, rim_id, spec_alpha=0.7, shadow_alpha=0.28,
               rx=None, skew=False):
    """Shadow + translucent single-shape body + outer outline + warm rim light + specular sweep."""
    body = hash_glyph(cx, cy + 26, size, rx=rx, skew=skew, fill="#000", attrs=f'opacity="{shadow_alpha}" filter="url(#gshadow)"')
    body += hash_fill("gfill", cx, cy, size, f"url(#{fill_id})", rx=rx, skew=skew)
    body += hash_ring("gring", cx, cy, size, 5, ring_color, ring_alpha, rx=rx, skew=skew)
    body += hash_ring("grim", cx, cy, size, 9, f"url(#{rim_id})", 1.0, rx=rx, skew=skew)
    body += (f'<g clip-path="url(#gfill)"><ellipse cx="{cx - 72}" cy="{cy - 182}" rx="330" ry="120" '
             f'fill="url(#spec)" opacity="{spec_alpha}"/></g>')
    return body


def spark(x, y, r=30, color="#fde68a", glow=58):
    return (f'<circle cx="{x}" cy="{y}" r="{glow}" fill="{color}" opacity="0.75" filter="url(#spark)"/>'
            f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#orb)"/>')


COMMON = '''
  <linearGradient id="spec" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.9"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></linearGradient>
  <linearGradient id="rim" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbbf24" stop-opacity="0.95"/><stop offset="0.45" stop-color="#fbbf24" stop-opacity="0.25"/><stop offset="1" stop-color="#fbbf24" stop-opacity="0"/></linearGradient>
  <radialGradient id="orb" cx="0.3" cy="0.3" r="0.8"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#fde68a"/></radialGradient>
  <radialGradient id="warm" cx="0.8" cy="0.18" r="0.6"><stop offset="0" stop-color="#f59e0b" stop-opacity="0.55"/><stop offset="1" stop-color="#f59e0b" stop-opacity="0"/></radialGradient>
  <filter id="gshadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="18"/></filter>
  <filter id="spark" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="16"/></filter>
  <filter id="blur" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="34"/></filter>
'''


# 10a — Ember: dark graphite glass, warm light from top-right, squared typographic caps
def v10a_ember():
    defs = COMMON + '''
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#232a36"/><stop offset="1" stop-color="#0b0e14"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.40"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.16"/></linearGradient>
'''
    body = squircle("url(#bg)")
    body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#warm)"/>'
    body += '<circle cx="250" cy="820" r="230" fill="#0ea5e9" opacity="0.18" filter="url(#blur)"/>'
    body += glass_core(CX, CY, 520, "glassfill", "#ffffff", 0.55, "rim", spec_alpha=0.5, rx=14)
    body += spark(770, 280)
    return wrap("10a-glass-ember", defs, body)


# 10b — Tide: teal→indigo glass with amber light (complementary, un-Instagram)
def v10b_tide():
    defs = COMMON + '''
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#0f8a9c"/><stop offset="0.55" stop-color="#155e96"/><stop offset="1" stop-color="#1e2f7a"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.50"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.18"/></linearGradient>
'''
    body = squircle("url(#bg)")
    body += '<circle cx="300" cy="280" r="230" fill="#5eead4" opacity="0.35" filter="url(#blur)"/>'
    body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#warm)"/>'
    body += glass_core(CX, CY, 520, "glassfill", "#ffffff", 0.8, "rim")
    body += spark(752, 292)
    return wrap("10b-glass-tide", defs, body)


# 10c — Frost: light-mode frosted glass on warm paper, amber light
def v10c_frost():
    defs = COMMON + '''
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6f4ef"/><stop offset="1" stop-color="#dcd8cf"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.85"/><stop offset="1" stop-color="#e8eef7" stop-opacity="0.65"/></linearGradient>
  <linearGradient id="rimc" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f59e0b" stop-opacity="0.9"/><stop offset="0.5" stop-color="#f59e0b" stop-opacity="0.15"/><stop offset="1" stop-color="#f59e0b" stop-opacity="0"/></linearGradient>
'''
    body = squircle("url(#bg)")
    body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#warm)"/>'
    body += glass_core(CX, CY, 520, "glassfill", "#64748b", 0.55, "rimc", spec_alpha=0.9, shadow_alpha=0.22)
    body += spark(752, 292, color="#fbbf24")
    return wrap("10c-glass-frost", defs, body)


# 10d — Lens: the glass '#' magnifies a Markdown page beneath it (light + reader in one)
def v10d_lens():
    defs = COMMON + '''
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbf8f1"/><stop offset="1" stop-color="#e6e1d6"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.40"/><stop offset="1" stop-color="#dbeafe" stop-opacity="0.25"/></linearGradient>
  <linearGradient id="rimd" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f59e0b" stop-opacity="0.95"/><stop offset="0.5" stop-color="#f59e0b" stop-opacity="0.2"/><stop offset="1" stop-color="#f59e0b" stop-opacity="0"/></linearGradient>
'''
    body = squircle("url(#bg)")
    body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#warm)"/>'
    # page text across the icon (first line = heading); faint outside the glass, dark inside it
    lines = [0.6, 0.9, 0.74, 0.86, 0.52, 0.88, 0.7]
    body += doc_lines(200, 236, 620, 84, lines, "#8c94a3", 0.32, 24)
    body += '<clipPath id="lensclip">' + hash_bars(CX, CY, 520) + '</clipPath>'
    body += '<g clip-path="url(#lensclip)">' + doc_lines(200, 236, 620, 84, lines, "#1f2937", 0.9, 24) + '</g>'
    body += glass_core(CX, CY, 520, "glassfill", "#475569", 0.5, "rimd", spec_alpha=0.6, shadow_alpha=0.2)
    body += spark(752, 292, color="#fbbf24")
    return wrap("10d-glass-lens", defs, body)


# 10e — Graphite: monochrome clear glass with neutral white light (most Apple-like)
def v10e_graphite():
    defs = COMMON + '''
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2f36"/><stop offset="1" stop-color="#101216"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.34"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.12"/></linearGradient>
  <linearGradient id="rime" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.95"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0.2"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></linearGradient>
  <radialGradient id="orbw" cx="0.3" cy="0.3" r="0.8"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#e2e8f0"/></radialGradient>
  <radialGradient id="cool" cx="0.8" cy="0.18" r="0.6"><stop offset="0" stop-color="#ffffff" stop-opacity="0.30"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>
'''
    body = squircle("url(#bg)")
    body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#cool)"/>'
    body += glass_core(CX, CY, 520, "glassfill", "#ffffff", 0.6, "rime", spec_alpha=0.55)
    body += ('<circle cx="770" cy="280" r="58" fill="#ffffff" opacity="0.6" filter="url(#spark)"/>'
             '<circle cx="770" cy="280" r="28" fill="url(#orbw)"/>')
    return wrap("10e-glass-graphite", defs, body)


# ---------------------------------------------------------------- Matched Frost / Ember pairs
# Same geometry, spark position and light direction; only background, glass opacity and outline
# colour change between the Default (Frost) and Dark (Ember) appearance.
CAPS = {"round": dict(rx=None, skew=False), "square": dict(rx=10, skew=True)}

FROST_DEFS = COMMON + '''
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f7f5f0"/><stop offset="1" stop-color="#cfc9bd"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.88"/><stop offset="1" stop-color="#e8eef7" stop-opacity="0.66"/></linearGradient>
  <linearGradient id="rimc" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f59e0b" stop-opacity="0.9"/><stop offset="0.5" stop-color="#f59e0b" stop-opacity="0.15"/><stop offset="1" stop-color="#f59e0b" stop-opacity="0"/></linearGradient>
'''
EMBER_DEFS = COMMON + '''
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#232a36"/><stop offset="1" stop-color="#0b0e14"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.40"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.16"/></linearGradient>
'''


def make_pair(cap):
    geo = CAPS[cap]

    def frost():
        body = squircle("url(#bg)")
        body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#warm)"/>'
        body += glass_core(CX, CY, 520, "glassfill", "#64748b", 0.55, "rimc", spec_alpha=0.9, shadow_alpha=0.22, **geo)
        body += spark(752, 292, color="#fbbf24")
        return wrap(f"pair-{cap}-frost", FROST_DEFS, body)

    def ember():
        body = squircle("url(#bg)")
        body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#warm)"/>'
        body += '<circle cx="250" cy="820" r="230" fill="#0ea5e9" opacity="0.18" filter="url(#blur)"/>'
        body += glass_core(CX, CY, 520, "glassfill", "#ffffff", 0.55, "rim", spec_alpha=0.5, **geo)
        body += spark(752, 292)
        return wrap(f"pair-{cap}-ember", EMBER_DEFS, body)

    frost.__name__ = f"pair_{cap}_frost"; ember.__name__ = f"pair_{cap}_ember"
    return frost, ember


PAIRS = make_pair("round") + make_pair("square")


# Frost, small-size rendition (16/32 px slots of the .icns): darker outline, more opaque glass,
# no specular sweep, bigger spark — so the light glass survives on a light Dock.
FROST_SMALL_DEFS = COMMON + '''
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f3efe6"/><stop offset="1" stop-color="#bfb8aa"/></linearGradient>
  <linearGradient id="glassfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="1"/><stop offset="1" stop-color="#dbe3ee" stop-opacity="1"/></linearGradient>
  <linearGradient id="rimc" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f59e0b" stop-opacity="1"/><stop offset="0.5" stop-color="#f59e0b" stop-opacity="0.2"/><stop offset="1" stop-color="#f59e0b" stop-opacity="0"/></linearGradient>
'''


def pair_round_frost_small():
    body = squircle("url(#bg)")
    body += f'<rect x="{P}" y="{P}" width="{S}" height="{S}" fill="url(#warm)"/>'
    body += hash_glyph(CX, CY + 22, 520, fill="#000", attrs='opacity="0.30" filter="url(#gshadow)"')
    body += hash_fill("gfill", CX, CY, 520, "url(#glassfill)")
    body += hash_ring("gring", CX, CY, 520, 12, "#334155", 0.85)
    body += hash_ring("grim", CX, CY, 520, 14, "url(#rimc)", 1.0)
    body += spark(752, 292, r=40, color="#f59e0b", glow=70)
    return wrap("pair-round-frost-small", FROST_SMALL_DEFS, body)

ALL = (v10a_ember, v10b_tide, v10c_frost, v10d_lens, v10e_graphite) + PAIRS + (pair_round_frost_small,)
