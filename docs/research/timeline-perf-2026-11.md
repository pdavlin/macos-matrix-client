# Timeline performance check, November 2026 (MATRIX-174)

Date: 2026-11-17. Scope: the automated spike gate and three costs that earlier stories did not measure.
The 120 Hz gate of MATRIX-124 is not part of this check.

## Result in short

- The gate shows no regression in the timeline container on S1, S2, and S4 frame time.
- S3 was unstable: 4 of 9 runs had a p99 of 80 ms or more. The cause is not known. See finding F1.
- The S4 prepend drift moved from 0.447 pt to 0.480 pt. One run was above the 0.5 pt limit. See finding F2.
- The gate cannot see the November body changes, because the spike does not draw the app's message body.
  The micro-measurements found the largest cost there: an HTML body was parsed again and again. This is fixed.

## Method

1. Gate: `spike/run-gate.sh --renderer m1-production`, 30 s for each timed scenario, nine full runs, one after the other.
   Each run wrote its dumps to its own folder below `.agent-logs/gate/` (not committed).
   `spike/evaluate-gate.py` scored each run. No dump was refused, and the harness did not exit with 3.
2. Four more runs of S3 alone (`--scenario s3`), to isolate finding F1.
3. Micro-measurements: a scratch test in the `UITests` target of `MactrixLibrary`, built with
   `swift test -c release -Xswiftc -enable-testing`. The file is not committed.
   Each number is the median of 300 to 500 samples after a warm-up. The jumbo scan samples are batches of 200 calls.
4. No committed test makes an assertion on wall-clock time.

## Environment

- Mac17,9, Apple M5 Pro, macOS 27.3 (26C5035r). The baseline dumps are from macOS 27.0 (26A428).
- Display: LC49G95T, 2560x1440 at 1x, 120 Hz, scroll bars "Always". This is the reference rig of `spike/GATE.md`.
- Each dump: 120.0 Hz measured, 1114x906 pt, 1x, legacy scrollers, workload `wl1-4246e7b15677d961`.

### Limits of these numbers

- No number in this report came from a quiet machine.
- The owner used the Mac. A Parallels VM used 50% to 70% of one core for the full session.
  WindowServer used 35% to 55%. The load average was 3.4 to 6.2 at the start of each run.
- Runs 1 to 5 (12:58 to 13:10): other agents possibly compiled in this time. No sampler ran.
- Runs 6 to 9 (13:25 to 13:38) and the S3-only runs: a sampler counted the compiler processes every 3 to 5 s.
  Compiler processes ran during S1, S2, and S4 of run 6. None ran during S3 of run 6 or during runs 7, 8, 9, and the S3-only runs.
- The second micro-measurement pass ran with no compiler process of another agent, at a load average of 4.3.
- The baseline is two runs. The gate document tells you to treat one bad storm run as a prompt to run again.

## Gate numbers against the baseline

Baseline: the two pinned-environment runs of 2026-09-17 (09:54 and 09:56) in `spike/results/`.
The S1 and S3 rows of that baseline used the old wall-clock scroll driver (MATRIX-65 replaced it).
A baseline for the display-link driver was never recorded: `spike/GATE.md` shows "pending" for S1 and S3.
The six older runs in the main checkout (08:32 to 09:01) have no recorded environment, and four of them have the wrong geometry.
They are not used as a baseline.

| Scenario | Metric | Limit | Baseline (run 1 / run 2) | Now: median of 9 | Now: min to max | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| S1 scroll | frame p95 | 8.5 ms | 16.75 / 16.75 (old driver) | 8.50 | 8.50 to 8.50 | pass, better (driver change) |
| S1 scroll | frame p99 | none | 19.50 / 17.25 (old driver) | 8.50 | 8.50 to 8.50 | better |
| S1 scroll | worst frame | none | 41.8 / 57.5 | 22.3 | 16.7 to 33.3 | better |
| S2 storm, idle | frame p95 | 16.67 ms | 16.75 / 31.50 | 16.75 | 16.75 to 25.25 | fail, same as baseline |
| S2 storm, idle | frame p99 | none | 23.75 / 47.25 | 17.00 | 16.75 to 64.00 | no regression |
| S2 storm, idle | drift worst | 815 pt | 320 / 348 | 341 | 240 to 775 | pass, one run near the limit |
| S3 storm, scroll | frame p99 | 25.0 ms | 20.50 / 19.75 (old driver) | 20.25 | 16.75 to 116.50 | 5 pass, 4 fail (F1) |
| S3 storm, scroll | frame samples | none | 2928 / 2889 | 3016 | 805 to 3088 | 4 runs with half or less (F1) |
| S3 storm, scroll | drift worst | 815 pt | 268 / 296 | 301 | 255 to 391 | pass |
| S4 prepend x20 | samples | 20 | 20 / 19 | 20 | 14 to 20 | 5 pass, 4 fail, as baseline |
| S4 prepend x20 | drift worst | 0.5 pt | 0.459 / 0.434 | 0.480 | 0.454 to 0.501 | 8 pass, 1 fail (F2) |
| S4 prepend x20 | frame p99 | none | 24.25 / 24.50 | 17.25 | 10.75 to 765 | no regression in the median |

