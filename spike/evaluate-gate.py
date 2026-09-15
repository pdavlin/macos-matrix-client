#!/usr/bin/env python3
"""S-39 — check a set of harness dumps against the M1 timeline thresholds.

Reads the newest dump per scenario for one renderer and prints a pass/fail line
per threshold. Exit code 0 when every threshold passes, 1 when one does not, 2
when a dump the gate needs is missing, 3 when a dump is not comparable and the
gate refuses to score it.

The thresholds come from the AppKit candidate that won S-15. They are recorded
here rather than in a comment so a change to them is a diff someone reviews.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

# The workload the thresholds were measured against. A dump with a different
# digest rendered different content per row; its frame times are not comparable,
# whatever the rest of the file says.
EXPECTED_FINGERPRINT = "wl1-4246e7b15677d961"

# Timeline clip-view width, in points, every scored dump must have been recorded
# at. Row heights are cached per width, so a dump taken at another width measured
# a different layout and its frame times cannot be compared with the baseline.
# `PinnedHarnessGeometry` pins a 1472x938 window and a 1131pt timeline pane under
# the automated driver; 1114pt is what the clip view measures inside that pane
# with legacy (always-visible) scrollers. This is a refusal, not a warning: a
# scored number from an unpinned run is worse than no number.
PINNED_TIMELINE_WIDTH_PT = 1114.0
PINNED_WIDTH_TOLERANCE_PT = 0.5

# Frame p95 on the sustained-scroll scenario, in milliseconds, on a 120 Hz
# display. This is the AppKit candidate's measured p95 adopted as a bar, and it
# is a scroll-only number: the reference candidate does not hold it under the
# mutation storm either, so applying it to S2 would fail the renderer that set
# it. S2 and S3 are scored on SCENARIOS.md §6's own bars instead.
S1_P95_MAX_MS = 8.5
# §6: "p95 <= 2 x nominal in S1 and S2, and p99 <= 3 x nominal in S3".
S2_P95_NOMINAL_MULTIPLE = 2.0
S3_P99_NOMINAL_MULTIPLE = 3.0
# Worst prepend anchor drift across 20 deliberate prepends, in points. The
# AppKit candidate held 0.0pt. A different table geometry cannot reproduce an
# exact zero in floating point, so the gate allows the probe's own stability
# threshold and prints the raw number next to it.
PREPEND_DRIFT_BASELINE_PT = 0.0
PREPEND_DRIFT_TOLERANCE_PT = 0.5
# Worst anchor drift during the mutation storm, in points.
MUTATION_DRIFT_MAX_PT = 815.0
# Every one of the 20 prepends must produce a sample. A lower count means the
# tracked event left the viewport, which is itself the failure.
PREPEND_SAMPLE_COUNT = 20


def newest_dump(results: pathlib.Path, renderer: str, scenario: str) -> pathlib.Path | None:
    matches = sorted(results.glob(f"timeline-spike-{renderer}-{scenario}-automated-*.json"))
    return matches[-1] if matches else None


def load(path: pathlib.Path) -> dict:
    with path.open() as handle:
        return json.load(handle)


class UnpinnedDump(Exception):
    """A dump that cannot be compared with the baseline, whatever its numbers say."""


def require_pinned_width(report: dict, path: pathlib.Path) -> None:
    """Refuse a dump that was not recorded at the pinned timeline width."""
    width = report.get("timelineWidth")
    if width is None:
        raise UnpinnedDump(
            f"{path.name} predates the pinned-frame epoch: it carries no timelineWidth, so the "
            "width its rows laid out at is unknown. Pre-epoch dumps are kept for history and "
            "are not comparable. Re-record with spike/run-gate.sh."
        )
    if abs(float(width) - PINNED_TIMELINE_WIDTH_PT) > PINNED_WIDTH_TOLERANCE_PT:
        raise UnpinnedDump(
            f"{path.name} was recorded at timeline width {float(width):.1f}pt, not the pinned "
            f"{PINNED_TIMELINE_WIDTH_PT:g}pt. Row heights are cached per width, so this dump "
            "measured a different layout. Check that the window was not resized during the run "
            "and that the scroll bar display setting has not changed, then re-run "
            "spike/run-gate.sh."
        )


class Gate:
    def __init__(self) -> None:
        self.failed = False
        self.missing = False

    def check(self, name: str, actual: float, limit: float, unit: str, comparison: str = "<=") -> None:
        ok = actual <= limit if comparison == "<=" else actual >= limit
        self.failed = self.failed or not ok
        status = "PASS" if ok else "FAIL"
        print(f"  [{status}] {name}: {actual:.3f}{unit} (limit {comparison} {limit:g}{unit})")

    def note_missing(self, scenario: str) -> None:
        self.missing = True
        print(f"  [MISS] no dump for scenario {scenario}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--renderer", default="m1-production")
    parser.add_argument("--results", default="spike/results")
    args = parser.parse_args()

    results = pathlib.Path(args.results)
    gate = Gate()

    print(f"renderer: {args.renderer}")
    print(f"results:  {results}")

    # One load per scenario, and every comparability check runs before any
    # threshold reads the file: a dump the gate cannot compare is refused, not
    # scored.
    reports: dict[str, dict] = {}
    for scenario in ("s1", "s2", "s3", "s4"):
        path = newest_dump(results, args.renderer, scenario)
        if path is None:
            gate.note_missing(scenario)
            continue
        report = load(path)
        check_fingerprint(report, path)
        require_pinned_width(report, path)
        reports[scenario] = report
        print(f"{scenario} ({path.name}): timeline {float(report['timelineWidth']):.0f}x{float(report['timelineHeight']):.0f}pt")

    # Frame time. SCENARIOS.md §6 scores p95 in S1 and S2 and p99 in S3, so the
    # 8.5ms bar is applied where the baseline set it and S3 is reported against
    # the protocol's own p99 bar.
    report = reports.get("s1")
    if report is not None:
        print("s1:")
        gate.check("frame p95", report["frame"]["p95Milliseconds"], S1_P95_MAX_MS, "ms")

    report = reports.get("s2")
    if report is not None:
        print("s2:")
        gate.check(
            "frame p95",
            report["frame"]["p95Milliseconds"],
            report["frame"]["nominalMilliseconds"] * S2_P95_NOMINAL_MULTIPLE,
            "ms",
        )

    report = reports.get("s3")
    if report is not None:
        print("s3:")
        gate.check(
            "frame p99",
            report["frame"]["p99Milliseconds"],
            report["frame"]["nominalMilliseconds"] * S3_P99_NOMINAL_MULTIPLE,
            "ms",
        )

    # Mutation-storm anchor drift. Worst case across both storm scenarios.
    for scenario in ("s2", "s3"):
        report = reports.get(scenario)
        if report is None:
            continue
        print(f"{scenario}:")
        gate.check("mutation drift worst", report["mutationDrift"]["worstMagnitude"], MUTATION_DRIFT_MAX_PT, "pt")

    # Prepend anchoring.
    report = reports.get("s4")
    if report is not None:
        print("s4:")
        gate.check(
            "prepend samples",
            report["prependDrift"]["count"],
            PREPEND_SAMPLE_COUNT,
            "",
            comparison=">=",
        )
        gate.check(
            "prepend drift worst",
            report["prependDrift"]["worstMagnitude"],
            PREPEND_DRIFT_BASELINE_PT + PREPEND_DRIFT_TOLERANCE_PT,
            "pt",
        )

    if gate.missing:
        print("\nresult: INCOMPLETE — run spike/run-gate.sh to record the missing scenarios")
        return 2
    if gate.failed:
        print("\nresult: FAIL")
        return 1
    print("\nresult: PASS")
    return 0


def check_fingerprint(report: dict, path: pathlib.Path) -> None:
    actual = report.get("workloadFingerprint")
    if actual != EXPECTED_FINGERPRINT:
        print(f"  [WARN] {path.name} has workload fingerprint {actual}, expected {EXPECTED_FINGERPRINT}")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except UnpinnedDump as refusal:
        print(f"\nrefusing to score: {refusal}")
        print("result: REFUSED")
        sys.exit(3)
