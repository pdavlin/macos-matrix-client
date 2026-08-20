#!/bin/bash
# test.sh — run every test suite in the repo.
#
# Four suites, in order:
#   1. `swift test --package-path MactrixLibrary` — the local SPM package's
#      unit tests.
#   2. `swift test --package-path spike/TimelineSpike` — the timeline spike
#      package's unit tests.
#   3. `xcodebuild test -scheme MactrixTests` — the app test plan, which
#      runs the MactrixLibrary tests through the app project's test plan.
#   4. `xcodebuild test -scheme MactrixIntegrationTests` — the S-05 headless
#      login/discovery integration test against davlin.io. Skips itself
#      (exit 0) unless MATRIX_DEV_USER / MATRIX_DEV_PASSWORD are present in
#      its environment; see MactrixIntegrationTests/LoginIntegrationTests.swift
#      for how to supply them, both from Xcode and headlessly.
#
# Exits non-zero if any suite fails.
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

echo "==> swift test --package-path spike/TimelineSpike"
swift test --package-path spike/TimelineSpike

echo "==> xcodebuild test -scheme MactrixTests"
xcodebuild test \
    -project Mactrix.xcodeproj \
    -scheme MactrixTests \
    -destination "platform=macOS,arch=arm64" \
    -disableAutomaticPackageResolution

echo "==> xcodebuild test -scheme MactrixIntegrationTests"
xcodebuild test \
    -project Mactrix.xcodeproj \
    -scheme MactrixIntegrationTests \
    -destination "platform=macOS,arch=arm64" \
    -disableAutomaticPackageResolution