The S2 p95 failure is the known MATRIX-57 failure: 16.75 ms is two frames at the 0.25 ms percentile step, and the limit is 16.667 ms.
All nine runs ended with "FAIL", as the baseline did.

S3 alone, four runs: p99 17.00, 23.00, 19.25, 16.75 ms. Frame samples 2963 to 3115. All pass.

## Findings

### F1. S3 is unstable when it follows S2 in one process

- 4 of 9 full runs: p99 80.75, 93.00, 116.50, 81.50 ms, with 805 to 1485 frame samples where a good run has approximately 3000.
- 0 of 4 runs of S3 alone show this. 0 of 2 baseline runs show this.
- 3 of the 4 bad runs had no compiler process of another agent in the S3 window (run 2 had no sampler). In each bad run, S2 or S4 was slow too.
- S1 was stable in all nine runs, so the display and the scroll driver are not the cause.
- Possible causes, not proved: machine load from the owner's work and the VM, or a state that S2 leaves in the process.
- This is not proof of a code regression, and it is not proof of no regression.

### F2. The S4 prepend drift has almost no margin

- Median 0.480 pt against 0.447 pt in the baseline. Eight of nine runs are above the two baseline values.
- Run 9 read 0.501 pt, which is a gate failure.
- The drift is a part of a point, so machine load is not a probable cause. A row layout change is the probable cause.
  The row chrome changed in November (hover bar, day pill, sender rhythm).
- The next small layout change can make the gate fail on each run.

### F3. One S2 run had an anchor drift of 775 pt

- Run 3 only. The other eight runs: 240 to 528 pt. The baseline: 320 and 348 pt. The limit is 815 pt.
- That run had no slow frame count above the others. No cause is known. One sample is not a trend.

### F4. The gate does not measure the November body work

- The spike draws a stand-in body (`Text` or a shape). It does not link `MessageFormatting`.
- Body emoticons, jumbo custom emoji, image reaction chips, the reaction tooltip, the own-avatar values,
  the member fetch, and the thread-reply notice do not run in the gate.
- The gate does run the container changes: the hover bar tracking and layout hook, and the merged timeline changes in the table files.

### F5. An HTML body was parsed again on each evaluation (fixed)

- `FormattedBodyText.body` calls `parseFormattedBody`, which built a ZMarkupParser and rendered the HTML each time. There was no cache.
- A row with an HTML body paid this at least two times: the offscreen height measure, then the row in the table.
- `ChatMessageView` passes `onEmoticons: learnEmoticons` (MATRIX-161). A closure does not compare equal,
  so SwiftUI evaluates the body again each time the parent row is evaluated. Measured in a hosting view:
  10 parses for 10 updates with a new closure, 0 parses for 10 updates with no closure.
- Before MATRIX-161 the inputs could compare equal, so this cost is probably new in November.

## Micro-measurements

Release build. Median, in microseconds. "Before" is a body that the new cache does not hold, which is the cost of each parse before the fix.

| Operation | Before the fix | After the fix (same body again) |
| --- | --- | --- |
| Parse, 79-character HTML, no emoticon | 685 to 853 | 6 to 8 |
| Parse, 529-character HTML, no emoticon | 1422 to 1715 | 43 to 46 |
| Parse, 5 emoticons, images not in the image cache | 362 to 561 | 70 to 77 |
| Parse, 5 emoticons, images in the image cache | 544 to 731 | 221 to 250 |
| Parse, 9 emoticons jumbo, images in the image cache | 641 to 977 | 443 to 521 |
| Row body, 529-character HTML: measure pass / display pass | 1802 / 1800 | 1794 / 79 |
| Row body, 1 emoticon: measure pass / display pass | 616 / 617 | 599 / 123 |

The two values in a range are the two passes (first pass with possible compiler load, second pass without).
The second pass added a short unique tag to each body, so its "before" values are somewhat higher.

