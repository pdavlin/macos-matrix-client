# Epic E-M0-01 — Foundation: fork, build, inherit

| | |
|---|---|
| **Milestone** | M0 — Foundation (Contract §4) |
| **Roadmap bullets** | M0: fork; pin SDK / macOS slice; inherited login, session, verification, decryption; repo hygiene for agentic dev; timeline spike |
| **Risks retired** | R-1 (timeline), R-2 (SDK pin), R-3 (macOS slice), R-5 (licensing) |
| **Open questions closed** | Q-1, Q-2, Q-3, Q-4, Q-5 |
| **Status** | Draft — 2026-08-19 |

## 1. Goal

Get a buildable, runnable fork of Mactrix that logs in to the homelab homeserver, restores a session, verifies a device, and decrypts an E2EE room. Put the repo in a state where Claude Code can build, test, and read real FFI signatures without a human in the loop. Retire the timeline architecture risk with a spike before M1 starts.

No new user-facing UI ships in this epic. The deliverable is a foundation and a decision.

## 2. Exit criteria (binary)

- [ ] `git clone` + documented steps → clean build on Apple Silicon, current Xcode. No manual fixups.
- [ ] App logs in to the dev account (`@dev:…`) on the homelab Synapse via password and via SSO.
- [ ] Quit and relaunch restores the session from the keychain. No re-login.
- [ ] Emoji verification against a second device completes. Cross-signing state is verified.
- [ ] An E2EE room decrypts. Historical messages decrypt after key backup restore.
- [ ] `scripts/build.sh` and `scripts/test.sh` run headlessly and exit non-zero on failure.
- [ ] `CLAUDE.md`, `docs/skills/`, `docs/ffi/` exist and are current for the pinned SDK.
- [ ] Timeline spike done. Decision (SwiftUI vs AppKit-backed) recorded in Contract §11 with measurements.
- [ ] Q-1 through Q-5 have a dated answer in Contract §11.

## 3. Stories

Each story is sized to one Claude Code session (≤ half a day). Definition of done for each: builds clean, tests pass, manual smoke on the dev account where applicable, no new SwiftLint violations.

### Cluster A — Fork and build viability

**S-01 Fork and first build**
- Fork Mactrix into `matrix-mac-client`. Remove upstream remote. Set the bundle ID and team to local ad-hoc signing.
- Open in current Xcode. Fix build errors that come from Swift or SDK version drift only. Do not touch features.
- Output: green build of the unmodified app. Commit.

