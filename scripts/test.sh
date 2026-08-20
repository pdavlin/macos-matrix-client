#!/bin/bash
# test.sh — run what is actually runnable today.
#
# Two suites:
#   1. `swift test --package-path MactrixLibrary` — the local SPM package's
#      unit tests. This is the real, working test suite.
#   2. `xcodebuild test -scheme MactrixTests` — the app test plan. As of
#      S-09 this fails with "test plan 'MactrixLibrary' could not be read".
#      That failure is pre-existing and known-broken; fixing the test plan
#      is story S-11, not this script's job. This script runs it, and if
#      (and only if) it fails with that known error, reports it as
#      "known-broken until S-11" and does NOT fail the script.
#      Any OTHER failure from this suite (a real regression, a different
#      error) DOES fail the script.
#
# TODO(S-11): once the MactrixTests test plan is repaired, remove the guard
# around step 2 and let its exit code fail the script like any other suite.
#
# Exits non-zero if the SPM suite fails, or if the app test suite fails with
# anything other than the known test-plan error.
#
# Usage: scripts/test.sh (runs correctly from any working directory)

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || dirname "$script_dir")"

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    : # respect the caller's DEVELOPER_DIR
elif [[ -d "/Applications/Xcode-beta.app" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
elif [[ -d "/Applications/Xcode.app" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
else
    echo "error: no usable Xcode found. Set DEVELOPER_DIR, or install" >&2
    echo "Xcode-beta.app or Xcode.app in /Applications." >&2
    exit 1
fi

echo "Using DEVELOPER_DIR=${DEVELOPER_DIR}"

cd "$repo_root"

echo "==> swift test --package-path MactrixLibrary"
swift test --package-path MactrixLibrary

echo "==> xcodebuild test -scheme MactrixTests (known-broken until S-11)"
app_test_log="$(mktemp)"
trap 'rm -f "$app_test_log"' EXIT

if xcodebuild test \
    -project Mactrix.xcodeproj \
    -scheme MactrixTests \
    -destination "platform=macOS,arch=arm64" \
    -disableAutomaticPackageResolution \
    >"$app_test_log" 2>&1; then
    echo "app test suite passed"
elif grep -q "test plan .*MactrixLibrary.* could not be read" "$app_test_log"; then
    echo "known-broken until S-11: MactrixTests test plan could not be read (TODO(S-11): remove this guard)"
else
    echo "app test suite failed with an unexpected error:" >&2
    cat "$app_test_log" >&2
    exit 1
fi
