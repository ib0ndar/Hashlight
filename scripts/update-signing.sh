#!/bin/bash
set -euo pipefail

# Ed25519 signing of release disk images for Hashlight's in-app updater.
#
#   ./scripts/update-signing.sh generate            create the key in the login Keychain (once)
#   ./scripts/update-signing.sh check               exit 0 if the key is in the login Keychain
#   ./scripts/update-signing.sh public-key          print the public key for the app's build setting
#   ./scripts/update-signing.sh sign DMG            write DMG.sig next to DMG
#   ./scripts/update-signing.sh verify DMG [APP]    check DMG.sig against APP's built-in public key
#                                                   (default: the Release product)
#
# The private key lives only in the login Keychain (generic password, service below). It passes
# between `security` and the Swift helper through pipes, never as an argument. Back it up: without
# it, releases cannot be signed and installed copies cannot update themselves.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HELPER="$SCRIPT_DIR/update-signing.swift"
SERVICE="io.github.ib0ndar.hashlight.update-signing"
ACCOUNT="ed25519"
DEFAULT_APP="$PROJECT_DIR/build/Xcode/Release/Hashlight.app"

helper() {
    xcrun swift "$HELPER" "$@"
}

has_key() {
    security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1
}

private_key() {
    if ! has_key; then
        echo "ERROR: no update-signing key in the login Keychain (service $SERVICE)." >&2
        echo "       Run ./scripts/update-signing.sh generate once, or restore the key from its backup." >&2
        exit 1
    fi
    security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w
}

app_public_key() {
    /usr/libexec/PlistBuddy -c 'Print :HashlightUpdatePublicKey' "$1/Contents/Info.plist"
}

case "${1:-}" in
    generate)
        if has_key; then
            echo "ERROR: an update-signing key already exists; refusing to replace it." >&2
            exit 1
        fi
        secret="$(helper generate)"
        printf 'add-generic-password -s %s -a %s -w %s\n' "$SERVICE" "$ACCOUNT" "$secret" | security -i >/dev/null
        public="$(printf '%s' "$secret" | helper public-key)"
        unset secret
        echo "Created the update-signing key in the login Keychain (service $SERVICE)."
        echo "Public key: $public"
        echo "Set HASHLIGHT_UPDATE_PUBLIC_KEY to it in Hashlight.xcodeproj, and back up the private key."
        ;;
    check)
        if has_key; then
            echo "The update-signing key is in the login Keychain."
        else
            echo "ERROR: no update-signing key in the login Keychain (service $SERVICE)." >&2
            exit 1
        fi
        ;;
    public-key)
        private_key | helper public-key
        ;;
    sign)
        dmg="${2:?usage: sign DMG}"
        private_key | helper sign "$dmg" > "$dmg.sig"
        echo "Wrote $dmg.sig"
        ;;
    verify)
        dmg="${2:?usage: verify DMG [APP]}"
        app="${3:-$DEFAULT_APP}"
        helper verify "$dmg" "$dmg.sig" "$(app_public_key "$app")"
        ;;
    *)
        echo "usage: $0 generate | check | public-key | sign DMG | verify DMG [APP]" >&2
        exit 1
        ;;
esac
