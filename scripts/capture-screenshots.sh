#!/usr/bin/env bash
# App Store product-evidence capture for Elderhub.
#
# Called by the shared renderer (~/ios/appstore-screenshots) as
#   capture-screenshots.sh <udid> <output-dir>
# on a leased headless simulator. The lease, the build and the install are the
# caller's job; this script only drives the app and saves named PNGs.
#
# Product evidence only. The paywall, the trial and anything that takes a
# purchase are deliberately not here: a monetization capture belongs in its own
# command so it cannot end up in an App Store set by accident.
set -euo pipefail

UDID="${1:?usage: capture-screenshots.sh <udid> <output-dir>}"
OUT="${2:?usage: capture-screenshots.sh <udid> <output-dir>}"
BUNDLE="com.jackwallner.aging"

mkdir -p "$OUT"

# The shared renderer leases the device and hands over its UDID; booting,
# building and installing are this script's job, and the lease stays the
# caller's to check in.
boot_and_install() {
    xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

    # A store page must not carry a real carrier name, a half battery or the
    # time the capture happened.
    xcrun simctl status_bar "$UDID" override \
        --time 9:41 --batteryState charged --batteryLevel 100 \
        --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true

    xcodegen generate >/dev/null
    xcodebuild -project Aging.xcodeproj -scheme Aging -configuration Debug \
        -destination "id=$UDID" build >/dev/null

    local app
    app="$(find ~/Library/Developer/Xcode/DerivedData/Aging-*/Build/Products/Debug-iphonesimulator \
        -maxdepth 1 -name 'Aging.app' | head -1)"
    [ -n "$app" ] || { echo "capture failed: no built Aging.app" >&2; exit 1; }
    xcrun simctl install "$UDID" "$app" >/dev/null
}

boot_and_install

# Every frame relaunches. The hub is one long scroll and the tiles below the
# fold are reached by swiping, so a frame that inherited the previous frame's
# scroll position would tap a different tile than the one it names.
launch() {
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" \
        -uitest-family YES -seedDemo YES >/dev/null
    sleep 4
}

tap() { axe tap --label "$1" --udid "$UDID" >/dev/null; sleep "${2:-2}"; }

# The setup checklist and a dismissed one are both legitimate states, so the
# hide is allowed to find nothing rather than failing the run.
tap_optional() { axe tap --label "$1" --udid "$UDID" >/dev/null 2>&1 || true; sleep "${2:-2}"; }

# Tiles carry a live count in their accessibility label ("Appointments. What's
# coming up, and what was said. Next: Sep 10, 2026 at 10:15 AM"), so an exact
# label would break the day the seed moves. Match the stable prefix and tap the
# centre of whatever it resolves to.
tap_prefix() {
    local prefix="$1"
    local point
    point="$(axe describe-ui --udid "$UDID" 2>/dev/null | /opt/homebrew/bin/python3.14 -c '
import json, sys
prefix = sys.argv[1]
found = []
def walk(node):
    label = node.get("AXLabel") or ""
    frame = node.get("frame") or {}
    if label.startswith(prefix) and frame.get("height"):
        found.append((frame["x"] + frame["width"] / 2, frame["y"] + frame["height"] / 2))
    for child in node.get("children") or []:
        walk(child)
tree = json.load(sys.stdin)
for node in (tree if isinstance(tree, list) else [tree]):
    walk(node)
onscreen = [p for p in found if p[1] > 0]
if not onscreen:
    raise SystemExit(1)
print(int(onscreen[0][0]), int(onscreen[0][1]))
' "$prefix")" || { echo "capture failed: no element starting with '$prefix'" >&2; exit 1; }
    axe tap -x "${point% *}" -y "${point#* }" --udid "$UDID" >/dev/null
    sleep "${2:-2}"
}

swipe_up() {
    axe swipe --start-x 200 --start-y 700 --end-x 200 --end-y 300 --udid "$UDID" >/dev/null
    sleep 1.5
}

# The settle is not politeness. A shot taken straight after the push that
# opened the screen has caught the Dynamic Island drawn as a black pill over
# the status bar, which reads as a rendering fault on a store page. It is
# intermittent, so the frame is checked and retaken rather than trusted: the
# strip where the island sits must be as light as the rest of the status bar.
shoot() {
    local name="$1" attempt
    for attempt in 1 2 3; do
        sleep 2
        xcrun simctl io "$UDID" screenshot "$OUT/$name" >/dev/null
        if python3 - "$OUT/$name" <<'PYEOF'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
width, _ = image.size
strip = image.crop((int(width * 0.35), 10, int(width * 0.65), 90))
dark = sum(1 for r, g, b in strip.getdata() if r < 60 and g < 60 and b < 60)
raise SystemExit(1 if dark > strip.width * 4 else 0)
PYEOF
        then
            echo "  captured $name"
            return 0
        fi
        echo "  retaking $name, the status bar was covered"
    done
    echo "capture failed: $name kept the Dynamic Island over the status bar" >&2
    exit 1
}

# A blank or hung launch must not be saved as evidence, so every frame is taken
# from a screen that has already answered describe-ui with a label we asked for.
require_label() {
    local needle="$1"
    local tree
    for _ in $(seq 1 20); do
        # Written to a variable rather than piped straight into grep: `grep -q`
        # closes the pipe on its first match, `axe` dies of SIGPIPE, and under
        # `pipefail` a successful match reads as a failed check.
        tree="$(axe describe-ui --udid "$UDID" 2>/dev/null || true)"
        case "$tree" in
            *"$needle"*) return 0 ;;
        esac
        sleep 1
    done
    echo "capture failed: never saw '$needle' on screen" >&2
    exit 1
}

echo "01 today, everyone"
launch
require_label "Emergency cards"
shoot 01_today_everyone.png

echo "02 emergency card"
launch
require_label "Emergency cards"
tap "Eleanor Wallner"
require_label "Blood type"
shoot 02_emergency_card.png

echo "03 medications"
launch
tap "Care"
tap "Eleanor Wallner"
tap_optional "Hide the whole setup list"
require_label "Medications"
shoot 03_medications.png

echo "04 tasks"
launch
tap "Care"
tap "Eleanor Wallner"
tap_optional "Hide the whole setup list"
swipe_up
tap "Tasks. Shared to-dos for the family. 4 open · 2 due"
require_label "Everyone"
shoot 04_tasks.png

echo "05 bills"
launch
tap "Care"
tap "Eleanor Wallner"
tap_optional "Hide the whole setup list"
swipe_up
tap "Bills. What's due, and who paid it. 4 open · 1 overdue"
require_label "Still to pay"
shoot 05_bills.png

echo "06 appointments"
launch
tap "Care"
tap "Eleanor Wallner"
tap_optional "Hide the whole setup list"
swipe_up
swipe_up
tap_prefix "Appointments."
require_label "Appointments"
shoot 06_appointments.png

echo "captured 6 frames into $OUT"
