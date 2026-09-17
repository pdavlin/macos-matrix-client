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
missing, `3` a dump is not comparable and the gate refused to score it. The harness itself
exits `3` as well, when the calibration spin says the display did not deliver the pinned
cadence — `run-gate.sh` runs under `set -e`, so that stops the script before it can score
whatever stale dumps are on disk.

## The pinned environment

**Set this up before recording anything. Three inputs to every number in the baseline are
properties of the machine, not of the code, and a dump that disagrees on any of them is
refused rather than scored.**

**The reference rig is the docked clamshell setup**: the lid shut, an external LC49G95T at
2560×1440, 1x backing scale, running at a 120 Hz refresh rate, with scroll bars set to always
show. That is the configuration the machine actually sits in, which is why it is the
reference and not the built-in ProMotion panel. The built-in panel is the better display and
the worse instrument: on 2026-09-17 its adaptive refresh moved the frame quantum *inside* a
recording session, which is the failure this whole section exists to make impossible.

| Input | Required | Why it moves the numbers | Recorded as | Refused on mismatch |
| --- | --- | --- | --- | --- |
| Cadence | a measured **120 Hz**, ±5% | every frame threshold is absolute milliseconds, so the frame quantum is an input to all of them | `environment.cadence` | yes, and the run stops before writing a dump |
| Backing scale | **1x**, the reference rig's external panel | the same layout in points rasterizes four times the pixels at 2x, so it costs different work to draw | `environment.display.backingScaleFactor` | yes |
| Scroll bars | System Settings → Appearance → **Show scroll bars: Always** | overlay scrollers hand the clip view back the scroller's 17pt, moving the timeline width from 1114pt to 1131pt, and row heights are cached per width | `environment.scrollerStyle`, `timelineWidth` | yes, on both fields |
| Display model | any panel meeting the three above | — | `environment.display.localizedName` | **no, recorded only** |

The display's *name* is deliberately not a refusal: swapping a monitor should not require a
constant edited. The scale is, because it is the physical variable behind the cost, it is
numeric, and it is stable. `PINNED_BACKING_SCALE_FACTOR` in `evaluate-gate.py` names the
baseline's scale; recording a baseline on a rig at another scale means changing that line,
which gets the same reviewed-diff treatment as the width and the thresholds.

Moving the reference to the built-in panel later is a legitimate decision — it is the display
a user looks at — but it is a **new epoch**, not a re-run: 1x and 2x figures are not
comparable, and the whole baseline has to be re-recorded behind the constant change.

#### Known limitation: this gate does not measure the undocked machine

The app runs in two environments — docked to the external panel, which is the common case,
and undocked on the built-in 2x ProMotion panel. **The gate deliberately measures only the
first.** Two differences make the second harder on the renderer, not easier:

- **2x rasterization.** The same layout in points covers four times the pixels, so drawing a
  row costs more.
- **Adaptive refresh.** The built-in panel varies its rate, which is precisely why it is a
  poor instrument: it will not hold a quantum across a recording session.

So a green gate is evidence about the docked experience, and gate numbers can **understate**
what the timeline costs undocked. If undocked performance is ever in question, the machinery
already supports the answer: the environment is a recorded, refused-on-mismatch profile, so a
second pinned profile (2x, built-in panel, its own baselines and its own constants) is a
configuration change plus a recording session, not a redesign. That is a deliberate future
option and it is not in scope here.

Run under `caffeinate -dis`, and with nothing else heavy on the machine — a baseline is the
reference every later run is scored against, so noise recorded into it never washes out. Do
not touch the window while it runs.

### Recording a baseline

```
pgrep -fl TimelineSpike                      # nothing else driving the window
caffeinate -dis spike/run-gate.sh --renderer m1-production
caffeinate -dis spike/run-gate.sh --renderer m1-production
caffeinate -dis spike/run-gate.sh --renderer appkit-table
caffeinate -dis spike/run-gate.sh --renderer appkit-table
```

Each run prints its environment line before the first scenario. Check it before letting the
run continue:

