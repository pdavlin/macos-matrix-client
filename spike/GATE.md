# Timeline regression gate (S-39)

The harness that measured the S-13 and S-14 candidates now also mounts the **shipping M1
container**. One command builds it, drives the four scenarios in `SCENARIOS.md` without a
human at the window, and prints a pass or fail line per threshold.

Read `SCENARIOS.md` first. This file says how to run the thing; that one says what the
numbers mean.

## Run it

```
spike/run-gate.sh                              # m1-production, 30s per timed scenario
spike/run-gate.sh --renderer appkit-table      # the S-14 candidate, for comparison
spike/run-gate.sh --duration 60                # the protocol's full 60 seconds
spike/run-gate.sh --out /tmp/dumps             # somewhere other than spike/results
spike/run-gate.sh --scenario s4                # one scenario
```

Re-score dumps that already exist, without re-recording:

```
python3 spike/evaluate-gate.py --renderer m1-production --results spike/results
```

Exit codes: `0` every threshold passed, `1` one did not, `2` a dump the gate needs is
missing, `3` a dump is not comparable and the gate refused to score it.

### The pinned frame

**Every number in the pinned-frame baseline was recorded at a timeline width of 1114pt. A
dump taken at any other width is refused, not scored. Figures recorded before this epoch are
marked as such and cannot be compared with it.**

The scene's window is restorable, so AppKit used to reopen it at whatever frame the previous
session left in the `NSWindow Frame timeline-spike` default. A stale off-screen frame clamps
differently on each launch, and row heights are cached per width (S-32), so the width that
fell out of that clamp moved every frame number the gate recorded. An unpinned pair of runs
of the same code produced an S2 p95 of 32.25ms and 76.25ms.

Under `--scenario` the harness now pins its own geometry, in three layers:

| Layer | What it does | Where |
| --- | --- | --- |
| Saved frame dropped | removes `NSWindow Frame timeline-spike` before the scene builds its window, and stops the run writing one back | `SpikeAppDelegate.applicationWillFinishLaunching`, `PinnedHarnessGeometry.apply(to:)` |
| Window frame set | 1472×938, centred under the top of the visible frame, fully on screen | `PinnedHarnessGeometry.pinWindow()` |
| Pane width pinned | the timeline pane gets a hard 1131pt frame, not a minimum, so it holds even if the window cannot get the size it asked for | `HarnessRootView` |

`run-gate.sh` deletes the same default before launch. That is a second layer, not the
mechanism: a run started by hand from this file is pinned the same way.

The 1131pt pane yields a **1114pt clip view** on the reference machine, because the vertical
scroller is set to display always and takes 17pt. Switching macOS to overlay scrollers
("Show scroll bars: When scrolling") makes it 1131pt, and the gate then refuses every dump
until the baselines are re-recorded. Each dump carries the measured width as
`timelineWidth`, and `evaluate-gate.py` pins it in `PINNED_TIMELINE_WIDTH_PT`.

Still true, and still your job: **do not resize the window during a run.** The pin is applied
before the first layout, not enforced afterwards.

### It needs a logged-in GUI session

The window opens. macOS cannot lay out a real `NSTableView`, run a real `CADisplayLink`, or
move a real `NSClipView` without one, so this does not run over plain ssh and it does not run
in CI. **CI stays build and test only.** Nothing has to be clicked — the runner picks the
renderer, drives the scroll, starts the storm, presses prepend and writes the dumps — but a
session has to exist. Do not touch the window while it runs; the input would land in the
measurement.

Release build, always. `run-gate.sh` passes `-c release`. A debug SwiftUI build spends its
time in retain traffic and unspecialised generics: the first S-39 run recorded a p95 of
58ms in debug and 8.5ms in release for the same code and the same workload.

## What is actually measured

`m1-production` is not a fourth candidate. It is `TimelineViewController`, its two
extensions and the app's `NSTableView` helper, compiled from **symlinks** to the app's own
files:

```
spike/TimelineSpike/Sources/ProductionTimeline/Production/
  TimelineTableView.swift      -> Mactrix/Views/ChatView/TimelineView/TimelineTableView.swift
  TimelineTableUpdates.swift   -> Mactrix/Views/ChatView/TimelineView/TimelineTableUpdates.swift
  TimelineScrollAnchor.swift   -> Mactrix/Views/ChatView/TimelineView/TimelineScrollAnchor.swift
  NSTableView.swift            -> Mactrix/Extensions/NSTableView.swift
```

Change the container and the next gate run measures the change. No copy is kept, so the two
cannot drift apart.

### The seam

