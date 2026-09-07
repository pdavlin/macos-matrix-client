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
missing.

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

## Recorded baseline — 2026-09-06

Both renderers, same machine, same release build, same driver, 30s per timed scenario.
Dumps are in `spike/results/`.

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
p99 ≤ 3× nominal. The reference candidate passes all of those, which is what makes the
production failure a signal rather than a calibration error.

### The open finding

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

> **Re-confirm before acting on it.** The machine slept during the recording session. The
> numbers above are internally consistent and the reference candidate reproduces its
> published baselines, but a sleep/wake cycle can perturb display-link timing. Re-run
> `spike/run-gate.sh --renderer m1-production` and `--renderer appkit-table` on a machine
> that stays awake before anyone files or sizes the follow-up.

## Adding a scenario

`ScenarioRunner.RunnerOptions.Scenario` lists them; `ScenarioRunner.run(_:)` drives them and
`ScrollDriver` moves the viewport. Thresholds live at the top of `evaluate-gate.py`, as
constants rather than comments, so changing one is a diff somebody reviews.
