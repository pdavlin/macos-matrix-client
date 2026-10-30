#!/bin/bash
# ios-sim-destination.sh — print an xcodebuild -destination for an iPhone
# simulator.
#
# Order:
#   1. IOS_SIM_DESTINATION from the environment, as-is
#   2. "iPhone 17", if `xcrun simctl list devices available` has one
#   3. the first available iPhone simulator, by UDID
# Fails with a clear message if no iPhone simulator is available.
#
# Used by scripts/test.sh and the CI workflow.
#
# Usage: destination="$(scripts/ios-sim-destination.sh)"

set -euo pipefail

if [[ -n "${IOS_SIM_DESTINATION:-}" ]]; then
    echo "$IOS_SIM_DESTINATION"
    exit 0
fi

devices="$(xcrun simctl list devices available)"

if grep -Eq '^ +iPhone 17 \(' <<<"$devices"; then
    echo "platform=iOS Simulator,name=iPhone 17"
    exit 0
fi

udid="$(grep -E '^ +iPhone ' <<<"$devices" | head -n 1 \
    | grep -Eo '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' || true)"

if [[ -z "$udid" ]]; then
    echo "error: no available iPhone simulator. Install an iOS Simulator" >&2
    echo "runtime with: xcodebuild -downloadPlatform iOS" >&2
    exit 1
fi

echo "platform=iOS Simulator,id=${udid}"