The container consumes `[Models.TimelineRow]` and a queue of `Models.TimelineDisplayChange`s.
Both live in `MactrixLibrary`, and neither knows the SDK exists — a row carries its event as
`any Models.EventTimelineItem`. That protocol is the seam the synthetic events cross:

```
SpikeEvent -> SyntheticEventAdapter -> MatrixRustSDK.EventTimelineItem (shim)
           -> TimelineItem.row -> Models.TimelineRow -> the real container
```

Three shims make the production files compile inside the spike package. **None of them
required a production edit.**

| Shim | What it stands in for |
| --- | --- |
| `Sources/MatrixRustSDKShim`, module name `MatrixRustSDK` | the six SDK shapes the container names. Naming the target after the real module is what lets the container's own `import MatrixRustSDK` resolve here. |
| `ProductionTimeline/AppShims/LiveTimeline.swift` | the display order and the change queue, computed from the synthetic store instead of from a homeserver. |
| `ProductionTimeline/AppShims/` (rest) | `AppState`, `WindowState`, the representable's coordinator, `ChatMessageView`, the loggers. |

If a timeline story makes the container name a new SDK symbol, the shim fails to compile and
the gate goes red. That is deliberate: the shim is the written-down contract between the
container and the SDK, and it has to keep pace.

### Where fidelity stops

Two differences are worth knowing before quoting a number.

1. **The rows are not the app's rows.** `ChatMessageView` here renders the real
   `UI.MessageEventProfileView` and `UI.MessageEventBodyView` — avatar, name, timestamp,
   hover buttons, reaction strip — but its message *body* is a `Text` or a shape at the
   right aspect ratio. `FormattedBodyView` and `MessageImageView` take SDK content the
   harness cannot build. Row chrome is real; the innermost body is not.
2. **A machine-driven sweep is not a trackpad drag.** The runner steps the clip view at
   250pt/s, which is `SCENARIOS.md`'s "3 to 4 seconds per screen" for an 800pt viewport.
   Numbers from here are not interchangeable with the hand-driven S-13/S-14 dumps. They are
   interchangeable with each other, which is what a gate needs — so run `appkit-table`
   through the same driver whenever a production number needs a reference.

The workload digest is unchanged: every dump in `spike/results` carries
`wl1-4246e7b15677d961`, the same fingerprint the candidates were measured under. The data is
identical; the view drawing it is not.

## Recorded baseline — 2026-09-15 (pinned-frame epoch)

Both renderers, two runs each, same machine, same release build, same driver, 30s per timed
scenario, every dump at **1114×906pt**. This is the first set of gate figures whose geometry
is known. Dumps are in `spike/results/`, stamped `20260915-11`/`-12`.

| Scenario | Metric | Threshold | `appkit-table` run 1 / run 2 (median) | `m1-production` run 1 / run 2 (median) |
| --- | --- | --- | --- | --- |
| S1 scroll | frame p95 | ≤ 8.5ms | 8.50 / 8.50 (8.50) PASS | **8.50 / 8.50 (8.50) PASS** |
| S2 storm, idle | frame p95 | ≤ 2× nominal (16.67ms) | 17.25 FAIL / 13.75 PASS (15.50) | **29.75 / 27.50 (28.63) FAIL** |
| S3 storm, scrolling | frame p99 | ≤ 3× nominal (25ms) | 23.00 / 24.50 (23.75) PASS | **177.75 / 35.75 (106.75) FAIL** |
| S2 storm, idle | anchor drift worst | ≤ 815pt | 231.9 / 244.0 (238.0) PASS | **456.0 / 408.0 (432.0) PASS** |
| S3 storm, scrolling | anchor drift worst | ≤ 815pt | 460.4 / 642.5 (551.4) PASS | **674.0 / 488.0 (581.0) PASS** |
| S4 prepend ×20 | samples | = 20 | 20 / 20 PASS | **20 / 20 PASS** |
| S4 prepend ×20 | anchor drift worst | 0.0pt baseline, ≤ 0.5pt | 0.000 / 0.000 PASS | **0.251 / 0.222 (0.237) PASS** |

Gate result: `m1-production` **FAIL** in both runs. `appkit-table` **FAIL** in run 1 and
**PASS** in run 2, on S2 p95 alone.

### What the pinned numbers say

1. **The MATRIX-57 finding survives.** `m1-production` misses the S2 storm-idle p95 bar in
   both pinned runs, at 1.65× and 1.79× the limit. The pre-epoch figure (24.25ms) understated
   it. The failure was never an artifact of the unpinned frame.
