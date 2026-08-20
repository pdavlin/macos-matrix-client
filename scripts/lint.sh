#!/bin/bash
# lint.sh — run SwiftFormat --lint and SwiftLint.
#
# SwiftFormat and SwiftLint configs are not committed yet (story S-11 owns
# that). Until they exist, and until both binaries are installed, this
# script is a fail-soft stub: it prints a notice and exits 0 so it does not
# block other scripts or CI. Once S-11 lands the configs, this script runs
# the real checks and propagates their failures.
#
# Usage: scripts/lint.sh (runs correctly from any working directory)

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || dirname "$script_dir")"

cd "$repo_root"

have_swiftformat=0
have_swiftlint=0
command -v swiftformat >/dev/null 2>&1 && have_swiftformat=1
command -v swiftlint >/dev/null 2>&1 && have_swiftlint=1

if [[ ! -f ".swiftformat" || ! -f ".swiftlint.yml" || "$have_swiftformat" -eq 0 || "$have_swiftlint" -eq 0 ]]; then
    echo "lint not configured yet (S-11)"
    exit 0
fi

echo "==> swiftformat --lint"
swiftformat --lint .

echo "==> swiftlint"
swiftlint
