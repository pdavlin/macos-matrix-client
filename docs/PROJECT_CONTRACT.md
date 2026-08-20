# Project Contract — Native macOS Matrix Client

| | |
|---|---|
| **Working name** | TBD (repo placeholder: `matrix-mac-client`) |
| **Base codebase** | Fork of [Mactrix](https://github.com/viktorstrate/mactrix) (SwiftUI + matrix-rust-sdk) |
| **Owner** | Patrick |
| **Status** | Draft v0.1 — 2026-08-19 |
| **Purpose of this doc** | Source of truth for scope and sequencing. PRDs are derived from milestones; epics from feature clusters; stories/tasks from epics. Changes to scope require an amendment logged in §11. |

---

## 1. Vision

A genuinely native, "Mac-assed" Matrix client for a single power user running a self-hosted homeserver with mautrix bridges. All messaging — bridged WhatsApp, Signal, Discord, etc. and native Matrix — in one fast, low-footprint AppKit-feeling app with a compliant Liquid Glass navigation layer, real menus, real keyboard support, and best-in-class local search. Not a general-audience product, not cross-platform, not a Beeper competitor. The measure of success: Beeper and Element Desktop can be uninstalled.

## 2. Guiding principles

1. **Don't implement Matrix.** matrix-rust-sdk owns sync, E2EE, crypto store, verification, timeline state. The app is a SwiftUI/AppKit shell over the FFI bindings. Any temptation to hand-roll protocol logic is a design smell.
2. **Glass on the navigation layer only.** Per Apple HIG: toolbar, sidebar, sheets, popovers get Liquid Glass (mostly automatic when built with the current SDK). The message timeline is opaque content. Never `.glassEffect()` on scrollable content.
3. **Mac-assed over feature-complete.** A smaller feature set that fully supports menus, shortcuts, drag-and-drop, context menus, multiple windows, and state restoration beats a bigger one that doesn't. Platform conventions are requirements, not polish.
4. **Personal scale.** Optimize for one account, one user, hundreds of (mostly bridged DM) rooms. No design work for org-scale spaces, moderation tooling, or thousands of public rooms.
5. **Hard fork.** Mactrix is a starting point, not an upstream. No obligation to stay mergeable. Its chrome is replaced wholesale; its SDK wiring, session storage, and verification flow are inherited and refactored in place.
6. **Scope discipline is the survival mechanism.** Single maintainer + agentic coding. Deferred means deferred; §11 amendments are the only path back in.

## 3. Scope

### In scope (v1 = M0–M3)
Login/SSO against own homeserver, device verification, E2EE, room list, full read/write timeline (text, replies, edits, reactions, redactions, media), local notifications, Mac platform integration (menus, shortcuts, windows, drag-and-drop, Quick Look), local full-text message search.

### Deferred (post-v1, requires amendment to schedule)
- Voice/video calls (Element Call / VoIP) — largest single scope item; explicitly held back
- Threads (beyond rendering a "thread exists" affordance)
- Spaces (bridge-network grouping may substitute; see Q-6)
- Multi-account
- Widgets, location sharing, polls (render-only fallback acceptable)
- Custom sticker/emoji *management* (rendering incoming ones is M4)
- Public distribution: notarization, auto-update (Sparkle), website
- iOS/iPadOS ports of any kind

### Out of scope (never, absent a new contract)
Account registration flows, homeserver administration UI, bridge management UI (bridges are managed server-side via their own tooling), Windows/Linux, non-Matrix protocols in-app.

## 4. Feature roadmap

### M0 — Foundation: fork, build, inherit
- Fork Mactrix; building and running in current Xcode on Apple Silicon
- Pin `matrix-rust-components-swift` to a known-good version; confirm the shipped XCFramework includes a macOS slice, else stand up the from-source build (Rust toolchain, `aarch64-apple-darwin`) — see R-3
- Inherited-and-working: login, session persistence (keychain), device verification (emoji), room decryption
- Repo hygiene for agentic dev: `CLAUDE.md`, exported Xcode SwiftUI agent skills (`xcrun agent skills export`), vendored copies of the generated FFI Swift interfaces so the agent can read real signatures, SwiftFormat + SwiftLint, `xcodebuild` build/test scripts
- **Timeline spike (gate for M1):** throwaway prototype of the inverted, variable-height, back-paginating timeline at 10k+ events with edits/reactions mutating laid-out items. Decide pure-SwiftUI vs AppKit-backed (`NSTableView`/`NSCollectionView` via `NSViewRepresentable`) before building the real one.
- Exit criteria: clean build from `git clone` + documented steps; logs into own homeserver; decrypts an E2EE room; timeline architecture decision recorded in §11.

### M1 — Core messaging (daily-driver read path)
- Replace Mactrix chrome: `NavigationSplitView`, glass toolbar/sidebar via standard components, opaque content layer
- Room list: recency sort, unread badges, DM/room distinction, bridge-aware avatars and display names, mute state
- Timeline v1 (per M0 decision): render text/media/state events, day separators, sender grouping, back-pagination, read markers, typing indicators
- Compose v1: plain text send, replies
- Media: inline image/video thumbnails, Quick Look on click, save-to-Downloads
- Notifications: local (in-process sync loop → `UNUserNotificationCenter`), dock badge, per-room mute respected. No APNs, no push gateway — the app is expected to be running.
- Exit criteria: a full day of bridged DM traffic handled without opening Beeper/Element; no timeline scroll hitches at p95.

### M2 — Full send path + Mac platform integration
- Edits, reactions (picker + frequent-emoji row), redactions, message forwarding
- Media send: file picker, paste, drag-and-drop into composer; upload progress
- Markdown composer with mentions autocomplete; multiline behavior (Enter/Shift-Enter) configurable
- Menu bar: real File/Edit/View/Go menus; Cmd-K quick-open room switcher; standard shortcuts (Cmd-F reserved for M3, Cmd-1..9 room pinning, Cmd-Shift-] room cycling)
- Context menus on every message and room; text selection across messages
- Multiple windows (room-in-new-window) + state restoration; sidebar width and window frames persisted
- Settings window (appearance, notifications, composer behavior) as a proper macOS Settings scene
- Exit criteria: everything currently done daily in Beeper — minus calls — has a keyboard-reachable equivalent.

