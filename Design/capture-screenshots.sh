#!/usr/bin/env bash
# capture-screenshots.sh — App Store listing screenshot helper.
#
# Boots the simulators Apple requires for an iPhone + iPad listing,
# pins the status bar to the canonical marketing convention (9:41,
# full battery, wifi), and captures named screenshots into
# Design/listing-screenshots/{device}/{name}.png.
#
# Usage:
#   ./Design/capture-screenshots.sh boot iphone-6.5      # boot + pin status
#   ./Design/capture-screenshots.sh boot ipad-13         # boot + pin status
#   ./Design/capture-screenshots.sh appearance dark      # active sim → dark
#   ./Design/capture-screenshots.sh appearance light     # active sim → light
#   ./Design/capture-screenshots.sh shot 01-library      # save screenshot
#   ./Design/capture-screenshots.sh shot 02-form-dark    # convention: -dark suffix
#   ./Design/capture-screenshots.sh done                 # restore status bar
#
# Workflow:
#   1. boot iphone-6.5  → simulator launches, status bar pinned (auto-creates
#                          the sim if it isn't provisioned yet)
#   2. Open SwiftPDF in Xcode, target this simulator, hit Run
#   3. Drive the UI by hand; between captures, run `shot <name>`
#   4. appearance dark → re-capture key screens
#   5. boot ipad-13 → repeat 2–4 for iPad shots
#   6. done → status bar overrides cleared on every booted sim
#
# Required device sizes (Apple App Store Connect, as of 2026-05):
#   iphone-6.5 (iPhone Air,         6.5" display)  — REQUIRED for iPhone listings
#   ipad-13    (iPad Pro 13" M4,    2064×2752)     — REQUIRED for iPad listings
#
# Per-device runtime: the iPhone Air runs on iOS 26.5 (the device class
# was introduced in that release); the iPad is pinned to iOS 18.6 to match
# the physical iPad's OS version, so the listing screenshots match what
# real iPad users see.
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

# Short-name → (simulator device name, runtime, SimDeviceType ID for auto-create).
# Add new entries to all three functions if Apple's required device list
# changes. (Three functions instead of an associative array because macOS
# ships bash 3.2 — no `declare -A`.)
device_name_for() {
    case "$1" in
        iphone-6.5) printf 'iPhone Air' ;;
        ipad-13)    printf 'iPad Pro 13-inch (M4)' ;;
        *)          return 1 ;;
    esac
}

device_runtime_for() {
    case "$1" in
        iphone-6.5) printf 'iOS 26.5' ;;
        ipad-13)    printf 'iOS 18.6' ;;
        *)          return 1 ;;
    esac
}

device_type_id_for() {
    case "$1" in
        iphone-6.5) printf 'com.apple.CoreSimulator.SimDeviceType.iPhone-Air' ;;
        ipad-13)    printf 'com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB' ;;
        *)          return 1 ;;
    esac
}

runtime_id_for() {
    # iOS 26.4 → com.apple.CoreSimulator.SimRuntime.iOS-26-4
    local rt="$1"
    local suffix
    suffix="$(printf '%s' "$rt" | sed 's/^iOS //; s/\./-/g')"
    printf 'com.apple.CoreSimulator.SimRuntime.iOS-%s' "$suffix"
}

KNOWN_SHORTS="iphone-6.5 ipad-13"

usage() {
    sed -n 's/^# \{0,1\}//; 3,30p' "$0"
    exit 1
}

# Look up a sim UUID by device name + runtime. If the device isn't yet
# provisioned, create it via `simctl create`. Errors with a useful message
# if the underlying runtime isn't installed (Xcode → Settings → Components).
#
# Uses `grep -F` (fixed-string match) because device names like
# "iPad Pro 13-inch (M4)" contain literal parens that would otherwise
# get treated as regex grouping operators by awk/grep — causing the lookup
# to silently miss the existing simulator and fall through to the
# auto-create branch (which is how this script accumulated 3 duplicate
# iPad sims before the bug was caught).
resolve_udid() {
    local short="$1"
    local name runtime type_id udid
    name="$(device_name_for "$short")"
    runtime="$(device_runtime_for "$short")"
    type_id="$(device_type_id_for "$short")"

    # Find the FIRST line listing this device name followed by " (" (the
    # opener for the UDID parens), then extract the UUID-shaped substring.
    # `grep -F` keeps the parens in the name literal; `grep -oE` matches
    # the canonical 8-4-4-4-12 hex UUID and ignores the trailing "(state)"
    # parens.
    udid="$(xcrun simctl list devices "$runtime" 2>/dev/null \
        | grep -F "    $name (" \
        | head -1 \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
        | head -1)"

    if [[ -n "$udid" ]]; then
        printf '%s' "$udid"
        return 0
    fi

    # Not provisioned — auto-create. Requires the runtime itself to be
    # installed; if not, surface a clear error.
    if ! xcrun simctl list runtimes 2>/dev/null | grep -q "^$runtime "; then
        echo "error: '$runtime' runtime not installed — Xcode → Settings → Components" >&2
        exit 1
    fi
    echo "Creating '$name' on $runtime..." >&2
    udid="$(xcrun simctl create "$name" "$type_id" "$(runtime_id_for "$runtime")" 2>&1)"
    if [[ -z "$udid" || ! "$udid" =~ ^[A-F0-9-]+$ ]]; then
        echo "error: simctl create failed: $udid" >&2
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
    udid="$(resolve_udid "$short")"

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
