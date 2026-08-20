# Timeline spike — measurement protocol

Status: authoritative for S-13, S-14 and S-15. Written 2026-08-19 as part of S-12.

S-13 (pure SwiftUI) and S-14 (AppKit-backed) each produce a set of numbers. Those numbers
decide the timeline architecture for the whole project. They are only comparable if both
candidates are measured the same way, so the procedure below is fixed. Do not vary it to
make a candidate look better. If a scenario is wrong, change it here first and re-run both
candidates.

## 1. Rig

Standalone SPM package, no matrix-rust-sdk, synthetic data only.

```
cd spike/TimelineSpike
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run TimelineSpikeApp
```

The report is written to the process working directory, so run the app from the directory
where you want the JSON files.

## 2. Fixed settings

Use these values for every recorded run. They are the defaults in `HarnessConfiguration`.

| Setting | Value |
|---|---|
| Seed | `6840123409045651498` (`0x5EED0000_0000002A`) |
| Initial events | 10000 |
| Mutations per tick | 6 |
| Mutation rate | 10 Hz |
| On-screen bias | 0.5 |
| Prepend batch | 50 |
| Window size | leave the default 1080x860. Do not resize during a run. |

Machine conditions:

- Mains power. Low Power Mode off.
- Debug configuration for the first pass, release for the recorded numbers. State which one
  the report came from in the scenario label.
- Nothing else running that fights for the GPU. Close Xcode's preview canvas.
- One display. Note the refresh rate; the HUD's `nominal` field records it.

## 3. Before every scenario

1. Select the candidate in the picker. Switching candidates resets the instruments.
2. Set the scenario label in the console. Use the exact names below.
3. Scroll to the bottom of the timeline and wait two seconds for the app to settle.
4. Press "Reset instruments" (Cmd-R). Never record a run that includes app launch or a
   candidate switch: first-layout cost is real, but it is a separate question from steady
   state and it swamps the percentiles.
5. Run the scenario.
6. Press "Dump stats to JSON" (Cmd-D). Keep the file.

## 4. The four scenarios

### S1 — cold scroll to top through 10k

Measures: sustained layout throughput and height estimation over the full corpus.

1. Mutation storm off. Automatic pagination **off**.
2. From the bottom, scroll continuously to the top of the loaded content with a trackpad
   two-finger drag. Aim for a steady 3 to 4 seconds per screen. Do not flick.
3. Stop when the first loaded event is on screen.
4. Dump.

Read: `frame.p95Milliseconds`, `frame.p99Milliseconds`, `frame.hitchCount`,
`frame.worstMilliseconds`.

Anchor drift is not meaningful here. No prepends and no mutations occur.

### S2 — mutation storm while idle

Measures: invalidation cost and anchor stability when heights change under a static
viewport.

1. Scroll to roughly the middle of the timeline. Stop moving.
2. Automatic pagination off.
3. Start the mutation storm (Cmd-M). Leave the pointer off the window.
4. Run for 60 seconds.
5. Stop the storm. Dump.

Read: `frame.p95Milliseconds`, `frame.hitchCount`, `mutationDrift.meanMagnitude`,
`mutationDrift.worstMagnitude`, `mutationDrift.stableCount` over `mutationDrift.count`.

This is the scenario that kills naive SwiftUI lists. A mutation to an off-screen event that
changes its height must not move the visible content.

### S3 — mutation storm while scrolling

Measures: the two costs together, which is the real usage pattern in a busy bridged room.

1. Automatic pagination off. Start the mutation storm.
2. Scroll continuously up and down over a range of about 2000 events for 60 seconds.
3. Stop the storm. Dump.

Read: everything from S2, plus `frame.p99Milliseconds`.

Expect this to be the worst scenario for both candidates. It is the one that decides the
architecture.

### S4 — prepend at top x20

Measures: scroll anchoring across back-pagination, which is the failure mode that makes a
client feel broken.

1. Mutation storm off. Automatic pagination **off**, so every prepend is deliberate.
2. Scroll until the first loaded event is near the top of the viewport, then scroll down
   slightly so a tracked event sits mid-viewport. Check the HUD shows a `tracked` id.
3. Press "Prepend now" (Cmd-P) 20 times, roughly one per second. Do not touch the scroller
   between presses.
4. Dump.