```
[TimelineSpike] environment: 120.0Hz (p50 8.334ms) on LC49G95T 2560x1440@1x, ceiling 120Hz, legacy scrollers
```

Then commit the dumps and fill in the table below from `evaluate-gate.py`'s output.

### Pinning the cadence

The three MATRIX-57 acceptance attempts on 2026-09-17 are what this section exists for. The
same binary, on the same day, produced an S2 p95 of 18.5ms and 29.75ms, and the difference
was the display:

1. **Clamshell on an external panel.** Effective 60 Hz, 16.75ms quanta on both arms. The gate
   scored it without complaint: the S2 and S3 bars are multiples of the measured nominal, so
   a 60 Hz run silently doubles them.
2. **Lid open.** macOS switched to overlay scroll bars, the timeline measured 1131pt, and the
   MATRIX-60 width guard refused — correctly, and that refusal is the only reason the session
   did not produce another unreadable number.
3. **Built-in ProMotion panel.** Adaptive refresh moved the quantum *mid-session*: one run at
   60 Hz quanta throughout, and three of four runs dropped prepend samples to 17-19 of 20.

So the harness now asks for the rate rather than accepting one:

| Layer | What it does | Where |
| --- | --- | --- |
| Rate requested | `CADisplayLink.preferredFrameRateRange` set to a **fixed** range, `minimum == maximum == 120`. A preferred-only range is what adaptive refresh is free to move | `FrameRecorder.applyPinnedRate()`, from `SpikeHarness.pinDisplayLinkCadence(hertz:)` |
| Rate requested early | applied to the live link as well as the next one, so the driver does not race the renderer mounting | `FrameRecorder.pinnedHertz`'s `didSet` |
| Rate measured | a 2-second scrolling calibration spin before the first scenario; the p50 of consecutive callback deltas is the frame quantum | `ScenarioRunner.calibrateCadence()` |
| Rate verified | a measured rate outside ±5% of 120 Hz stops the run with exit `3`, before a single dump is written | same |
| Rate recorded | measured cadence, display identity and scroller style land in every dump's `environment` | `HarnessEnvironment`, `SpikeReport.environment` |

The spin scrolls rather than sitting idle on purpose: the scenarios are measured while the
viewport moves, and a cadence read from a still window is not evidence about one that does
not stand still.

`evaluate-gate.py` then refuses, with a distinct message and exit `3`, any dump that carries
no `environment` (pre-epoch), whose measured cadence is outside `PINNED_CADENCE_HZ` ±
`PINNED_CADENCE_TOLERANCE`, whose `scrollerStyle` is not `PINNED_SCROLLER_STYLE`, or whose
backing scale is not `PINNED_BACKING_SCALE_FACTOR`. It is the same refusal shape MATRIX-60
gave the width, for the same reason: a scored number from a run whose environment is unknown
is worse than no number.

One caveat worth writing down. On 2026-09-17 the clamshelled external panel measured a clean
120.0 Hz (8.3335ms quantum over 263 samples) from the same rig that had presented at an
effective 60 Hz that morning. Nothing here explains that: it was a one-time state, and the
machine was not reconfigured in between. The pin does not make the cause go away — it makes
the state **detectable**, in the log line and in the dump, either way. That is the whole
claim.

### The pinned frame

**Every number in the pinned baseline was recorded at a timeline clip view of 1114×906pt. A
dump taken at any other width *or height* is refused, not scored. Figures recorded before this
epoch are marked as such and cannot be compared with it.**

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
| Window size clamped | `minSize`/`maxSize` and their content equivalents fixed at the same 1472×938, so nothing can grow the window afterwards | `PinnedHarnessGeometry.apply(to:)` |
| Pane width pinned | the timeline pane gets a hard 1131pt frame, not a minimum, so it holds even if the window cannot get the size it asked for | `HarnessRootView` |
| Pane height pinned | a hard 906pt frame, for the same reason and with more teeth: a pinned *window* does not stop SwiftUI sizing the pane to its content and letting the window clip it, which is how a 1327pt clip view once fitted inside a 938pt window | `HarnessRootView`, `PinnedHarnessGeometry.timelinePaneHeight` |

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

