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
4. Check the HUD shows a non-zero `visible` count and a `tracked` id. A candidate that
   never reports its visible set produces zero drift samples, and every drift column in the
   run comes out empty. That is a broken run, not a good result.
5. Press "Reset instruments" (Cmd-R). Never record a run that includes app launch or a
   candidate switch: first-layout cost is real, but it is a separate question from steady
   state and it swamps the percentiles.
6. Run the scenario.
7. Press "Dump stats to JSON" (Cmd-D). Keep the file.

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

Attach the JSON files to the story. They carry the seed, the driver settings, the drift
settle window, the workload fingerprint, the OS version and the machine model, so a number
can always be traced back to the run that produced it.

Before building the table, check that every file shares one `workloadFingerprint` and one
`configuration.driftSettleTicks`. If they do not, the rows are not comparable. See §10.

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
  the top of the viewport. It closes `configuration.driftSettleTicks` frames after the
  change, three by default. If the tracked event leaves the viewport before the sample
  closes, the sample is discarded and counted in `discardedDriftSampleCount` rather than
  scored as zero.
- **Drift is not only anchoring failure.** The tracked event is the middle visible one, so
  a mutation that grows an event *above* it but still on screen moves it legitimately: the
  content really did get taller. In S2 and S3, where half the mutations target the visible
  range by design, some of `mutationDrift` is content movement that no renderer can or
  should prevent. Compare the two candidates against each other on this number; do not read
  a single candidate's `mutationDrift` as its anchoring error. `prependDrift` in S4 has no
  such confound: a prepend only inserts above the viewport, so every point of drift there
  is anchoring failure.
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

Candidate A was `SwiftUIListRenderer` (S-13), removed after the S-15 decision (2026-08-20,
contract §11): its S3 worst anchor drift was 4238pt against AppKit's 815pt, and it captured
18 of 20 prepend samples in S4 against AppKit's perfect 20/20 at 0.0pt. The surviving
renderer is `AppKitTableRenderer` (S-14). The measurement dumps for both candidates and the
placeholder live in `spike/results/`. The harness stays for M1 regression use: re-run these
scenarios whenever the row workload or the real timeline implementation changes.

## 9. Determinism

The generator is a pure function of `(seed, index)`. The same seed produces the same 10k
events on any machine, and the same events for every back-pagination batch, without bound.
Day separators use a fixed UTC calendar for the same reason. If two runs disagree, the
difference is the renderer or the machine, never the data.

## 10. Measurement hygiene

Added in S-13. This section governs the S-13 to S-15 window.

### The row workload is frozen

`SpikeRowView` and `SpikeRowMetrics` do not change until S-15 lands in Contract §11.

Every frame time in this comparison is dominated by how much text and how many shapes a
row lays out. Change one padding and every row height changes, every viewport holds a
different number of rows, and the two candidates' numbers stop meaning the same thing. The
change is invisible in the JSON, which is what makes it dangerous: nothing about the file
says it came from a different workload.

Detection is now mechanical. Every dump carries `workloadFingerprint`, a digest of the
`SpikeRowMetrics` constants, the behaviour of `imageSize(for:availableWidth:)` at fixed
probe points, and the `SpikeCorpus` pools. **Two dumps with different fingerprints must not
appear in the same table.** The console shows the current value next to the dump button, so
it can be checked without opening the file.

The fingerprint is pinned by `WorkloadFingerprintTests`. A workload edit fails the test
suite. Do not update the pinned constant to make it pass: revert the edit, or, if the
change is genuinely wanted, re-run every scenario for every candidate and say so in the
story.

Two gaps the fingerprint cannot close, both covered by this freeze instead:

- The *structure* of `SpikeRowView`. A `View` is not introspectable, so an added row of
  chrome is invisible to the digest.
- Font weights and designs, which live inside `Font` values with no stable textual form.
  Deriving the digest from those would make it vary by OS build, which would break
  cross-machine comparison — a worse failure than the one it fixes.

### Prefer a workload that is slightly too expensive

If the synthetic row is ever revised, err on the side of heavier than the real client, not
lighter.

The two errors are not symmetric. A workload that is too cheap makes both candidates clear
the bar, the spike concludes "either is fine", and the real timeline — with formatted
bodies, replies, read receipts and inline media — misses the budget in M1, when the
architecture is no longer cheap to change. A workload that is too expensive costs a
candidate that would have been adequate, and the fallback in §6 is already written down.
Pay for a conservative architecture decision, not for an optimistic one.

### The drift settle window

`configuration.driftSettleTicks` sets how many display-link frames a drift sample waits
before it closes. It defaults to 3 and is exported in every dump, because a run measured
with a six-frame window is not comparable to a run measured with three. Changing it in the
console clears the drift accumulators for that reason.

Leave it at 3 for the four scored scenarios. Three frames cover a change that lands in the
next layout pass and is presented on the frame after that, with one frame of margin.

Raise it only for a candidate whose height changes are **animated**. An animated row
expansion is still in flight three frames in, so the sample closes mid-animation and scores
the transient position as drift, which reports a stable renderer as a drifting one. Set the
window past the animation's duration in frames — for a 0.25 s animation on a 120 Hz
display, at least 30 — and record the value you used in the story alongside the numbers.

Do not raise it to flatter a candidate that jumps and then corrects itself. That is the
failure this instrument exists to catch: at a long enough window, a renderer that scrolls
the content wrong and snaps it back a few frames later reports zero drift, and the user
still sees the flinch. If you raise the window, S4's by-eye check in §4 stops being
optional and becomes the primary result.
