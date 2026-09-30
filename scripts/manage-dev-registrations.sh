#!/bin/bash
set -euo pipefail

# Audit and unregister Hashlight development bundles without deleting any files.
#
# Xcode's macOS build pipeline unconditionally runs Launch Services registration for app
# products. Xcode 27's LSRegisterURL.xcspec exposes no option to disable that synthesized task,
# so local builds must be isolated by bundle ID and explicitly unregistered when they finish.

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# Only Hashlight's own identities; other apps' registrations are never touched.
RELEASE_APP_ID="io.github.ib0ndar.hashlight"
DEBUG_APP_ID="io.github.ib0ndar.hashlight.debug"
RELEASE_EXTENSION_ID="io.github.ib0ndar.hashlight.QuickLook"
DEBUG_EXTENSION_ID="io.github.ib0ndar.hashlight.debug.QuickLook"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/manage-dev-registrations.sh status
  ./scripts/manage-dev-registrations.sh unregister [--include-installed] [--quiet]
  ./scripts/manage-dev-registrations.sh refresh

status
  Lists every Hashlight app/Quick Look record currently visible to Launch Services or PlugInKit.

unregister
  Unregisters Hashlight copies outside /Applications and /System. It never deletes an app, build
  directory, source checkout, worktree, DMG, or Trash item. Use --include-installed only when
  deliberately removing the installed release app's registration as well.

refresh
  Asks Quick Look to reload its generator list. It does not clear the thumbnail cache.
EOF
}

require_tools() {
    if [ ! -x "$LSREGISTER" ]; then
        echo "ERROR: Launch Services tool not found at $LSREGISTER" >&2
        exit 1
    fi
    if ! command -v pluginkit >/dev/null 2>&1; then
        echo "ERROR: pluginkit is unavailable on this macOS installation." >&2
        exit 1
    fi
}

launch_services_records() {
    local dump_path
    dump_path="$(mktemp -t hashlight-lsregister)"
    "$LSREGISTER" -dump >"$dump_path"

    awk -v release_app="$RELEASE_APP_ID" \
        -v debug_app="$DEBUG_APP_ID" \
        -v release_extension="$RELEASE_EXTENSION_ID" \
        -v debug_extension="$DEBUG_EXTENSION_ID" '
        function emit() {
            if (path == "" || identifier == "") return
            if (identifier == release_app || identifier == debug_app) {
                print "app\t" identifier "\t" path
            } else if (identifier == release_extension || identifier == debug_extension) {
                print "extension\t" identifier "\t" path
            }
        }
        /^-+$/ {
            emit()
            path = ""
            identifier = ""
            next
        }
        /^path:[[:space:]]/ {
            value = $0
            sub(/^path:[[:space:]]*/, "", value)
            sub(/[[:space:]]+\(0x[[:xdigit:]]+\)$/, "", value)
            path = value
            next
        }
        /^identifier:[[:space:]]/ {
            value = $0
            sub(/^identifier:[[:space:]]*/, "", value)
            identifier = value
            next
        }
        END { emit() }
    ' "$dump_path"

    rm -f "$dump_path"
}