Emoticon render with `ImageRenderer`, for each emoticon that the image cache holds: 29 to 45 us.
(Difference between image cache hit and miss, divided by the emoticon count, for 1, 5, and 9 emoticons.)
This render still runs on each parse. For a jumbo body of 9 emoticons it is approximately 0.4 ms.

`ImageTagRewriter.rewrite`: 3.8 us with no `<img>`, 41 us with 5 emoticons.

Jumbo scan, `JumboEmoji.kind(body:formattedBody:)`:

| Body | Median |
| --- | --- |
| Prose, no HTML | 0.09 us |
| Prose with HTML | 0.23 to 0.25 us |
| One emoji, no HTML | 0.09 us |
| 9 emoji, no HTML | 1.1 us |
| 1 emoticon in HTML | 4.8 to 4.9 us |
| 9 emoticons in HTML | 43 to 46 us |
| 10 emoticons in HTML (above the limit) | 49 us |
| 1 emoticon, then prose | 4.9 to 5.2 us |

The jumbo scan is not a problem. A prose row costs less than 0.3 us, and the row fingerprint asks one time for each mapped item.
The regular expressions of the `<img>` reader cost approximately 5 us for each emoticon.

For scale: one frame at 120 Hz is 8333 us. Before the fix, one new row with a 529-character HTML body used
approximately 3600 us for its two parses, which is 43% of a frame.

## Fix made

`MactrixLibrary/Sources/MessageFormatting/Parser.swift`: `renderHTML` keeps its result in an `NSCache`
(512 entries), with the font size and the HTML as the key. The render depends on these two inputs only:
ZMarkupParser reads no appearance, screen, or clock value. The cache holds immutable copies, and
`EmoticonResolver` makes its own copy before it changes anything.
`MactrixLibrary/Tests/UITests/RenderedBodyCacheTests.swift` proves the key and the second parse of an emoticon body.
The four local checks passed.

The fix removes the repeated HTML render. It does not remove the repeated body evaluation, the tag rewrite, or the emoticon render.

## Not measured

- `fetchMembers` on timeline open. It is an SDK call that needs a homeserver and an account, and this story
  permits neither. From the code: `LiveTimeline` calls it one time for each new `LiveTimeline`, in a `Task` of
  utility priority. A new `LiveTimeline` is made on each room selection, for each part of a merged chat, and for each thread.
  The network and store work is in the SDK, off the main thread. The cost that can reach the main thread is the
  burst of timeline diffs when profiles change. Its size is not known.
- How frequently SwiftUI evaluates a row body in the real app (hover, selection, read receipts). The scratch test proves the mechanism only.
- The time to draw an emoticon attachment. The measurement covers the parse, not the draw.
- Image reaction chips, the reaction tooltip overlay, the own-avatar environment values, the day-label observable,
  and the thread-reply notice. The spike does not draw them, and no micro-measurement was made.
- The undocked 2x display. The gate does not cover it (see `spike/GATE.md`).

## Proposed follow-ups

1. Record a display-link baseline on a quiet machine: VM stopped, no agent sessions, two runs for each renderer, then commit the dumps and fill the "pending" table in `spike/GATE.md`.
2. Find the cause of F1: run S2 then S3 ten times on a quiet machine. If it stays, record a time profile of a bad run.
3. Find where the S4 prepend drift of 0.45 to 0.50 pt comes from (the reference renderer reads 0.000 pt) and remove it, before the gate fails on each run.
4. Stop the repeated body evaluation: make the `onEmoticons` path stable (for example, an environment action or an `Equatable` body view), so a row update with equal content skips the parse.
5. Cache the emoticon render by source and side, so a parse does not call `ImageRenderer` again for each cached image.
6. Measure `fetchMembers` in the app on the dev account with signposts: the count of calls for each selection and the size of the diff burst. Then decide if one call for each room in a session is sufficient.
7. Give the spike a body that uses `FormattedBodyText` with a stub image loader, so the gate can see body regressions.

## Processes started and stopped

- `TimelineSpikeApp` (through `spike/run-gate.sh`, under `caffeinate -dis`): 13 launches, all ended.
  One more launch (first try of run 7) ended immediately after its calibration with no dump. The cause is not known. The second try ran.
- Two load samplers (shell loops that wrote `.agent-logs/load-sampler.log` and `load-sampler2.log`): both stopped with `pkill`.
- No `yes` load generator was started. `pgrep` shows no harness or sampler process.
