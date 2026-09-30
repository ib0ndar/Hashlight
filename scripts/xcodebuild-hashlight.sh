#!/bin/bash
set -euo pipefail

# The supported local command-line entry point for Hashlight builds and tests.
# It keeps one DerivedData location per checkout and removes development registrations both before
# and after xcodebuild. Set HASHLIGHT_KEEP_REGISTRATION=1 only while intentionally testing Quick Look.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGISTRATION_MANAGER="$SCRIPT_DIR/manage-dev-registrations.sh"
DERIVED_DATA_PATH="$PROJECT_DIR/build/Xcode/DerivedData"
KEEP_REGISTRATION="${HASHLIGHT_KEEP_REGISTRATION:-0}"
BUILD_CONFIGURATION="Debug"

if [ "$KEEP_REGISTRATION" != "0" ] && [ "$KEEP_REGISTRATION" != "1" ]; then
    echo "ERROR: HASHLIGHT_KEEP_REGISTRATION must be 0 or 1." >&2
    exit 2
fi

arguments=("$@")
argument_index=0
while [ "$argument_index" -lt "${#arguments[@]}" ]; do
    argument="${arguments[$argument_index]}"
    case "$argument" in
        -derivedDataPath|-derivedDataPath=*)
            echo "ERROR: Do not pass -derivedDataPath. Hashlight uses $DERIVED_DATA_PATH" >&2
            exit 2
            ;;
        -configuration)
            argument_index=$((argument_index + 1))
            if [ "$argument_index" -ge "${#arguments[@]}" ]; then
                echo "ERROR: -configuration requires a value." >&2
                exit 2
            fi
            BUILD_CONFIGURATION="${arguments[$argument_index]}"
            ;;
        -configuration=*)
            BUILD_CONFIGURATION="${argument#-configuration=}"
            ;;
    esac
    argument_index=$((argument_index + 1))
done

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "ERROR: Full Xcode is not selected. Run:" >&2
    echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

"$REGISTRATION_MANAGER" unregister --quiet

cleanup_on_exit() {
    local command_status=$?
    local cleanup_status=0
    trap - EXIT
    if [ "$KEEP_REGISTRATION" != "1" ]; then
        "$REGISTRATION_MANAGER" unregister --quiet || cleanup_status=$?
    else
        echo "Keeping the current Hashlight development registration for intentional Quick Look testing."
        echo "Clean it afterwards with: ./scripts/manage-dev-registrations.sh unregister"
    fi
    if [ "$command_status" -ne 0 ]; then
        exit "$command_status"
    fi
    exit "$cleanup_status"
}
trap cleanup_on_exit EXIT

mkdir -p "$DERIVED_DATA_PATH"
exec_path="$(xcrun --find xcodebuild)"
"$exec_path" \
    -project "$PROJECT_DIR/Hashlight.xcodeproj" \
    -scheme Hashlight \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "$@" || {
        command_status=$?
        exit "$command_status"
    }

if [ "$KEEP_REGISTRATION" = "1" ]; then
    app_path="$PROJECT_DIR/build/Xcode/$BUILD_CONFIGURATION/Hashlight.app"
    if [ ! -d "$app_path" ]; then
        echo "ERROR: Cannot keep a registration because no app exists at $app_path" >&2
        exit 1
    fi
    lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    "$lsregister" -f -R -trusted "$app_path"
    "$REGISTRATION_MANAGER" refresh >/dev/null
fi