plugin_records() {
    local identifier line plugin_path
    for identifier in "$RELEASE_EXTENSION_ID" "$DEBUG_EXTENSION_ID"; do
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            plugin_path="${line##*$'\t'}"
            case "$plugin_path" in
                /*) printf 'extension\t%s\t%s\n' "$identifier" "$plugin_path" ;;
            esac
        done < <(pluginkit -m -A -D -v -i "$identifier" 2>/dev/null || true)
    done
}

all_records() {
    launch_services_records
    plugin_records
}

is_installed_location() {
    case "$1" in
        /Applications/*|/System/*) return 0 ;;
        *) return 1 ;;
    esac
}

show_status() {
    local records_path
    records_path="$(mktemp -t hashlight-registrations)"
    all_records | sort -u >"$records_path"

    if [ ! -s "$records_path" ]; then
        echo "No Hashlight app or Quick Look extension registrations found."
        rm -f "$records_path"
        return 0
    fi

    printf '%-10s %-36s %s\n' "KIND" "BUNDLE ID" "PATH"
    while IFS=$'\t' read -r kind identifier bundle_path; do
        printf '%-10s %-36s %s\n' "$kind" "$identifier" "$bundle_path"
    done <"$records_path"
    rm -f "$records_path"
}

unregister_records() {
    local include_installed="$1"
    local quiet="$2"
    local records_path remaining_path changed clean pass kind_order kind identifier bundle_path embedded_extension
    records_path="$(mktemp -t hashlight-registrations)"
    remaining_path="$(mktemp -t hashlight-registrations-remaining)"
    changed=0
    clean=0

    # Xcode registers both the containing app and its embedded extension. Remove extension
    # records first, then apps, and retry: Launch Services can briefly retain or
    # reconstruct the parent record while PlugInKit is dropping the embedded extension.
    # Individual unregister commands may legitimately return nonzero when another command in
    # the same pass already removed that record, so the final audit determines success.
    for pass in 1 2 3 4; do
        all_records | sort -u >"$records_path"
        : >"$remaining_path"
        while IFS=$'\t' read -r kind identifier bundle_path; do
            [ -n "$bundle_path" ] || continue
            if [ "$include_installed" != "1" ] && is_installed_location "$bundle_path"; then
                if [ "$quiet" != "1" ] && [ "$pass" = "1" ]; then
                    echo "Keeping installed registration: $bundle_path"
                fi
                continue
            fi
            printf '%s\t%s\t%s\n' "$kind" "$identifier" "$bundle_path" >>"$remaining_path"
        done <"$records_path"

        if [ ! -s "$remaining_path" ]; then
            clean=1
            break
        fi

        for kind_order in extension app; do
            while IFS=$'\t' read -r kind identifier bundle_path; do
                [ "$kind" = "$kind_order" ] || continue
                [ -n "$bundle_path" ] || continue

                if [ "$kind" = "app" ]; then
                    embedded_extension="$bundle_path/Contents/PlugIns/HashlightQuickLook.appex"
                    if [ -d "$embedded_extension" ]; then
                        pluginkit -r "$embedded_extension" >/dev/null 2>&1 || true
                    fi
                else
                    pluginkit -r "$bundle_path" >/dev/null 2>&1 || true
                fi

                "$LSREGISTER" -u "$bundle_path" >/dev/null 2>&1 || true
                if [ "$quiet" != "1" ] && [ "$pass" = "1" ]; then
                    echo "Requested unregistration of $identifier at $bundle_path"
                fi
                changed=1
            done <"$remaining_path"
        done
    done

    if [ "$clean" != "1" ]; then
        all_records | sort -u >"$records_path"
        : >"$remaining_path"
        while IFS=$'\t' read -r kind identifier bundle_path; do
            [ -n "$bundle_path" ] || continue
            if [ "$include_installed" != "1" ] && is_installed_location "$bundle_path"; then
                continue
            fi
            printf '%s\t%s\t%s\n' "$kind" "$identifier" "$bundle_path" >>"$remaining_path"
        done <"$records_path"
    fi

    rm -f "$records_path"
    if [ "$changed" = "0" ] && [ "$quiet" != "1" ]; then
        echo "No removable Hashlight development registrations found."
    fi
    if [ "$clean" != "1" ] && [ -s "$remaining_path" ]; then
        echo "ERROR: Hashlight development registrations remain after cleanup:" >&2
        while IFS=$'\t' read -r kind identifier bundle_path; do
            printf '  %s: %s (%s)\n' "$kind" "$bundle_path" "$identifier" >&2
        done <"$remaining_path"
        rm -f "$remaining_path"
        return 1
    fi
    rm -f "$remaining_path"
}

require_tools

command_name="${1:-status}"
case "$command_name" in
    status)
        [ "$#" -eq 1 ] || { usage >&2; exit 2; }
        show_status
        ;;
    unregister)
        shift
        include_installed=0
        quiet=0
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --include-installed) include_installed=1 ;;
                --quiet) quiet=1 ;;
                *) usage >&2; exit 2 ;;
            esac
            shift
        done
        unregister_records "$include_installed" "$quiet"
        ;;
    refresh)
        [ "$#" -eq 1 ] || { usage >&2; exit 2; }
        qlmanage -r
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
