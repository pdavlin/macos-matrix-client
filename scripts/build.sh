#!/bin/bash
# build.sh — build the Mactrix app target.
#
# Wraps `xcodebuild build` for scheme Mactrix, platform macOS, arch arm64.
# Resolves DEVELOPER_DIR in this order:
#   1. an existing DEVELOPER_DIR in the environment (respected as-is)
#   2. /Applications/Xcode-beta.app
#   3. /Applications/Xcode.app
# Fails with a clear message if none of the above is usable.
#
# If xcbeautify is installed (checked via `command -v`), xcodebuild output is
# piped through it. Either way, `set -o pipefail` preserves xcodebuild's exit
# code, so a build failure still fails this script even through the pipe.
#
# Exits non-zero on build failure.
#
# Usage: scripts/build.sh (runs correctly from any working directory)

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

xcodebuild_cmd=(
    xcodebuild build
    -project Mactrix.xcodeproj
    -scheme Mactrix
    -destination "platform=macOS,arch=arm64"
    -disableAutomaticPackageResolution
)

if command -v xcbeautify >/dev/null 2>&1; then
    "${xcodebuild_cmd[@]}" | xcbeautify
else
    "${xcodebuild_cmd[@]}"
fi
