# E-M1-01 — Production Timeline (M1 PRD)

| | |
|---|---|
| **Milestone** | M1 — Core messaging (Contract §4) |
| **Roadmap bullets** | M1: timeline v1 (per M0 decision), compose v1, media, design tokens (2026-09-01 constraint) |
| **Risks retired** | R-1 residual (production re-verification via S-12 harness) |
| **Open questions closed** | Q-6 is decided at this PRD (D-4); M1 PRD questions from the seed → D-1…D-6 below |
| **Status** | PRD draft for Patrick's review — 2026-09-01 |

## 1. Goal

Replace the inherited Mactrix timeline with the production timeline per the S-15
decision, hardened until it carries a full day of bridged DM traffic without
opening Beeper or Element (contract M1 exit criteria). The inherited
implementation supplies the skeleton — data layer, inverted table container,
composer, media rows — so this epic is **harden-and-extract, not greenfield**.
Two constraints from the 2026-09-01 wishlist discussion shape everything: the
timeline consumes a design-token layer from day one, and row view-models and
layout math live in `MactrixLibrary` so only the scroll container is
macOS-specific.

## 2. Decided foundations (do not relitigate)

- **2026-08-20 (S-15):** the timeline is **AppKit-backed** — `NSTableView`
  wrapped in `NSViewControllerRepresentable`, pre-measured row heights,
  measured-delta prepend compensation. Evidence: S-12 harness, 10k events,
  120 Hz — prepend ×20 anchoring 20/20 samples at 0.0pt worst, mutation-storm
  drift 815pt vs SwiftUI's 4238pt, frame p95 ≤ 8.5ms. Harness and baselines
  under `spike/results/` (workload fingerprint `wl1-4246e7b15677d961`).
- **Glass rule (Contract):** the timeline is opaque. Liquid Glass stays on the
  navigation layer only.
- **2026-09-01 constraint 1 — design tokens from day one:** the timeline
  consumes a token layer (typography, density, accent, bubble styling) rather
  than hardcoded values. The token story (S-36) and the container work are
  peers, not sequential — retrofitting tokens later is miserable.
- **2026-09-01 constraint 2 — platform-neutral row math:** row view-models and
  layout math live in `MactrixLibrary` (which already links
  `MatrixRustSDK` and can compile for iOS — the SDK ships iOS slices). Only
  the scroll container (`NSTableView`) is AppKit-specific; a future iOS
  container would be `UICollectionView` re-using the S-15 methodology and the
  same row layer. This is the seam E-APP-03 (native/iOS extras) and E-APP-05
  (port question) depend on.

## 3. Current state (inherited inventory)

What the fork already carries, verified 2026-09-01:

