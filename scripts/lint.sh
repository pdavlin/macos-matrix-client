#!/bin/bash
# lint.sh — run SwiftFormat --lint and SwiftLint.
#
# Reads .swiftformat and .swiftlint.yml at the repo root. Requires both
# swiftformat and swiftlint on PATH (install via `brew install swiftformat
# swiftlint`). Fails the script if either tool is missing, or if either
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

echo "==> swiftformat --lint"
swiftformat . --lint

echo "==> swiftlint"
swiftlint lint
