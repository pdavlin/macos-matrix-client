#!/usr/bin/env python3
"""S-39 — check a set of harness dumps against the M1 timeline thresholds.

Reads the newest dump per scenario for one renderer and prints a pass/fail line
per threshold. Exit code 0 when every threshold passes, 1 when one does not, 2
when a dump the gate needs is missing, 3 when a dump is not comparable and the
gate refuses to score it.

Three things make a dump comparable, and all three are refusals rather than
warnings: the workload it rendered (`workloadFingerprint`), the width its rows
laid out at (`timelineWidth`, MATRIX-60) and the frame quantum its milliseconds
were measured against (`environment`, MATRIX-64). A scored number from a run
whose environment is unknown is worse than no number.

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

# Timeline clip-view height, in points, every scored dump must have been recorded at. Height
# was recorded but not enforced until MATRIX-64, and that gap cost a recording session: on a
# 2560x1440 display SwiftUI sized the timeline pane to its content's ideal height and let the
# 938pt window clip it, so the gate measured a 1327pt viewport — 47% more rows drawn per frame
# — while the run log still reported the pinned window frame. The laptop panel had been
# clamping it to 906pt and hiding the problem. Height sets how many rows a frame draws, so it
# is an input to every frame number here exactly as width is.
PINNED_TIMELINE_HEIGHT_PT = 906.0
PINNED_HEIGHT_TOLERANCE_PT = 0.5

# Display cadence, in hertz, every scored dump must have been recorded at. Frame thresholds
# below are absolute milliseconds, so the frame quantum is an input to all of them: the same
# binary scored an S2 p95 of 18.5ms on a 120 Hz panel and 29.75ms on a 60 Hz one. The harness
# asks the display link for a fixed 120 Hz, measures what arrived during a calibration spin,
# and writes it into `environment.cadence`. Anything else is refused, not scored.
PINNED_CADENCE_HZ = 120.0
# Fraction the measured cadence may differ from the pinned rate. Matches `PinnedCadence`.
PINNED_CADENCE_TOLERANCE = 0.05
# Scroller style the baseline was recorded under. This is not cosmetic: overlay scrollers give
# the clip view back the 17pt the legacy scroller occupies, which changes the timeline width
# and therefore the cached row heights. It is checked separately from the width so the refusal
# names the cause rather than the symptom.
PINNED_SCROLLER_STYLE = "legacy"
# Backing scale factor the baseline was recorded at. A 1x panel rasterizes a quarter of the
# pixels a 2x one does for the same point size, so the same layout costs different work to
# draw. The display's *name* is deliberately not checked — swapping monitors should not need a
# constant edited — but the scale is the physical variable behind the cost, it is numeric, and
# it is stable. Recording a baseline on a rig at another scale means changing this line, which
# is the same reviewed-diff discipline the width and the thresholds get.
#
# 1x, not 2x: the reference rig is the docked clamshell setup described in GATE.md, which is
# the one the machine actually sits in. The built-in ProMotion panel is the higher-fidelity
# display and the wrong reference — it spent 2026-09-17 demonstrating that its adaptive
# refresh will not hold a quantum across a recording session.
PINNED_BACKING_SCALE_FACTOR = 1.0
PINNED_BACKING_SCALE_TOLERANCE = 0.01

# Frame p95 on the sustained-scroll scenario, in milliseconds, at the pinned
# 120 Hz cadence (8.333ms quantum, so this bar is a shade over one dropped
# frame). This is the AppKit candidate's measured p95 adopted as a bar, and it
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

    height = report.get("timelineHeight")
    if height is None:
        raise UnpinnedDump(
            f"{path.name} predates the pinned-frame epoch: it carries no timelineHeight. "
            "Re-record with spike/run-gate.sh."
        )
    if abs(float(height) - PINNED_TIMELINE_HEIGHT_PT) > PINNED_HEIGHT_TOLERANCE_PT:
        raise UnpinnedDump(
            f"{path.name} was recorded at timeline height {float(height):.1f}pt, not the pinned "
            f"{PINNED_TIMELINE_HEIGHT_PT:g}pt. Viewport height sets how many rows a frame draws, "
            "so this dump measured a different amount of work per frame. A taller viewport than "
            "the pin means the harness window grew to the display rather than to its pinned "
            "frame; re-run spike/run-gate.sh on a build that pins the pane height."
        )


def require_pinned_cadence(report: dict, path: pathlib.Path) -> None:
    """Refuse a dump that did not present at the pinned cadence, or under another scroller style."""
    environment = report.get("environment")
    if environment is None:
        raise UnpinnedDump(
            f"{path.name} predates the pinned-cadence epoch: it carries no environment, so the "
            "frame quantum its milliseconds were measured against is unknown. Pre-epoch dumps are "
            "kept for history and are not comparable. Re-record with spike/run-gate.sh."
        )

    cadence = environment.get("cadence") or {}
    measured = cadence.get("measuredHertz")
    if measured is None:
        raise UnpinnedDump(
            f"{path.name} carries an environment with no measured cadence. Re-record with "
            "spike/run-gate.sh."
        )
    measured = float(measured)
    if abs(measured - PINNED_CADENCE_HZ) > PINNED_CADENCE_HZ * PINNED_CADENCE_TOLERANCE:
        display = (environment.get("display") or {}).get("localizedName", "unknown display")
        raise UnpinnedDump(
            f"{path.name} was recorded at {measured:.1f}Hz (frame quantum "
            f"{float(cadence.get('quantumP50Milliseconds', 0)):.3f}ms) on {display}, not the pinned "
            f"{PINNED_CADENCE_HZ:g}Hz. Every frame threshold here is an absolute millisecond figure, "
            "so a dump taken at another quantum measured a different bar. Run the gate on a display "
            "that holds the pinned rate — see spike/GATE.md."
        )

    style = environment.get("scrollerStyle")
    if style != PINNED_SCROLLER_STYLE:
        raise UnpinnedDump(
            f"{path.name} was recorded with {style!r} scrollers, not the baseline's "
            f"{PINNED_SCROLLER_STYLE!r}. Overlay scrollers hand the clip view back the 17pt the "
            "legacy scroller occupies, so the rows laid out at a different width. Set System "
            "Settings > Appearance > Show scroll bars to Always, then re-run spike/run-gate.sh."
        )

    display = environment.get("display") or {}
    scale = display.get("backingScaleFactor")
    if scale is None:
        raise UnpinnedDump(
            f"{path.name} carries an environment with no backing scale factor. Re-record with "
            "spike/run-gate.sh."
        )
    if abs(float(scale) - PINNED_BACKING_SCALE_FACTOR) > PINNED_BACKING_SCALE_TOLERANCE:
        raise UnpinnedDump(
            f"{path.name} was recorded at {float(scale):g}x backing scale on "
            f"{display.get('localizedName', 'an unknown display')}, not the baseline's "
            f"{PINNED_BACKING_SCALE_FACTOR:g}x. The same layout in points rasterizes a different "
            "number of pixels at another scale, so it costs different work to draw. Run the gate "
            "on a display at the baseline's scale — see spike/GATE.md."
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
        require_pinned_cadence(report, path)
        reports[scenario] = report
        environment = report["environment"]
        print(
            f"{scenario} ({path.name}): timeline "
            f"{float(report['timelineWidth']):.0f}x{float(report['timelineHeight']):.0f}pt, "
            f"{float(environment['cadence']['measuredHertz']):.1f}Hz, "
            f"{float(environment['display']['backingScaleFactor']):g}x on "
            f"{environment['display'].get('localizedName', 'unknown')}"
        )

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