**S-02 Pin and verify `matrix-rust-components-swift` (Q-4, R-3)**
- Pin the exact version in `Package.resolved`.
- Inspect the shipped XCFramework. Record whether a `macos-arm64` slice exists and whether it links.
- If the slice is missing or broken: stand up the from-source build (`rustup`, `aarch64-apple-darwin`, `uniffi-bindgen` at the SDK's pinned version). Script it in `scripts/build-ffi.sh`.
- Output: a §11 entry for Q-4 and the chosen path. Store the source build path as insurance even if the binary slice works.

**S-03 Licensing check (Q-1, Q-2, R-5)**
- Read the Mactrix license. Read the license of `matrix-rust-components-swift` and of any Element-published package at the pinned version.
- Record obligations and any constraint on a future public release in §11.
- Output: `LICENSE` and `THIRD_PARTY_NOTICES.md` at repo root. Q-1 and Q-2 closed.

**S-04 Deployment target decision (Q-3)**
- Set min deployment target to macOS 26. Confirm the project builds and runs on the primary dev machine (macOS 27 beta if installed).
- Record the decision and the rationale in §11.

### Cluster B — Inherited functionality works

**S-05 Login: password and SSO**
- Point the login flow at the homelab homeserver. Confirm `.well-known` discovery works.
- Test password login with the dev account. Test SSO login if the homeserver has an IdP.
- Fix only what blocks login. Log the failures that are Mactrix bugs for later.

**S-06 Session persistence (Q-5)**
- Confirm the session restores from the keychain after quit and relaunch.
- Inspect the session and crypto-store layout. Decide: keep the Mactrix layout or migrate to current SDK defaults. Record in §11.
- If migration is chosen, do it now. Stores are empty and cheap to reset. Later is expensive.
- Confirm the keychain access entitlement is present and correct.

**S-07 Device verification**
- Run emoji verification from a second device (Element X on iOS or Element Desktop) to this app. Then the reverse direction.
- Confirm cross-signing keys are trusted after completion.
- Confirm key backup restore works so history decrypts.

**S-08 E2EE room decrypts**
- Open a bridged E2EE DM on the dev account. Confirm live messages and back-paginated messages decrypt.
- Record any "unable to decrypt" cases and their cause (missing backup, unverified device, bridge key share).

### Cluster C — Repo hygiene for agentic development

**S-09 `CLAUDE.md` and scripts**
- Write `CLAUDE.md`: build and test commands, architecture map, the "never hand-roll protocol logic" rule, pointer to `docs/ffi/`, pointer to `docs/skills/`, dev vs prod account rule.
- Write `scripts/build.sh`, `scripts/test.sh`, `scripts/lint.sh` that wrap `xcodebuild` with `xcbeautify`. Non-zero exit on failure.
- Output: a fresh Claude Code session can build and test from the instructions alone.

**S-10 Agent skills and FFI reference**
- Run `xcrun agent skills export` for SwiftUI Specialist and What's New in SwiftUI. Commit under `docs/skills/`.
- Copy the generated FFI Swift interfaces from the pinned SDK to `docs/ffi/` as read-only reference. Add `scripts/refresh-ffi-docs.sh` so the copy updates on every SDK bump.
- Output: the agent can read real signatures for the timeline, room list, and session APIs.

**S-11 Formatting, lint, and test scaffolding**
- Add SwiftFormat and SwiftLint with configs. Run them once. Commit the reformat as a single no-logic commit.
- Add swift-snapshot-testing as a test dependency. Add one trivial snapshot test to prove the harness runs headlessly.
- Output: `scripts/test.sh` runs the snapshot test and passes.

### Cluster D — Timeline spike (gate for M1, R-1)

**S-12 Spike harness and synthetic data**
- Build a throwaway target `TimelineSpike` in the workspace. It does not depend on the SDK.
- Generate 10k+ synthetic events: mixed heights (one-line text, multi-paragraph, image placeholders), sender grouping, day separators.
- Add a mutation driver: random edits and reactions that change the height of already laid-out items. Add a back-pagination driver that prepends 50 items on scroll-to-top.
- Add instrumentation: frame time, hitch count, and scroll anchor drift after prepend and after mutation.

**S-13 Candidate A — pure SwiftUI**
- Implement the inverted list with `List` or `ScrollView` + `LazyVStack`, `scrollPosition`, and `defaultScrollAnchor`.
- Run the S-12 harness. Record p95 frame time, hitch count, and anchor drift.

**S-14 Candidate B — AppKit-backed**
- Implement with `NSTableView` (or `NSCollectionView`) in an `NSViewRepresentable`. Variable row heights, prepend without jump, in-place row height updates.
- Run the S-12 harness. Record the same numbers.

**S-15 Decision and record**
- Compare A and B against the budget in Contract §7: no visible hitching at p95, stable anchor on prepend and mutation.
- Write the decision in Contract §11 with the numbers. Delete the losing candidate. Keep the harness for M1 regression use.
- Output: M1 PRD can start.

## 4. Sequencing inside the epic

```
S-01 → S-02 → S-04 ─┐
S-03 (parallel)     ├→ S-05 → S-06 → S-07 → S-08
S-09 → S-10 → S-11 ─┘
S-12 → S-13 → S-14 → S-15   (can start after S-01; does not depend on Cluster B)
```

The spike is independent of the inherited-functionality work. Run Cluster D early and in parallel. Its answer changes everything in M1 and it is the item most likely to slip.

## 5. Out of scope for this epic

- Any replacement of Mactrix chrome. That is M1.
- Any fix to Mactrix features that do not block the exit criteria. Log them as M1 candidates.
- Room list or timeline work beyond the throwaway spike.
- Notifications, search, settings.
- Project name (Q-6, Q-7). Not blocking.

## 6. Risks specific to this epic

| Risk | Signal | Response |
|---|---|---|
| XCFramework macOS slice absent or broken | S-02 fails to link | From-source build path. Budget one extra session. |
| Mactrix does not build on current Xcode at all | S-01 needs many logic changes | Stop. Re-evaluate the fork base vs. a fresh SwiftUI shell over the SDK. Log as an amendment. |
| Neither timeline candidate meets the budget | S-15 shows hitching in both | Prefer AppKit. Reduce item complexity. Record the gap in §11 and carry a perf story into M1. |
| Verification or decryption fails for SDK reasons | S-07 or S-08 blocked | Check the SDK version against Element X's pinned version. Bump the pin before any deep debugging. |

## 7. Definition of done for the epic

All exit criteria in §2 are checked. Contract §11 has dated entries for Q-1 through Q-5 and the timeline decision. A fresh clone builds and tests from `CLAUDE.md` alone.
