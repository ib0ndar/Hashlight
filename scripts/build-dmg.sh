#!/bin/bash
set -euo pipefail

# Build the Hashlight DMG with a drag-to-Applications layout.
# Usage: ./scripts/build-dmg.sh
#
# dmgbuild writes the disk-image window layout (size, background, icon positions) straight into
# the image. It is installed on demand into build/dmg-venv. Nothing here opens or scripts Finder:
# on a Mac that opens new windows as tabs, Finder applies a layout window's bounds and view
# settings to the user's existing window.
#
# The image is ad-hoc signed and not notarized. NOTARIZE is accepted for compatibility and ignored.
#
# The finished image is signed for the in-app updater with the Ed25519 key in the login Keychain
# (scripts/update-signing.sh) into build/Hashlight.dmg.sig, and the signature is checked against
# the public key built into the app. Set HASHLIGHT_UNSIGNED_DMG=1 to skip that for a test image;
# installed copies cannot update to an image without its .sig.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGISTRATION_MANAGER="$SCRIPT_DIR/manage-dev-registrations.sh"
UPDATE_SIGNING="$SCRIPT_DIR/update-signing.sh"
SIGN_DMG=1
if [ "${HASHLIGHT_UNSIGNED_DMG:-0}" = "1" ]; then
    SIGN_DMG=0
fi
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_PRODUCTS_DIR="$PROJECT_DIR/build/Xcode/Release"
DMG_PATH="$BUILD_DIR/Hashlight.dmg"
APP_NAME="Hashlight.app"
VOLUME_NAME="Hashlight"
VENV_DIR="$BUILD_DIR/dmg-venv"
DMGBUILD_REQUIREMENTS=("dmgbuild==1.6.7" "ds_store==1.3.3" "mac_alias==2.2.3")

# Window size in points. The background image is generated at exactly this size, and
# scripts/dmg-settings.py receives the same values.
WIN_W=480
WIN_H=540

cleanup_on_exit() {
    local command_status=$?
    trap - EXIT
    # A release build is a development copy until it is installed. Never leave its embedded
    # Quick Look extension registered from build/, a mounted DMG, or another temporary path.
    "$REGISTRATION_MANAGER" unregister --quiet || true
    exit "$command_status"
}
trap cleanup_on_exit EXIT

if [ "$SIGN_DMG" = "1" ]; then
    # Fail before the long build rather than after it.
    "$UPDATE_SIGNING" check
fi

echo "==> Building Release (ad-hoc signed)..."
cd "$PROJECT_DIR"
# Start from an empty product: a Release test run embeds HashlightTests.xctest in the app's
# PlugIns, and an incremental build never removes it.
"$REGISTRATION_MANAGER" unregister --quiet
rm -rf "$RELEASE_PRODUCTS_DIR/$APP_NAME" "$RELEASE_PRODUCTS_DIR/$APP_NAME.dSYM"
# Ad-hoc signing builds the app and its sandboxed Quick Look extension without a Developer ID
# certificate; the extension's configured entitlements are still embedded. The generic
# destination builds every architecture in ARCHS; without it, xcodebuild picks this Mac and
# builds only its architecture.
"$SCRIPT_DIR/xcodebuild-hashlight.sh" -configuration Release \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS= CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build \
    2>&1 | tail -5

if [ ! -d "$RELEASE_PRODUCTS_DIR/$APP_NAME" ]; then
    echo "ERROR: Build failed - no app found"
    exit 1
fi

APP_BUNDLE="$RELEASE_PRODUCTS_DIR/$APP_NAME"
PLUGINS="$(ls "$APP_BUNDLE/Contents/PlugIns")"
if [ "$PLUGINS" != "HashlightQuickLook.appex" ]; then
    echo "ERROR: Unexpected app plug-ins: $(echo "$PLUGINS" | tr '\n' ' ')"
    exit 1
fi
for binary in "$APP_BUNDLE/Contents/MacOS/Hashlight" \
    "$APP_BUNDLE/Contents/PlugIns/HashlightQuickLook.appex/Contents/MacOS/HashlightQuickLook"; do
    archs="$(lipo -archs "$binary")"
    if [[ " $archs " != *" arm64 "* || " $archs " != *" x86_64 "* ]]; then
        echo "ERROR: $(basename "$binary") is not universal: $archs"
        exit 1
    fi
done

echo "==> Generating background image..."
python3 - "$BUILD_DIR" "$WIN_W" "$WIN_H" << 'PYEOF'
import struct, zlib, sys, os, math

build_dir = sys.argv[1]
W = int(sys.argv[2])   # 1x — must match window size exactly
H = int(sys.argv[3])

def create_png(width, height, pixels):
    def chunk(ct, data):
        c = ct + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    raw = b''
    for y in range(height):
        raw += b'\x00'
        for x in range(width):
            raw += bytes(pixels[y * width + x])
    idat = chunk(b'IDAT', zlib.compress(raw, 9))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend

def blend(bg, fg):
    """Alpha-blend fg onto bg."""
    a = fg[3] / 255.0
    return (
        int(bg[0] * (1 - a) + fg[0] * a),
        int(bg[1] * (1 - a) + fg[1] * a),
        int(bg[2] * (1 - a) + fg[2] * a),
        255
    )

