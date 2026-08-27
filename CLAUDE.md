# CLAUDE.md — Native macOS Matrix Client

Single-user, Mac-native Matrix client. Hard fork of Mactrix (SwiftUI + matrix-rust-sdk). One account, one self-hosted homeserver, mautrix bridges. Success metric: Beeper and Element Desktop get uninstalled.

## Repo state

The Mactrix fork has landed. Current layout:

- `Mactrix/` — the app target: SwiftUI shell, views, models, extensions.
- `MactrixLibrary/` — a local Swift Package Manager package with the `UI`, `Models`, `Utils`, and `MessageFormatting` libraries and their tests.
- `docs/` — `PROJECT_CONTRACT.md` (the source of truth for scope, read it before any planning work) and `docs/epics/E-M0-01-foundation.md` (the active epic).
- `scripts/` — `build.sh`, `test.sh`, `lint.sh`.

## Hard rules

1. **Never hand-roll protocol logic.** matrix-rust-sdk owns sync, E2EE, crypto, verification, timeline state. The app is a SwiftUI/AppKit shell over the FFI bindings. If a change starts to implement Matrix semantics, stop and redesign.
2. **Glass on the navigation layer only.** Toolbar, sidebar, sheets, popovers. Never `.glassEffect()` on scrollable content. The timeline is opaque.
3. **The prod account is never used for automated or agent-driven testing.** Use the dev account only. If credentials are ambiguous, stop and ask.
4. **Scope comes from the contract.** Deferred means deferred. Do not add calls, threads, spaces, or multi-account work without a §11 amendment.
5. **Do not guess FFI signatures.** matrix-rust-sdk bindings are undertrained. Read the vendored copies in `docs/ffi/`. If the signature is not there, read the package sources in `DerivedData`/SPM checkouts. Never write an SDK call from memory.
6. **Pin discipline.** `matrix-rust-components-swift` is pinned by exact version. Do not bump it inside a feature story. SDK bumps are their own story with a changelog review.

## Build and test

```
scripts/build.sh    # xcodebuild build, xcbeautify, non-zero exit on failure
scripts/test.sh     # xcodebuild test incl. snapshot tests
scripts/lint.sh     # SwiftFormat --lint + SwiftLint
```

Each script auto-detects `DEVELOPER_DIR` (existing env value, else Xcode-beta.app, else Xcode.app) unless it is already set.

## Definition of done (every story)

- Builds clean via `scripts/build.sh`.
- Tests pass, including snapshot tests.
- Manual smoke on the dev account where user-visible.
- No new SwiftLint violations.
- Architectural decisions get a dated entry in the contract §11.

## Architecture map **[after S-01]**

- App target: SwiftUI shell, `NavigationSplitView`, standard glass components.
- Timeline: implementation per the S-15 decision (SwiftUI vs `NSViewRepresentable`-wrapped AppKit). Do not build timeline UI before that decision is in §11.
- Session/crypto stores: per the S-06 decision (Q-5).
- Search (M3): SQLite FTS5, local only, plaintext-at-rest documented per R-6.

## Conventions

- Swift Package Manager only. No CocoaPods, no Carthage.
- Strong types. No force-unwraps outside tests.
- SwiftFormat + SwiftLint configs are authoritative once committed (S-11).
- No trailing whitespace, including whitespace-only lines.
- Snapshot tests are the agent's eyes on the timeline. Add or update snapshots with any layout change.

## Reference material

- `docs/ffi/` — vendored generated FFI Swift interfaces for the pinned SDK. Read-only. Refresh via `scripts/refresh-ffi-docs.sh` on every SDK bump.
- `docs/skills/` — exported Xcode agent skills (SwiftUI Specialist, What's New in SwiftUI). Read these before Liquid Glass or macOS 26/27 API work.

## Project Management

Stories live in Plane. Coordinates (base URL, workspace/project UUIDs, state map) are in `.plane.local.md` at the repo root — gitignored, read it first. The API key is the `PLANE_API_KEY` env var (set via `.claude/settings.local.json`); pass it as the `X-API-Key` header. Never print or commit the key.

Workflow (orchestrator-only: in multi-agent sessions, ONLY the main session calls the Plane API; subagents never touch Plane or read its key — they report back and the orchestrator updates the board):
- Stories in Plane are self-contained: the description carries the full story text (all steps, outputs, sequencing, known findings, and the definition of done), not a summary plus a pointer. Update the description when the story's scope or known facts change.
- On starting a story: PATCH the issue to the "In Progress" state AND post a start-of-work comment: who picked it up (which session/agent), the planned approach, and any known blocker.
- On tests green: move to "Review". Never move anything to "Done" — that's Patrick's click.
- Assign an issue to Patrick the moment it needs manual work from him — a terminal action, a hardware or account credential, a physical check, or a decision only he can make. Do not wait to be asked and do not just mention it in chat: put his UUID in `assignees` (see `.plane.local.md`) and say in the comment exactly what is needed from him. Unassign when the blocker clears.
- Every move to "Review" must carry a resolution comment on the issue: what was done, key findings/decisions, output artifacts (files, commits), and anything deferred. Post the comment before or with the state change.
- Contract §11 rows are append-only and WILL conflict between concurrent branches. On a PR conflict in docs/PROJECT_CONTRACT.md, rebase onto main and keep all rows, earliest-merged first. Verify the build after any rebase before force-pushing (--force-with-lease only).
- Stories that change code are done on a branch named `s-XX/short-slug`, not on main. Moving such a story to "Review" requires an open PR against main; put the PR link in the resolution comment AND attach it to the issue via the links API (`POST .../issues/<id>/links/` with `url` and `title`). Docs-only changes may commit straight to main. Never merge a PR — that's Patrick's click, same as "Done". Never put Claude session links in PR bodies or comments.
- States have per-project UUIDs. If the map in `.plane.local.md` is empty, GET `.../projects/<uuid>/states/` once and record it there.