Read: `prependDrift.count` (must be 20; a lower count means samples were discarded because
the tracked event left the viewport, which is itself a failure), `prependDrift.meanMagnitude`,
`prependDrift.worstMagnitude`, `prependDrift.stableCount`.

Also record by eye: did the content visibly jump on any prepend? A candidate that jumps once
in 20 fails, whatever the mean says.

### S5 — automatic pagination sanity check (not scored)

Turn automatic pagination on and flick to the top repeatedly. This is a robustness check,
not a measurement: it should not deadlock, should not prepend on every frame, and should not
run out of memory. Note anything odd in the story write-up.

## 5. What to record per candidate

One JSON file per scenario, plus a table in the S-13 / S-14 story:

| Scenario | p50 ms | p95 ms | p99 ms | worst ms | hitches | prepend drift mean/worst pt | mutation drift mean/worst pt |
|---|---|---|---|---|---|---|---|

Attach the JSON files to the story. They carry the seed, the driver settings, the OS version
and the machine model, so a number can always be traced back to the run that produced it.

## 6. Pass bar

From Contract §7 and §2 of the M0 epic:

- **Frame time:** no visible hitching at p95. Concretely, `p95 <= 2 x nominal` in S1 and S2,
  and `p99 <= 3 x nominal` in S3. On a 120 Hz display that is p95 within 16.7 ms and p99
  within 25 ms.
- **Anchor on prepend:** `prependDrift.worstMagnitude <= 1 pt` across all 20 prepends in S4,
  and `prependDrift.count == 20`.
- **Anchor on mutation:** `mutationDrift.worstMagnitude <= 1 pt` in S2.

A candidate that misses the frame bar but holds both anchor bars is still viable; a
candidate that drifts is not. Scroll position is correctness, frame time is polish.

If both candidates miss the bar, the epic's risk table already says what happens: prefer
AppKit, reduce item complexity, and carry a perf story into M1.

## 7. Reading the instrumentation honestly

- **Frame time is presentation cadence, not work per frame.** The recorder measures the gap
  between presented frames from a `CADisplayLink` attached to the window's view. A 24 ms gap
  means the user saw a stutter. It does not say where the time went. When a candidate loses,
  take an Instruments trace before concluding why.
- **Percentiles are quantised to 0.25 ms.** That is the histogram bucket width, reported in
  every JSON file as `percentileResolutionMilliseconds`.
- **A hitch is a frame over twice the nominal interval**, that is, at least one dropped
  frame. The nominal interval is read from the display link, so it is correct on a ProMotion
  display and on an external 60 Hz panel.
- **Drift is measured against one tracked event**, the middle visible one, in points from
  the top of the viewport. It closes three frames after the change. If the tracked event
  leaves the viewport before the sample closes, the sample is discarded and counted in
  `discardedDriftSampleCount` rather than scored as zero.
- **The HUD refreshes at 5 Hz from a snapshot**, not from live observation. Do not
  "improve" this: binding the HUD to the display link would make the instrument perturb the
  thing it measures.

## 8. What a candidate owes the harness

A candidate is a `TimelineRenderer`: a `View` constructed with the harness and nothing else.
It must:

- Render `harness.store.items` inverted and variable-height, starting at the bottom.
- Use `item.daySeparator` and `item.startsSenderRun` as given. Do not recompute grouping.
- Call `harness.probe.reportVisible(_:range:)` when the on-screen set changes.
- Call `harness.probe.reportOffset(_:for:)` for the tracked item, in points from the top of
  the viewport, increasing downward, excluding the scroll position.
- Call `harness.viewportDidScroll(distanceFromTop:)` on scroll.
- Match `SpikeRowMetrics` exactly. SwiftUI candidates get this free from `SpikeRowView`; an
  AppKit candidate must reproduce the same paddings, fonts and image sizing, or the two
  candidates lay out different amounts of content and nothing below is comparable.

It must not throttle, coalesce or debounce store reads. That is the thing being measured.

`PlaceholderRenderer` in the app target shows the wiring end to end. It is **not** candidate
A: it has no anchoring strategy and no height estimation, and its numbers must never appear
in the comparison.

## 9. Determinism

The generator is a pure function of `(seed, index)`. The same seed produces the same 10k
events on any machine, and the same events for every back-pagination batch, without bound.
Day separators use a fixed UTC calendar for the same reason. If two runs disagree, the
difference is the renderer or the machine, never the data.