### M3 — Search & archive (the differentiator)
Rationale: Element X still ships without in-room search; for a bridges-as-archive setup, search is the killer feature.
- Local message index: SQLite FTS5 populated from the SDK's event cache/timeline stream; index survives restarts; backfill job for history
- In-room search (Cmd-F) with jump-to-context in timeline
- Global search (Cmd-Shift-F) across all rooms, filterable by sender/room/date/has-media
- Per-room media browser grid
- Exit criteria: any remembered message from any bridged network found in under a second; index size and privacy posture documented (index is plaintext-at-rest — see R-6).

### M4 — Refinement (grab-bag, individually optional)
- Custom emoji/sticker rendering (MSC2545-style packs incoming)
- Read-only thread view
- Share extension (share into a room from Finder/Safari)
- App Intents / Shortcuts (send message, set status)
- Icon Composer app icon; LG2 design-token pass
- Room creation/invite management (minimal)
- Multi-account (test vs. prod accounts) if separate build configs prove annoying

## 5. Implementation order

Strictly sequential by milestone; within a milestone, order is decided at PRD time. Rationale for the sequence:

1. **M0 before anything** — the timeline spike is the single largest technical risk and must be retired before UI investment; FFI build viability gates the whole project.
2. **M1 read-path before M2 send-path** — value arrives earliest via reading; the send path builds on timeline primitives.
3. **M2 before M3** — search UX (jump-to-result) depends on a mature timeline that can open at an arbitrary event.
4. **M3 before M4** — the differentiator ships before comforts.

Cross-cutting, continuous (not milestone-gated): crash-free operation, memory/energy budget adherence (§7), decision log upkeep, SDK version pinning and a monthly upgrade window (R-2).

Suggested cadence for decomposition: **one milestone = one PRD**; epics = the bullet clusters above; stories sized to a single Claude Code session (≤ half a day) with build + tests green as the definition of done.

## 6. Environment & installation requirements