| Layer | Where | State |
|---|---|---|
| Data layer | `Mactrix/Models/LiveTimeline.swift` | Solid. `TimelineFocus.live`, `TimelineConfiguration` (daily date dividers, `.allEvents` read receipts, `reportUtds: true`), full `TimelineDiff` application (append/clear/pushFront/insert/set/remove/truncate/reset), back-pagination subscription, reply-details lazy loading, composer draft persistence. Weakness: array maintained in SDK order, reversed per container update. |
| Container | `Mactrix/Views/ChatView/TimelineView/TimelineTableView.swift` | The inverted-table trick is already here: `BottomStickyTableView` (`isFlipped == false`), `NSDiffableDataSourceSnapshot`, offscreen `NSHostingController` measurement in `heightOfRow`, 200px-from-oldest-end pagination trigger, content-only full-reload path. **Missing: prepend anchor compensation** (the S-14 winner's mechanism never landed in inherited code). Conflicts: `usesAutomaticRowHeights = true` alongside manual `heightOfRow`. `fatalError` in the row mapping. Row info untyped in the app target. |
| Row content | `MactrixLibrary/Sources/UI` + `MessageFormatting` | `ChatMessageView` renders bodies, reactions (toggle works), replies; `GenericEventView`/`VirtualItemView` for state/virtual rows; media rows (`MessageImageView`, `MessageVideoView`, `MessageFileView`) exist. `@AppStorage("fontSize")` is the only "theming" today. |
| Protocol abstraction | `MactrixLibrary/Sources/Models/EventTimelineItem.swift` | The platform-neutral pattern already exists: library-side protocols (`EventTimelineItem`, `MsgLikeContent`, `Reaction`) with SDK conformances in the app target. S-31 extends this pattern, it does not invent one. |
| Composer | `ChatInputView.swift` | Markdown send (`messageEventContentFromMarkdown`), reply mode, SDK draft save/restore, scroll-to-bottom on send. Missing: send-failure surface, unread-jump affordance, Enter-behavior decision. |
| Notifications | `Mactrix/Models/Notifications.swift` | `UNUserNotificationCenter` delegate exists. M1 bullets (per-room mute, dock badge, focus-room suppression) unverified. |
| Room list | `SidebarView.swift`, `RoomRow.swift` | Sections (Favorites/Directs/Rooms/Spaces) work. Unread badges, recency sort, bridge-aware avatars/names, mute state: not present or unverified. |

## 4. Gaps vs contract M1

| Contract M1 bullet | Inherited state | Gap → story |
|---|---|---|
| Timeline v1: render text/media/state, day separators, sender grouping, back-pagination, read markers, typing | Renders all item kinds; day dividers configured in SDK; pagination trigger exists | Prepend compensation (S-33), typed row layer (S-31), height cache (S-32), read marker + typing section wiring + diff-cost fix (S-34), UTD/error display (S-35) |
| Compose v1: plain text send, replies | Markdown send + replies + drafts exist | Enter default (D-1), failure/retry, unread jump (S-37) |
| Media: inline thumbnails, Quick Look, save | Rows exist, unverified on bridged rooms | Bridged-room verification + gap-fill (S-38) |
| Notifications: local, dock badge, per-room mute | Delegate exists, mute/badge unverified | Depends on D-6 (this epic vs E-M1-02) |
| Room list: recency, unread badges, DM distinction, bridge-aware names, mute | Sections + DM distinction exist | Depends on D-6 (E-M1-02 candidate) |
| Chrome: `NavigationSplitView`, glass toolbar/sidebar, opaque content | Largely in place from M0+S-16…S-30 | Audit tail item (D-6) |
| Exit: full day of bridged DM traffic, no p95 hitches | Not yet | Harness baselines (S-39) + Patrick's day (§8) |

## 5. Decisions needed from Patrick

These gate story details. Recommendations are mine; the pick is yours.

- **D-1 Send UX** — Recommend: Enter sends, Shift-Enter newlines (Beeper
  parity; M2 makes it configurable per contract). Affects S-37.
- **D-2 Pagination UX** — Recommend: keep infinite scroll with a visible
  activity state at the oldest end (Beeper parity; inherited 200px threshold
  retained). Alternative: explicit "load older" button. Affects S-34.
- **D-3 Receipts / typing / edits surface** — Recommend: typing indicator on
  (section already sketched), read receipts in **DMs only** for M1 (group
  receipts are noise), edits display inline with the edit marker (the send/edit
  UI stays M2). Affects S-34/S-35.
- **D-4 Q-6 — bridge-network grouping in the sidebar** (contract reserves this
  for M1 PRD time) — Recommend: **defer past M1**. The network set itself is
  in flux until the E-HS-03 re-homing cutover; grouping semantics designed
  today would be designed against a dying bridge topology. Revisit after
  cutover. Recording the decision closes Q-6.
- **D-5 Token layer placement** — Recommend: a `Tokens` module under
  `MactrixLibrary/Sources/UI/`, sibling to (not inside) `MessageFormatting`;
  formatting code consumes tokens rather than owning them. Affects S-36.
- **D-6 Epic split** — Recommend: **this epic covers the timeline surface
  only** (row layer, container, tokens, composer, media, harness — S-31…S-39).
  Room-list refinement, notifications pass, and chrome audit become a short
  **E-M1-02** epic after this lands. Keeps the PRD's exit criteria crisp.

## 6. Stories

Sized to one session each (≤ half a day), M0 house rules: builds clean, tests
pass, manual smoke on the dev account where user-visible, no new SwiftLint
violations. Story numbers continue from S-30.

### Cluster A — Platform-neutral row layer

**S-31 Timeline row view-models in `MactrixLibrary`**
- `TimelineRow` model (message / state / virtual cases carrying all render
  data), extending the existing `EventTimelineItem`/`MsgLikeContent` protocol
  pattern — SDK conformances stay in the app target.
- Replaces the app-target `TimelineItemRowInfo` and its `fatalError` with a
  total mapping; `uniqueId` handling moves into the model.
- Output: unit tests for the mapping; row rendering unchanged visually.

**S-32 Row measurement + height cache**
- Measurement math (row + width + tokens → height) as pure library functions
  over `TimelineRow`; a height cache keyed by (row id, width, token set).
- Container drops `usesAutomaticRowHeights` and relies on manual
  `heightOfRow` + cache only — the S-14 mechanism, without the AppKit
  auto-sizing conflict.
- Output: measurement unit tests; cache hit behavior observable in logs.

### Cluster B — Container productionization

**S-33 Measured-delta prepend compensation**
- Port the S-14 anchor mechanism into `TimelineViewController`: before a
  prepend batch (pagination pushFront), record the anchored visible row's
  offset; after apply, restore by the measured height delta.
- Acceptance: prepended batches leave the visible content unmoved — verified
  by S-39 harness runs, matching the `spike/results/` 0.0pt baseline class.

**S-34 Container hardening**
- Diff application without per-update full-array rebuild: maintain the
  display-ordered model once (no `reversed()` on every update), snapshot
  updates derived from the diff, not from a rescan.
- Reuse-identifier granularity beyond message/state/virtual; typing-indicator
  section wired (already declared as `TimelineSection.typingIndicator`); read
  marker row; day-separator rendering verified against the SDK's
  `.daily` dividers on a real bridged room.
- Pagination activity state per D-2.

**S-35 UTD and error display**
- `reportUtds: true` is configured — surface the UTD row with the crypto
  layer's cause (via `UtdReporter`), pagination/fetch error state, and
  `focusedTimelineEventId` deep-link arrival (room open at event).
- Receipts/typing display per D-3.

### Cluster C — Design tokens (peer story, starts in parallel)

**S-36 Token layer**
- `MactrixLibrary` token module per D-5: typography scale, density, accent,
  bubble styling. Row content views (`ChatMessageView` chain, message bubble,
  `GenericEventView`, `VirtualItemView`) consume tokens — no hardcoded
  row-styling values land after this story.
- `AppearanceSettingsView` (exists) wired to token values; `fontSize`
  `@AppStorage` migrates into the token set.
- Output: token unit tests + snapshot updates; appearance change visibly
  re-styles the timeline.

### Cluster D — Composer + media v1

**S-37 Composer v1**
- Enter/Shift-Enter default per D-1; send-failure surface with retry (local
  echo error state); scroll-to-bottom affordance with unread-count chip;
  draft restore verified across relaunch.

**S-38 Media v1**
- Bridged-room verification pass: image/video/file rows render inline,
  Quick Look on click, save-to-Downloads. Fill whatever the inherited views
  miss on real bridged media. No new upload UI (that is M2).

### Cluster E — Regression harness

**S-39 Harness drives the production container**
- Refactor so the S-12 harness can mount the real row layer + container
  (rendererID e.g. `m1-production`) with the same synthetic workloads and
  fingerprint `wl1-4246e7b15677d961`.
- Record M1 baselines; thresholds: frame p95 ≤ 8.5ms, prepend ×20 anchor
  0.0pt worst, mutation-storm drift ≤ 815pt. On-demand script (perf numbers
  from shared CI runners are noise — document the run procedure instead).
- Output: `spike/results/` gains `m1-production-*` baselines; the thresholds
  become the PR gate for every subsequent timeline story.

## 7. Sequencing

```
S-36 (tokens) ──────┐          peer, starts immediately
S-31 → S-32 ────────┼→ S-33 → S-34 → S-35    container line
                    └→ S-37 → S-38           content line (needs row layer + tokens)
S-39 after S-33 + S-34 (final container shape) — then runs with every later story
```

S-36 is deliberately unblocked from the container line so token design never
waits on AppKit mechanics, and row views never hardcode values waiting on
tokens.

## 8. Exit criteria (binary)

- [ ] Harness baselines recorded for the production container; thresholds
      green (p95 ≤ 8.5ms, prepend anchor 0.0pt, storm drift ≤ 815pt).
- [ ] 10k-event room: prepend ×20 leaves visible content unmoved; mutation
      storm while scrolling stays under threshold.
- [ ] Day separators, sender grouping, read marker, typing indicator correct
      on a real bridged DM room.
- [ ] Drafts survive relaunch; send failures show a retry affordance.
- [ ] Media: inline render, Quick Look, save-to-Downloads on bridged content.
- [ ] Appearance settings restyle the timeline via tokens — zero hardcoded
      row-styling values.
- [ ] Row layer + measurement compile in `MactrixLibrary` with no AppKit
      import (container excepted).
- [ ] **Patrick's day:** a full day of bridged DM traffic handled without
      opening Beeper or Element, no visible scroll hitching. (This is the
      manual gate; it is yours.)

## 9. Out of scope (M2/M3/epics)

- Edit/reaction/redact **send** UI (M2) — display of edits/reactions is in
  scope here.
- Markdown composer settings, mentions autocomplete, message forwarding (M2).
- Room-list refinement, notifications pass, chrome audit — E-M1-02 per D-6.
- Search, jump-to-context (M3 — but S-35's focus-event work is its seam).
- Broadcast composer (E-APP-02) builds on S-37's composer; nothing here
  pre-empts it.
- Threads UI (M4 read-only at most; thread focus already plumbed in
  `LiveTimeline`).

## 10. Risks

| Risk | Signal | Response |
|---|---|---|
| Per-row `NSHostingView` sizing cost at 10k rows | S-39 p95 breaches 8.5ms | Height cache (S-32) first; coarser reuse identifiers (S-34); worst case restrict hosting-view re-measure to width changes |
| Diffable snapshot rebuild O(n) per update visible in long rooms | Frame drops on busy rooms | S-34's diff-derived updates; fallback: incremental snapshot applies |
| Token over-abstraction stalls container work | S-36 slips or sprawls | Keep S-36 to values the timeline consumes day one; E-APP-01 owns the full system later |
| Harness fidelity gap vs real bridged traffic | Green harness, hitchy real day | Accept: harness is regression, the manual day is the gate; instrument the day with OSLog signposts if it fails |
| `usesAutomaticRowHeights` removal changes intrinsic behavior | Row-height regressions after S-32 | Compare against spike baselines in S-39 immediately after S-32 |
| SDK pagination quirks (back-pagination status only on main timeline, per inherited comment) | Thread rooms misbehave | Keep inherited thread workaround; note for M4 threads |

## 11. Definition of done for this epic

All §8 criteria checked. Harness baselines committed under `spike/results/`.
Q-6's disposition (D-4) and any D-1…D-6 picks recorded in Contract §11. Every
story PR'd on an `s-XX/…` branch per house workflow; merged only by Patrick.
