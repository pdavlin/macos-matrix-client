#!/bin/bash
# S-39 — timeline regression gate.
#
# Builds the spike package, drives the four scenarios from SCENARIOS.md against
# a renderer without a human at the window, and checks the dumps against the
# thresholds the S-15 decision set.
#
#   spike/run-gate.sh                       # m1-production, the shipping container
#   spike/run-gate.sh --renderer appkit-table
#   spike/run-gate.sh --duration 60         # the protocol's full 60s per scenario
#   spike/run-gate.sh --out spike/results   # where the dumps land
#
# It opens a window. macOS cannot lay out a real table, run a real display link
# or move a real clip view without one, so this needs a logged-in GUI session —
# it will not run over plain ssh or in CI. CI stays build and test only.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_PATH="$REPO_ROOT/spike/TimelineSpike"

RENDERER="m1-production"
DURATION="30"
OUT_DIR="$REPO_ROOT/spike/results"
SCENARIOS="s1,s2,s3,s4"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --scenario) SCENARIOS="$2"; shift 2 ;;
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

mkdir -p "$OUT_DIR"

echo "==> building"
swift build -c release --package-path "$PACKAGE_PATH"

echo "==> running $SCENARIOS against $RENDERER (${DURATION}s per timed scenario)"
# Release, always. A debug SwiftUI build spends most of its time in retain
# traffic and unspecialised generics; frame numbers from one mean nothing.
swift run -c release --package-path "$PACKAGE_PATH" TimelineSpikeApp \
    --renderer "$RENDERER" \
    --scenario "$SCENARIOS" \
    --duration "$DURATION" \
    --out "$OUT_DIR"

echo "==> evaluating thresholds"
python3 "$REPO_ROOT/spike/evaluate-gate.py" --renderer "$RENDERER" --results "$OUT_DIR"