### Development machine
- Apple Silicon Mac; macOS 26 (Tahoe) minimum, macOS 27 beta if adopting LG2 tokens immediately (Q-3)
- Xcode 27 (beta channel until GM) — required for current Liquid Glass appearance and agent skills
- Free Apple ID sufficient: local/ad-hoc signing, no APNs, no Developer Program membership until public distribution (deferred)
- Keychain access entitlement for session storage (inherited from Mactrix's setup — verify in M0)

### Toolchain
- Swift Package Manager only (no CocoaPods/Carthage)
- `matrix-rust-components-swift` pinned by exact version in `Package.resolved`
- Rust toolchain via `rustup` **only if** R-3 forces from-source XCFramework builds: `aarch64-apple-darwin` target, `uniffi-bindgen` per matrix-rust-sdk's pinned version
- SwiftFormat, SwiftLint, xcbeautify
- swift-snapshot-testing for timeline rendering regression tests

### Agentic-dev setup (Claude Code)
- `CLAUDE.md` at repo root: build/test commands, architecture map, "never hand-roll protocol logic" rule, pointer to vendored FFI interfaces
- `xcrun agent skills export` output committed under `docs/skills/` (SwiftUI Specialist + What's New in SwiftUI) — Liquid Glass and 27-era APIs are undertrained; this is the hallucination guard
- Vendored generated FFI Swift sources under `docs/ffi/` (read-only reference copies), refreshed on every SDK bump
- Build validation loop the agent can run headlessly: `xcodebuild build test` scripts; snapshot tests as the agent's eyes on the timeline

### Server (homelab) — prerequisites, not project deliverables
- Synapse, recent stable (Simplified Sliding Sync / MSC4186 is required by matrix-rust-sdk and is native in modern Synapse — no sliding-sync proxy)
- PostgreSQL backing Synapse
- Federation optional but recommended; `.well-known` delegation for the chosen server name; reverse proxy with valid TLS
- mautrix bridges deployed as appservices (compose-managed), with end-to-bridge encryption and double-puppeting as desired
- Two accounts recommended: `@patrick:…` (prod) and `@dev:…` (test) so agent-driven runs never touch real DMs
- No TURN/coturn (calls deferred), no Sygnal/push gateway (no APNs)

## 7. Non-functional requirements

| Dimension | Budget / requirement |
|---|---|
| Idle memory | < 300 MB with full account synced (vs. ~1 GB+ Electron baseline) |
| Cold start to interactive room list | < 2 s on Apple Silicon |
| Timeline scroll | no visible hitching at p95; snapshot-tested layouts |
| Energy | negligible CPU at idle; sync loop must not prevent Mac sleep policy from applying |
| Offline | room list + cached timelines readable offline; queued sends on reconnect |
| Data at rest | crypto store per SDK defaults; search index encryption posture documented (R-6) |
| Accessibility | full keyboard operability (falls out of Mac-assed requirement); VoiceOver labels on timeline items; respect Reduce Transparency (glass degrades gracefully) |
| macOS target | min macOS 26; primary dev/test on latest |

## 8. Risks & mitigations

| ID | Risk | Mitigation |
|---|---|---|
| R-1 | SwiftUI timeline can't hit scroll/anchoring targets (the classic hobby-client killer) | M0 spike gates the decision; AppKit-backed fallback (`NSTableView`/`NSCollectionView` in `NSViewRepresentable`) is a planned branch, not an emergency |
| R-2 | matrix-rust-sdk / FFI API churn; thin docs; undertrained in models | Pin exact versions; monthly upgrade window with dedicated story; vendored FFI sources keep the agent honest; changelog review is part of every bump |
| R-3 | macOS is second-class in `matrix-rust-components-swift`; XCFramework may lack a usable macOS slice at some version | Verify in M0 before any UI work; maintain a documented from-source build path as insurance |
| R-4 | Liquid Glass churn (LG2 token updates, contrast/accessibility revisions) | Glass restricted to standard components on the nav layer → appearance updates arrive via SDK rebuild, not code |
| R-5 | Licensing: Mactrix's license and the dual-licensing of Element-published components could constrain a future public release | Q-1/Q-2 resolved during M0, before significant divergence; private personal use is safe in the interim |
| R-6 | M3 search index is plaintext-at-rest, weakening E2EE guarantees on disk | Document explicitly; FileVault assumed; evaluate SQLCipher or index-level encryption as an M3 story; index exclusion list for sensitive rooms |
| R-7 | Single-maintainer burnout / scope creep | §11 amendment process; milestone exit criteria are binary; M4 items individually droppable |
| R-8 | Agentic dev can't see the UI; visual regressions slip through | Snapshot tests as CI gate; human review reserved specifically for scroll feel and glass rendering |

## 9. Open questions (resolve by end of M0 unless noted)

- **Q-1:** Mactrix license — confirm terms permit fork + modification; record obligations.
- **Q-2:** `matrix-rust-components-swift` licensing/dual-licensing status at the pinned version — implications only if the app is ever distributed (deferred, but check before divergence makes unwinding costly).
- **Q-3:** Minimum deployment target: macOS 26 (stable, LG1) vs. macOS 27 (beta now, LG2, GM ~Sept 2026). Leaning 26-min/27-primary.
- **Q-4:** XCFramework macOS slice present at pinned version? (Feeds R-3.)
- **Q-5:** Keep Mactrix's session/crypto-store layout or migrate to current SDK defaults during M0 refactor?
- **Q-6:** Bridge-network grouping in the sidebar (WhatsApp/Signal/Discord sections) as a v1 substitute for Spaces — cheap win or premature structure? Decide at M1 PRD time.
- **Q-7:** Project name. (Blocking nothing; blocking everything.)
- **Q-8:** Target homeserver vs. the existing Beeper self-host hybrid on `sectional-cache.exe.xyz` (local `bbctl` bridges for Slack/Google Chat/GroupMe against Beeper's hosted homeserver, account `@pdav:beeper.com`). The contract assumes self-hosted Synapse + mautrix. Options: Beeper setup stays interim while homelab Synapse is stood up; the client targets `beeper.com` (breaks the dev-account rule, unverified MSC4186 support); or the Beeper bridges become a migration source. **Resolve before S-05.**

## 10. Working agreements

- This contract is the only source of scope truth. PRDs cite milestone IDs; epics cite roadmap bullets; stories cite epics.
- Definition of done for any story: builds clean, tests (incl. snapshots) pass, manual smoke on the dev account, no new SwiftLint violations.
- The prod account is never used for automated/agent-driven testing.
- Every architectural decision (timeline approach, index schema, store migrations) gets a dated entry in §11.
- Deferred items enter scope only via a logged amendment with an explicit trade (what moves out or which milestone absorbs the cost).

## 11. Decision log & amendments

| Date | Decision |
|---|---|
| 2026-08-19 | Contract drafted. Fork Mactrix as base; hard-fork stance; calls and threads deferred; search designated the v1 differentiator (M3). |
| 2026-08-19 | Q-8 opened: existing Beeper self-host bridges on sectional-cache.exe.xyz vs. the assumed homelab Synapse target. Undecided; resolve before S-05. |
| 2026-08-19 | Q-1 resolved: Mactrix is GPL-3.0-only. Fork and private modification are unrestricted; public distribution would require conveying the fork under GPL-3.0, providing complete source, and avoiding distribution channels (e.g. the Mac App Store) whose terms conflict with GPLv3. See THIRD_PARTY_NOTICES.md. |
| 2026-08-19 | Q-2 resolved: matrix-rust-components-swift and matrix-rust-sdk are both Apache-2.0 with no AGPL history; the 2023-2024 Element AGPL dual-licensing applies to Synapse and Element X client apps, not to matrix-rust-sdk. Apache-2.0 is compatible with GPLv3 combination. Mactrix pins matrix-rust-components-swift to `branch = main` rather than a fixed version; establishing an exact pin remains an open task, separate from this licensing verdict. See THIRD_PARTY_NOTICES.md. |
| 2026-08-19 | Q-4 resolved: matrix-rust-components-swift pinned to exact version 26.04.01 (revision 2916f3f9cc2aea86ba3a820cb6a8389e13e0284a, the same commit previously tracked via `branch = main`, so no functional change). The macOS slice is present in the resolved XCFramework (`LibraryIdentifier` `macos-arm64_x86_64`; the static lib carries both `arm64` and `x86_64` per `lipo -info`) and the app links and builds clean against it. The from-source build path for `aarch64-apple-darwin`, as insurance against a future pinned version dropping the macOS slice, is documented in `scripts/build-ffi-notes.md`. |
| 2026-08-19 | Q-3 resolved: minimum deployment target is macOS 26.0; primary dev and test run on macOS 27 beta with Xcode 27. Rationale: the current-SDK Liquid Glass appearance the contract requires needs the current SDK, and the pinned matrix-rust-sdk binary itself already targets macOS 26.2. |
| 2026-08-20 | S-15 timeline decision: the timeline is **AppKit-backed** — `NSTableView` wrapped in `NSViewRepresentable`, pre-measured row heights, measured-delta prepend compensation (per the S-14 spike candidate). Measured on the S-12 harness, 10k events, identical workload fingerprint, 120 Hz: prepend ×20 anchoring AppKit 20/20 samples at 0.0pt worst vs SwiftUI 18/20 at 0.3pt; mutation-storm-while-scrolling worst drift AppKit 815pt vs SwiftUI 4238pt; frame p95 at or under 8.5ms for both outside storm conditions. SwiftUI's below-viewport anchor gap is structural (`defaultScrollAnchor` covers only one edge); the losing candidate is deleted, the harness and both candidates' dumps are kept under `spike/results/` for M1 regression use. R-1 retired. |
| 2026-08-20 | Q-8 hosting resolved: Synapse runs on a dedicated exe.dev VM (primary) with davbuntu as cold-standby failover and permanent-migration target; hot failover ruled out (single-writer homeserver, E2EE one-time-key hazard). Migration plan in `docs/SYNAPSE-MIGRATION-PLAN.md`, copies on both hosts. Beeper hybrid on sectional-cache stays interim. STILL OPEN before account creation: the server name (davlin.io + .well-known delegation) — the one permanent choice. |