# White background
pixels = [(255, 255, 255, 255)] * (W * H)

# Clean arrow between app icon (y=140) and Applications (y=400)
cx = W // 2
ac = (175, 180, 188, 255)

# Use distance-field approach for smooth anti-aliased arrow
def arrow_sdf(px, py):
    """Signed distance to arrow shape. Negative = inside."""
    # Shaft: rectangle from y=218 to y=295, half-width 5
    shaft_top, shaft_bot, shaft_hw = 218, 295, 5
    # Head: triangle from y=280 to y=340, half-width 30 at top tapering to 0
    head_top, head_bot, head_hw = 280, 338, 30

    dx = px - cx
    dy = py

    # Head triangle
    if dy >= head_top and dy <= head_bot:
        progress = (dy - head_top) / (head_bot - head_top)
        hw = head_hw * (1.0 - progress)
        dist_x = abs(dx) - hw
        if dy <= head_bot:
            # Inside or near triangle
            dist_y_top = head_top - dy
            dist_y_bot = dy - head_bot
            if dist_x <= 0:
                return max(dist_x, dist_y_top, dist_y_bot)
            else:
                return dist_x

    # Shaft rectangle
    if dy >= shaft_top and dy <= shaft_bot:
        dist_x = abs(dx) - shaft_hw
        dist_y = max(shaft_top - dy, dy - shaft_bot)
        if dist_x <= 0 and dist_y <= 0:
            return max(dist_x, dist_y)
        elif dist_x > 0 and dist_y > 0:
            return math.sqrt(dist_x**2 + dist_y**2)
        else:
            return max(dist_x, dist_y)

    # Outside both shapes - find nearest
    dists = []
    # Distance to shaft
    clamped_y = max(shaft_top, min(shaft_bot, dy))
    dist_to_shaft_x = abs(dx) - shaft_hw
    dist_to_shaft_y = abs(dy - clamped_y)
    if dist_to_shaft_x <= 0:
        dists.append(dist_to_shaft_y)
    else:
        dists.append(math.sqrt(dist_to_shaft_x**2 + dist_to_shaft_y**2))

    # Distance to head
    if dy >= head_top:
        clamped_hy = max(head_top, min(head_bot, dy))
        progress = (clamped_hy - head_top) / (head_bot - head_top)
        hw = head_hw * (1.0 - progress)
        dist_hx = abs(dx) - hw
        if dist_hx <= 0:
            dists.append(abs(dy - clamped_hy))
        else:
            dists.append(math.sqrt(dist_hx**2 + (dy - clamped_hy)**2))
    else:
        dists.append(abs(dy - head_top) + max(0, abs(dx) - head_hw))

    return min(dists) if dists else 999

for y in range(200, 355):
    for x in range(cx - 45, cx + 45):
        if 0 <= x < W and 0 <= y < H:
            d = arrow_sdf(x, y)
            if d < -1.0:
                pixels[y * W + x] = ac
            elif d < 1.0:
                # Anti-alias edge
                t = 0.5 - d * 0.5
                t = max(0.0, min(1.0, t))
                bg = pixels[y * W + x]
                pixels[y * W + x] = (
                    int(bg[0] * (1-t) + ac[0] * t),
                    int(bg[1] * (1-t) + ac[1] * t),
                    int(bg[2] * (1-t) + ac[2] * t),
                    255
                )

out_dir = os.path.join(build_dir, 'dmg-background')
os.makedirs(out_dir, exist_ok=True)
path = os.path.join(out_dir, 'background.png')
with open(path, 'wb') as f:
    f.write(create_png(W, H, pixels))
print(f"Background image: {path} ({W}x{H})")
PYEOF

echo "==> Preparing dmgbuild..."
if ! "$VENV_DIR/bin/python" -m pip freeze --disable-pip-version-check 2>/dev/null |
    grep -qx "${DMGBUILD_REQUIREMENTS[0]}"; then
    python3 -m venv --clear "$VENV_DIR"
    "$VENV_DIR/bin/python" -m pip install --quiet --disable-pip-version-check \
        "${DMGBUILD_REQUIREMENTS[@]}"
fi

echo "==> Creating DMG..."
rm -f "$DMG_PATH" "$DMG_PATH.sig"
"$VENV_DIR/bin/dmgbuild" -s "$SCRIPT_DIR/dmg-settings.py" \
    -D app="$RELEASE_PRODUCTS_DIR/$APP_NAME" \
    -D background="$BUILD_DIR/dmg-background/background.png" \
    -D window_width="$WIN_W" -D window_height="$WIN_H" \
    "$VOLUME_NAME" "$DMG_PATH"

if [ "$SIGN_DMG" = "1" ]; then
    echo "==> Signing the DMG for the in-app updater..."
    "$UPDATE_SIGNING" sign "$DMG_PATH"
    "$UPDATE_SIGNING" verify "$DMG_PATH" "$RELEASE_PRODUCTS_DIR/$APP_NAME"
else
    echo "==> HASHLIGHT_UNSIGNED_DMG=1: no update signature (installed copies cannot update to this image)"
fi

echo "==> Done! DMG at: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
