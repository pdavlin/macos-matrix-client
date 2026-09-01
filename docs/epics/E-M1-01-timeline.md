# E-M1-01 — Production Timeline (PRD seed)

Status: seed — drafted 2026-09-01 from the S-15 decision plus two constraints
Patrick approved during the 2026-09-01 feature-wishlist discussion. The full
PRD (scope, milestones, story decomposition) is still to be written with
Patrick; this file records the constraints that must not get lost between now
and then.

## Foundation (decided, in contract §11)

- 2026-08-20 (S-15): the timeline is **AppKit-backed** — `NSTableView` wrapped
  in `NSViewRepresentable`, pre-measured row heights, measured-delta prepend
  compensation. Evidence: S-12 harness, 10k events, 120 Hz — prepend ×20
  anchoring AppKit 20/20 at 0.0pt worst; mutation-storm drift 815pt vs
  SwiftUI's 4238pt. SwiftUI's below-viewport anchor gap is structural
  (`defaultScrollAnchor` covers only one edge). Harness and candidate dumps
  live under `spike/results/` for M1 regression use.
- Glass rule: the timeline is opaque. Liquid Glass stays on the navigation
  layer only.

## Constraints recorded 2026-09-01

These two come out of the "features Beeper doesn't have" wishlist (Plane
epics E-APP-01/02/03) and Patrick's answers:

1. **Design tokens from day one.** The timeline must consume a token layer
   (typography, density, accent, message-bubble styling) rather than
   hardcoded values, because the design-system epic (E-APP-01) makes
   user-tunable appearance cheap forever if the tokens exist at build time
   and miserable if retrofitted. The token architecture story and the
   timeline build are peers, not sequential.
2. **Platform-neutral row math.** Row view-models and layout math live in
   `MactrixLibrary` (compilable for macOS and iOS), with only the scroll
   container AppKit-specific. Rationale: two of the four wishlist features
   (custom design, native features + on-device models) explicitly target
   iOS, so the timeline — the one component an eventual port can't share —
   should at least share its non-AppKit half. The iOS container would be
   `UICollectionView` in `UIViewRepresentable`, re-using the S-15 methodology.

## Open PRD questions (for the planning session)

- Message send UX (the broadcast epic E-APP-02 builds on it).
- Read receipts / typing / edits / reactions surface area (SDK-exposed only).
- Pagination UX and the M1 regression harness derived from `spike/results/`.
- Where the token layer lives relative to `MessageFormatting`.
