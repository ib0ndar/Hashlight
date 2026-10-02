#!/bin/bash
set -euo pipefail

# Rebuilds Hashlight/HighlightJS/ from a pinned highlight.js release: the browser build with its
# common languages, followed by every other language it ships, in one file that JavaScriptCore
# loads. Usage: scripts/update-highlightjs.sh 11.12.0
# Downloads @highlightjs/cdn-assets from the npm registry and checks the tarball against the
# registry's sha512 integrity before using it.

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 VERSION   (for example 11.12.0)" >&2
    exit 64
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$(dirname "$SCRIPT_DIR")/Hashlight/HighlightJS"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hashlight-highlightjs.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL "https://registry.npmjs.org/@highlightjs/cdn-assets/$VERSION" -o "$WORK_DIR/metadata.json"
TARBALL_URL="$(plutil -extract dist.tarball raw -o - "$WORK_DIR/metadata.json")"
INTEGRITY="$(plutil -extract dist.integrity raw -o - "$WORK_DIR/metadata.json")"
case "$INTEGRITY" in
    sha512-*) ;;
    *) echo "ERROR: unexpected integrity format: $INTEGRITY" >&2; exit 65 ;;
esac

curl -fsSL "$TARBALL_URL" -o "$WORK_DIR/package.tgz"
ACTUAL="sha512-$(openssl dgst -sha512 -binary "$WORK_DIR/package.tgz" | base64)"
if [ "$ACTUAL" != "$INTEGRITY" ]; then
    echo "ERROR: tarball integrity mismatch" >&2
    exit 65
fi
tar -xzf "$WORK_DIR/package.tgz" -C "$WORK_DIR"
PACKAGE="$WORK_DIR/package"

# The common build registers its languages from `grmr_*` keys, turning the first `_` into `-`
# (grmr_php_template → php-template). Those are not appended a second time.
COMMON="$(grep -o 'grmr_[a-z0-9_]*' "$PACKAGE/highlight.min.js" | sort -u | sed -e 's/^grmr_//' -e 's/_/-/')"

mkdir -p "$OUTPUT_DIR"
BUNDLE="$WORK_DIR/highlight.min.js"
{
    printf '/* highlight.js %s with all of its languages, assembled for Hashlight by\n' "$VERSION"
    printf '   scripts/update-highlightjs.sh from @highlightjs/cdn-assets@%s (%s).\n' "$VERSION" "$INTEGRITY"
    printf '   BSD-3-Clause; see LICENSE in this folder. */\n'
    cat "$PACKAGE/highlight.min.js"
    printf '\n'
    for language in "$PACKAGE"/languages/*.min.js; do
        name="$(basename "$language" .min.js)"
        if printf '%s\n' "$COMMON" | grep -qx "$name"; then
            continue
        fi
        cat "$language"
        printf '\n'
    done
} > "$BUNDLE"

# Load it in JavaScriptCore, as the app does, and report what it registered.
COUNT="$(osascript -l JavaScript - "$BUNDLE" <<'EOF'
ObjC.import("Foundation");
function run(argv) {
    const source = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
    (0, eval)(source);
    return hljs.listLanguages().length;
}
EOF
)"
if [ "$COUNT" -lt 190 ]; then
    echo "ERROR: the bundle registered only $COUNT languages" >&2
    exit 70
fi

cp "$BUNDLE" "$OUTPUT_DIR/highlight.min.js"
cp "$PACKAGE/LICENSE" "$OUTPUT_DIR/LICENSE"
echo "highlight.js $VERSION: $COUNT languages, $(wc -c < "$OUTPUT_DIR/highlight.min.js" | tr -d ' ') bytes in $OUTPUT_DIR"