2. **Anchor stability is not the problem, still.** Every drift threshold passes in every run,
   production included, and the prepend anchor holds to a quarter of a point.
3. **The reference candidate no longer clears the bars with room.** `appkit-table` straddles
   S2 p95 (17.25 fails, 13.75 passes — a 25% spread between two runs of the same binary) and
   sits within 2% of the S3 p99 bar (23.00 and 24.50 against 25). S1 p95 lands on 8.50 exactly
   in all four runs, passing only because the comparison is `≤`.

Point 3 is a **calibration question, not a change**: thresholds are unchanged in this epoch.
A bar the reference renderer fails half the time cannot separate a regression from noise, so
either the S2/S3 bars need re-deriving from pinned reference runs, or the gate needs to score
a median of N runs rather than the newest dump. Both are somebody's decision, not the
measurement's. See the MATRIX-60 pull request for the argument.

## Pre-epoch baseline — 2026-09-06 (not comparable)

**Recorded before the frame was pinned. Do not compare these numbers with anything below
them.** Every run in this table restored whatever window frame the previous session left, so
each row was measured at an unknown width, and the width is an input to the frame times. The
dumps stay in `spike/results/` as history; `evaluate-gate.py` refuses to score them because
they carry no `timelineWidth`. The same applies to the MATRIX-57, MATRIX-58 and MATRIX-59
figures, which were recorded the same way.

Both renderers, same machine, same release build, same driver, 30s per timed scenario.

| Scenario | Metric | Threshold | `appkit-table` | `m1-production` |
| --- | --- | --- | --- | --- |
| S1 scroll | frame p95 | ≤ 8.5ms | 8.50 PASS | **8.50 PASS** |
| S2 storm, idle | frame p95 | ≤ 2× nominal (16.67ms) | 13.75 PASS | **24.25 FAIL** |
| S3 storm, scrolling | frame p99 | ≤ 3× nominal (25ms) | 10.25 PASS | **31.00 FAIL** |
| S2 storm, idle | anchor drift worst | ≤ 815pt | 196.0 PASS | **348.0 PASS** |
| S3 storm, scrolling | anchor drift worst | ≤ 815pt | 712.0 PASS | **420.0 PASS** |
| S4 prepend ×20 | samples | = 20 | 20 PASS | **20 PASS** |
| S4 prepend ×20 | anchor drift worst | 0.0pt baseline, ≤ 0.5pt | 0.000 PASS | **0.219 PASS** |

Gate result: `appkit-table` **PASS**, `m1-production` **FAIL** on frame time under the
mutation storm.

### Why the 8.5ms bar sits on S1 only

8.5ms is the AppKit candidate's measured scroll p95, adopted as a regression bar. It is a
scroll-only number: under the automated driver the reference candidate does not hold it
during the storm either (13.75ms in S2). A bar that fails the renderer which set it is the
wrong bar, so S2 and S3 are scored on `SCENARIOS.md` §6's own limits — p95 ≤ 2× nominal and
p99 ≤ 3× nominal. The reference candidate passed all of those when the bars were set, which
is what made the production failure a signal rather than a calibration error. Under the
pinned frame it no longer passes S2 reliably — see "What the pinned numbers say".

### The open finding

**Pre-epoch figures. The pinned-frame table above supersedes the numbers in this paragraph;
the conclusion it draws is unchanged.**

The production container costs roughly **1.8× the reference candidate's p95 under the
mutation storm** (24.25ms against 13.75ms) and **3× its p99 while scrolling through one**
(31.00ms against 10.25ms). Anchor stability is not the problem — production is *better* than
the candidate on S3 drift (420pt against 712pt) and holds the prepend anchor to a fifth of a
point across twenty prepends. The cost is invalidation: a mutation bumps the row's revision,
misses the height cache, and pays an offscreen `sizeThatFits` on an `NSHostingController`
plus a `reloadData` for that row. Part of the gap is the heavier real row chrome (see
"Where fidelity stops"), and how much is unknown.

This is **out of scope for S-39**, which delivers the measurement, not the fix. It wants its
own story.

> **Re-confirmed on 2026-09-15.** The original recording session was taken on a machine that
> slept, so this table carried a warning to re-run it. The pinned-frame baseline above is that
> re-run: four runs under `caffeinate -dis`, at a known width. The production storm-idle
> failure reproduces, wider than it first looked.

## Adding a scenario

`ScenarioRunner.RunnerOptions.Scenario` lists them; `ScenarioRunner.run(_:)` drives them and
`ScrollDriver` moves the viewport. Thresholds live at the top of `evaluate-gate.py`, as
constants rather than comments, so changing one is a diff somebody reviews.