## Recorded baseline — 2026-09-17 (pinned-cadence epoch)

Both renderers, two runs each, on the reference rig above, 30s per timed scenario. Every one
of the 16 dumps recorded **120.0 Hz measured, 8.333ms nominal, 1114×906pt, 1x, legacy
scrollers** — the cadence held in every scenario of every run, which is the one thing this
epoch set out to establish. Dumps are in `spike/results/`, stamped `20260917-09`/`-10`.

| Scenario | Metric | Threshold | `appkit-table` run 1 / run 2 (median) | `m1-production` run 1 / run 2 (median) |
| --- | --- | --- | --- | --- |
| S1 scroll | frame p95 | ≤ 8.5ms | 16.75 / 16.75 (16.75) FAIL | **16.75 / 16.75 (16.75) FAIL** |
| S2 storm, idle | frame p95 | ≤ 2× nominal (16.67ms) | 8.50 / 8.50 (8.50) PASS | **16.75 / 31.50 (24.13) FAIL** |
| S3 storm, scrolling | frame p99 | ≤ 3× nominal (25ms) | 23.50 PASS / 43.50 FAIL (33.50) | **20.50 / 19.75 (20.13) PASS** |
| S2 storm, idle | anchor drift worst | ≤ 815pt | 244.0 / 244.0 (244.0) PASS | **320.0 / 348.0 (334.0) PASS** |
| S3 storm, scrolling | anchor drift worst | ≤ 815pt | 260.0 / 211.0 (235.5) PASS | **268.0 / 296.0 (282.0) PASS** |
| S4 prepend ×20 | samples | = 20 | 20 / 20 PASS | **20 PASS / 19 FAIL** |
| S4 prepend ×20 | anchor drift worst | 0.0pt baseline, ≤ 0.5pt | 0.000 / 0.000 PASS | **0.459 / 0.434 (0.447) PASS** |

Gate result: both renderers **FAIL**, each on a different bar.

### The first attempt at this table was void — read this before trusting a geometry

Four earlier runs on this same rig recorded a **1327pt** timeline viewport against the 906pt
the baseline is measured at, and the run log reported the pinned window frame the whole time.
Pinning the `NSWindow` does not constrain the SwiftUI layout inside it: `HarnessRootView`
pinned the pane's *width* only, SwiftUI sized the pane to its content's ideal height, and the
window simply clipped it. The 1512×949 laptop panel had been clamping the whole thing back to
906pt, which is why MATRIX-60 never saw this. A 2560×1440 display does not clamp it.

That is 47% more rows drawn per frame, and it moved real numbers — `m1-production`'s S3 p99
read 55.50/68.00ms at 1327pt and 20.50/19.75ms at 906pt. A **pass/fail flip caused entirely
by geometry.** Those four runs were discarded.

The pane height is now pinned alongside the width, the window's min and max sizes are clamped
too, and `evaluate-gate.py` refuses a dump whose `timelineHeight` is not 906pt ± 0.5. The
field GATE.md previously described as "not scored — it records which window the numbers came
from" was load-bearing all along.

### What this table says

1. **The cadence discipline works.** 16 dumps, 16 identical quanta, no flap, no refusal.
2. **S1 p95 = 16.75ms in all four runs, both renderers.** Perfectly reproducible, and the
   control arm fails it as hard as production does. 8.5ms is one 120 Hz frame, so this metric
   asks "did 5% of frames drop a single frame" — and the automated driver steps the clip view
   from a `1/120s Task.sleep`, a software timer racing the vsync it is being measured against.
   At a pinned 120 Hz it has no headroom to absorb its own jitter. The pre-epoch 8.50ms
   readings were taken at an unrecorded cadence, quite possibly 60 Hz, where the same driver
   had twice the budget per step. **The S1 bar is now measuring the driver, not the
   renderer.** It wants a follow-up — either drive the scroll from the display link instead of
   a timer, or re-derive the bar from pinned reference runs. Do not move the bar to make it
   green.
