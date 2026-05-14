#!/usr/bin/env bash
# capture-screenshots.sh — App Store listing screenshot helper.
#
# Boots the simulators Apple requires for an iPhone + iPad listing,
# pins the status bar to the canonical marketing convention (9:41,
# full battery, wifi), and captures named screenshots into
# Design/listing-screenshots/{device}/{name}.png.
#
# Usage:
#   ./Design/capture-screenshots.sh boot iphone-6.9      # boot + pin status
#   ./Design/capture-screenshots.sh boot ipad-13         # boot + pin status
#   ./Design/capture-screenshots.sh appearance dark      # active sim → dark
#   ./Design/capture-screenshots.sh appearance light     # active sim → light
#   ./Design/capture-screenshots.sh shot 01-library      # save screenshot
#   ./Design/capture-screenshots.sh shot 02-form-dark    # convention: -dark suffix
#   ./Design/capture-screenshots.sh done                 # restore status bar
#
# Workflow:
#   1. boot iphone-6.9  → simulator launches, status bar pinned
#   2. Open SwiftPDF in Xcode, target this simulator, hit Run
#   3. Drive the UI by hand; between captures, run `shot <name>`
#   4. appearance dark → re-capture key screens
#   5. boot ipad-13 → repeat 2–4 for iPad shots
#   6. done → status bar overrides cleared on every booted sim
#
# Required device sizes (Apple App Store, as of 2026-05):
#   iphone-6.9 (iPhone 16 Pro Max, 1320×2868)  — REQUIRED for iPhone listings
#   ipad-13    (iPad Pro 13" M4,   2064×2752)  — REQUIRED for iPad listings
#
# Output filenames:
#   01-library.png      02-form.png     03-signature.png ...
#   01-library-dark.png 02-form-dark.png ...
# Leading-number controls display order in App Store Connect. Pair light/dark
# variants with the `-dark` suffix.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_BASE="$REPO_ROOT/Design/listing-screenshots"
STATE_FILE="${TMPDIR:-/tmp}/swiftpdf-screenshot-session"
RUNTIME="iOS 18.6"

# Short-name → simulator device name. Add new entries to `device_name_for`
# below if Apple's required device list changes. (Using a function instead
# of an associative array because macOS ships bash 3.2 — no `declare -A`.)
device_name_for() {
    case "$1" in
        iphone-6.9) printf 'iPhone 16 Pro Max' ;;
        ipad-13)    printf 'iPad Pro 13-inch (M4)' ;;
        *)          return 1 ;;
    esac
}

KNOWN_SHORTS="iphone-6.9 ipad-13"

usage() {
    sed -n 's/^# \{0,1\}//; 3,30p' "$0"
    exit 1
}

# Look up a sim UUID by device name + runtime. Errors with a useful message
# if the named device isn't installed.
resolve_udid() {
    local name="$1"
    local udid
    udid="$(xcrun simctl list devices "$RUNTIME" 2>/dev/null \
        | awk -F '[()]' -v name="$name" '
            $0 ~ ("^[[:space:]]*" name " \\(") { print $2; exit }
          ')"
    if [[ -z "$udid" ]]; then
        echo "error: no '$name' on '$RUNTIME' — install via Xcode → Settings → Components" >&2
        exit 1
    fi
    printf '%s' "$udid"
}

# Apple's marketing-convention status bar: 9:41, charged, full battery,
# active cellular at full bars, wifi at full bars.
pin_status_bar() {
    local udid="$1"
    xcrun simctl status_bar "$udid" override \
        --time "9:41" \
        --dataNetwork "wifi" \
        --wifiMode "active" \
        --wifiBars 3 \
        --cellularMode "active" \
        --cellularBars 4 \
        --batteryState "charged" \
        --batteryLevel 100
}

boot_device() {
    local short="$1"
    local name
    if ! name="$(device_name_for "$short")"; then
        echo "error: unknown device '$short' (known: $KNOWN_SHORTS)" >&2
        exit 1
    fi
    local udid
    udid="$(resolve_udid "$name")"

    if ! xcrun simctl list devices | grep -q "$udid.*Booted"; then
        echo "Booting $name ($udid)..."
        xcrun simctl boot "$udid"
    fi
    open -a Simulator --args -CurrentDeviceUDID "$udid" || true
    sleep 1
    pin_status_bar "$udid"

    # Record current session — `shot` reads this to know where to save.
    printf '%s\n%s\n' "$short" "$udid" > "$STATE_FILE"

    mkdir -p "$OUT_BASE/$short"
    echo "✓ $short ready ($udid). Output → $OUT_BASE/$short/"
    echo "  Hit Run in Xcode targeting '$name', then capture with:"
    echo "    $0 shot <name>"
}

current_udid() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "error: no active session — run '$0 boot <device>' first" >&2
        exit 1
    fi
    sed -n '2p' "$STATE_FILE"
}

current_short() {
    sed -n '1p' "$STATE_FILE"
}

shot() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        echo "error: shot needs a name (e.g. '01-library')" >&2
        exit 1
    fi
    local udid short out
    udid="$(current_udid)"
    short="$(current_short)"
    out="$OUT_BASE/$short/${name}.png"
    xcrun simctl io "$udid" screenshot "$out"
    echo "✓ $out"
}

appearance() {
    local mode="${1:-}"
    if [[ "$mode" != "light" && "$mode" != "dark" ]]; then
        echo "error: appearance needs 'light' or 'dark'" >&2
        exit 1
    fi
    local udid
    udid="$(current_udid)"
    xcrun simctl ui "$udid" appearance "$mode"
    echo "✓ appearance → $mode"
}

done_session() {
    # Clear status bar overrides on every booted sim. Safe even if no session.
    local booted
    booted="$(xcrun simctl list devices booted 2>/dev/null \
        | awk -F '[()]' '/Booted/ { print $2 }')"
    for udid in $booted; do
        xcrun simctl status_bar "$udid" clear || true
    done
    rm -f "$STATE_FILE"
    echo "✓ status bar overrides cleared, session ended"
}

cmd="${1:-}"
shift || true

case "$cmd" in
    boot)        boot_device "$@" ;;
    shot)        shot "$@" ;;
    appearance)  appearance "$@" ;;
    done)        done_session ;;
    *)           usage ;;
esac
