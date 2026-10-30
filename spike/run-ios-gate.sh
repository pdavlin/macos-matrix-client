#!/bin/bash
# MATRIX-87 — iOS timeline regression gate, simulator pass.
#
# Builds the iOS app (Debug, simulator), creates a throwaway simulator, runs
# the app in its DEBUG `-TimelineGate` mode, copies the JSON dumps out of the
# app's Documents, deletes the simulator, and exits on the verdict.
#
#   spike/run-ios-gate.sh                          # dumps to spike/results/ios
#   spike/run-ios-gate.sh --out /tmp/dumps
#   spike/run-ios-gate.sh --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-17
#   spike/run-ios-gate.sh --udid <UDID>            # an existing simulator, kept
#
# The simulator pass scores counts and anchor positions only. Frame numbers
# need a device: see spike/GATE.md, "iOS". This is the same harness the
# `TimelineGateTests` XCTest runs; it exists because a machine whose XCTest
# runner cannot start (xcodebuild -checkFirstLaunchStatus exits 69) can still
# boot a simulator and launch an app.
#
# Exit codes: 0 every bar passed, 1 a bar failed, 3 the run refused to
# measure (the Mac gate's REFUSED code), 2 the harness did not finish.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/spike/results/ios"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
BUNDLE_ID="io.davlin.matrixclient.ios"
UDID=""
KEEP_SIMULATOR=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT_DIR="$2"; shift 2 ;;
        --device-type) DEVICE_TYPE="$2"; shift 2 ;;
        --udid) UDID="$2"; KEEP_SIMULATOR=1; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if [[ -d /Applications/Xcode-beta.app ]]; then
        export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
    else
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
fi

WORK_DIR="$(mktemp -d -t timeline-ios-gate)"
BUILD_LOG="$WORK_DIR/build.log"
RUN_LOG="$WORK_DIR/run.log"

cleanup() {
    if [[ -n "$UDID" && "$KEEP_SIMULATOR" == 0 ]]; then
        xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "==> building MactrixiOS (Debug, simulator); log: $BUILD_LOG"
xcodebuild build \
    -project "$REPO_ROOT/Mactrix.xcodeproj" \
    -scheme MactrixiOS \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    CODE_SIGNING_ALLOWED=NO >"$BUILD_LOG" 2>&1
APP="$WORK_DIR/DerivedData/Build/Products/Debug-iphonesimulator/Mactrix.app"

if [[ -z "$UDID" ]]; then
    echo "==> creating a $DEVICE_TYPE simulator"
    UDID="$(xcrun simctl create "timeline-gate-$$" "$DEVICE_TYPE")"
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"

echo "==> running the gate; log: $RUN_LOG"
# The app exits with the verdict, but `simctl launch` does not pass the
# status on, so the verdict is read from the log. A pty ends lines in CR.
xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE_ID" -TimelineGate 2>&1 \
    | tr -d '\r' >"$RUN_LOG" || true
grep '^\[TimelineGate\]' "$RUN_LOG" || true

CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
mkdir -p "$OUT_DIR"
if cp "$CONTAINER"/Documents/TimelineGate/*.json "$OUT_DIR"/; then
    echo "==> dumps copied to $OUT_DIR"
fi
# One run's dumps only: the next run starts from an empty folder.
rm -f "$CONTAINER"/Documents/TimelineGate/*.json

if grep -q '^\[TimelineGate\] refused' "$RUN_LOG"; then exit 3; fi
if grep -q '^\[TimelineGate\] PASS$' "$RUN_LOG"; then exit 0; fi
if grep -q '^\[TimelineGate\] FAIL$' "$RUN_LOG"; then exit 1; fi
echo "error: the harness did not finish; see $RUN_LOG" >&2
exit 2