3. **The MATRIX-57 storm-idle failure survives, and narrows.** `m1-production` misses S2 p95
   in both runs (16.75 and 31.50 against 16.67) where the control arm sits at 8.50 in both.
   That is the cleanest production-versus-reference separation in the table.
4. **S3 no longer separates them** — production passes it (20.13 median) and the control arm
   straddles it (23.50 / 43.50). The pre-epoch reading that made S3 look like production's
   worst scenario was recorded at the wrong geometry.
5. **Prepend anchoring is production's other weak spot,** consistently: 0.459 and 0.434pt
   against the control arm's exact 0.000pt in both runs, and one run resolved only 19 of 20
   samples. It passes, but with 10% of the tolerance left.

Run-to-run spread is tight where the scenario is steady (S2 p95 8.50/8.50 on the control arm,
S3 p99 20.50/19.75 on production) and wide where it is bursty (S2 p95 16.75/31.50 on
production, S3 p99 23.50/43.50 on the control arm). Two runs cannot distinguish a burst from a
trend, so **treat a single failing storm run as a prompt to re-run, not as a verdict.**

Two things changed under `m1-production` between the pre-cadence table and this one, and both
have to be read into these numbers:

1. **The cadence is now 120 Hz by construction, not by luck.** The S2 and S3 bars are
   multiples of the measured nominal, so they were 33.3ms and 50ms in any run that presented
   at 60 Hz. They are 16.67ms and 25ms here, in every run.
2. **The drain budget is a share of a frame, not a flat 6ms** (MATRIX-64, see below). At
   120 Hz that is 3ms rather than 6ms per callback, which is the same ~120 rows/second of
   capacity spread over twice as many callbacks.

## Pinned-frame baseline — 2026-09-15 (pre-cadence epoch, not comparable)

**Recorded before the cadence was pinned. These dumps carry no `environment`, so the frame
quantum their milliseconds were measured against is unknown, and `evaluate-gate.py` refuses
to score them.** They stay here because the conclusion they support — the production
container's storm-idle failure — is not in doubt; the figures themselves are.

Both renderers, two runs each, same machine, same release build, same driver, 30s per timed
scenario, every dump at **1114×906pt**. Dumps are in `spike/results/`, stamped
`20260915-11`/`-12`.

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

## The drain budget is cadence-aware (MATRIX-64)

Pinning the gate at 120 Hz raised a question about the thing being measured, not just about
the measurement. MATRIX-57 paces the container's row updates against its own `CADisplayLink`
and gave each callback a flat **6ms**, calibrated against a 60 Hz frame: a third of 16.67ms,
two rows per callback at ~2.6ms a row, ~120 rows/second against the ~60 rows/second a 10 Hz
storm of six mutations produces.

Both halves of that move with the refresh rate, in opposite directions:

- **Capacity** falls with the rate, because a flat budget fixes rows *per callback*. 60 Hz is
  the floor the number was chosen at, so **throughput at 60 Hz is the designed 2× headroom,
  not a shortfall — the queue drains.** The premise that a 60 Hz panel starves the drain is
  the wrong way round.
- **Frame share** rises with the rate. A flat 6ms is 72% of a 120 Hz frame, leaving the
  SwiftUI update, the table's layout and the compositor 2.3ms of 8.33ms.

`Models.TimelineDrainBudget` replaces the constant with a share of the interval the link
reports, `0.36 × frameInterval`, clamped to 30-240 Hz. It is the same 6ms at 60 Hz. Rows per
callback is `budget / rowCost`, so capacity is `(share × interval / rowCost) × (1 / interval)`
and the interval cancels: two rows per callback at 60 Hz, one at 120 Hz, five at 24 Hz, and
~120 rows/second at all three. `TimelineDrainBudgetTests` holds that property at every rate.

Whether the smaller per-callback budget also moves the S2 and S3 frame times is a question
for the first pinned-cadence baseline, not a claim made here.

## Adding a scenario

`ScenarioRunner.RunnerOptions.Scenario` lists them; `ScenarioRunner.run(_:)` drives them and
`ScrollDriver` moves the viewport. Thresholds live at the top of `evaluate-gate.py`, as
constants rather than comments, so changing one is a diff somebody reviews.
