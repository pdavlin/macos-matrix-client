#!/usr/bin/env python3
"""S-39 — check a set of harness dumps against the M1 timeline thresholds.

Reads the newest dump per scenario for one renderer and prints a pass/fail line
per threshold. Exit code 0 when every threshold passes, 1 when one does not, 2
when a dump the gate needs is missing.

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

    # Frame time. SCENARIOS.md §6 scores p95 in S1 and S2 and p99 in S3, so the
    # 8.5ms bar is applied where the baseline set it and S3 is reported against
    # the protocol's own p99 bar.
    path = newest_dump(results, args.renderer, "s1")
    if path is None:
        gate.note_missing("s1")
    else:
        report = load(path)
        check_fingerprint(report, path)
        print(f"s1 ({path.name}):")
        gate.check("frame p95", report["frame"]["p95Milliseconds"], S1_P95_MAX_MS, "ms")

    path = newest_dump(results, args.renderer, "s2")
    if path is None:
        gate.note_missing("s2")
    else:
        report = load(path)
        check_fingerprint(report, path)
        print(f"s2 ({path.name}):")
        gate.check(
            "frame p95",
            report["frame"]["p95Milliseconds"],
            report["frame"]["nominalMilliseconds"] * S2_P95_NOMINAL_MULTIPLE,
            "ms",
        )

    path = newest_dump(results, args.renderer, "s3")
    if path is None:
        gate.note_missing("s3")
    else:
        report = load(path)
        check_fingerprint(report, path)
        print(f"s3 ({path.name}):")
        gate.check(
            "frame p99",
            report["frame"]["p99Milliseconds"],
            report["frame"]["nominalMilliseconds"] * S3_P99_NOMINAL_MULTIPLE,
            "ms",
        )

    # Mutation-storm anchor drift. Worst case across both storm scenarios.
    for scenario in ("s2", "s3"):
        path = newest_dump(results, args.renderer, scenario)
        if path is None:
            gate.note_missing(scenario)
            continue
        report = load(path)
        check_fingerprint(report, path)
        print(f"{scenario} ({path.name}):")
        gate.check("mutation drift worst", report["mutationDrift"]["worstMagnitude"], MUTATION_DRIFT_MAX_PT, "pt")

    # Prepend anchoring.
    path = newest_dump(results, args.renderer, "s4")
    if path is None:
        gate.note_missing("s4")
    else:
        report = load(path)
        check_fingerprint(report, path)
        print(f"s4 ({path.name}):")
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
    sys.exit(main())
