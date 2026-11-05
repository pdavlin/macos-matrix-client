#!/bin/bash
# lint.sh — run SwiftFormat --lint and SwiftLint.
#
# Reads .swiftformat and .swiftlint.yml at the repo root. Requires both
# swiftformat and swiftlint on PATH (install via `brew install swiftformat
# swiftlint`). Fails the script if either tool is missing, if swiftformat is
# not the version pinned in .github/workflows/xcode-build.yml, or if either
# check reports a failure.
#
# Usage: scripts/lint.sh (runs correctly from any working directory)

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || dirname "$script_dir")"

cd "$repo_root"

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "error: swiftformat not found. Install it with: brew install swiftformat" >&2
    exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: swiftlint not found. Install it with: brew install swiftlint" >&2
    exit 1
fi

# The SwiftFormat version CI installs is the single source of truth. Rules
# change between releases, so a different local version reports drift that
# CI does not see (or misses drift that CI fails on).
workflow=".github/workflows/xcode-build.yml"
pinned_version="$(grep -E '^[[:space:]]*SWIFTFORMAT_VERSION:' "$workflow" | head -n 1 | awk '{print $2}')"
if [ -z "$pinned_version" ]; then
    echo "error: could not read SWIFTFORMAT_VERSION from $workflow" >&2
    exit 1
fi
local_version="$(swiftformat --version)"
if [ "$local_version" != "$pinned_version" ]; then
    echo "error: swiftformat $local_version is on PATH, but CI pins $pinned_version ($workflow)." >&2
    echo "       Install $pinned_version from https://github.com/nicklockwood/SwiftFormat/releases/tag/$pinned_version" >&2
    exit 1
fi

echo "==> swiftformat --lint ($local_version)"
swiftformat . --lint

echo "==> swiftlint"
swiftlint lint
