---
name: ffi-lookup
description: Safe procedure for looking up matrix-rust-sdk FFI signatures in docs/ffi. Use before writing or verifying any SDK call, and before spawning a subagent whose story touches the FFI.
---

# FFI signature lookup

Hard rule 5 says: never write an SDK call from memory. This skill says how to read the reference without dying.

## The hazard

`docs/ffi/matrix_sdk_ffi.swift` is ~1.7 MB of generated Swift. It is far larger than a subagent context window, and larger than is sane to read in any session. Five subagent runs died from "autocompact is thrashing" on 2026-09-04 by opening it (MATRIX-48/52/55). Reading any `docs/ffi/` file whole is forbidden.

## Lookup procedure

1. Grep, do not read. Search for the declaration:
   - Method: `grep -n "func <name>(" docs/ffi/matrix_sdk_ffi.swift`
   - Type: `grep -n "class <Name>\b\|protocol <Name>\b" docs/ffi/matrix_sdk_ffi.swift`
   - The smaller files (`matrix_sdk.swift`, `matrix_sdk_crypto.swift`, etc.) hold base/crypto types; grep them the same way.
2. Read only the matching region: `sed -n '<start>,<end>p'` or the Read tool with offset/limit, at most ~100 lines. Protocol declarations carry the doc comment; the `open func` implementation confirms async/throws.
3. Record what you verified (signature, file, line) in the story's PR body or resolution comment, so the next session does not repeat the lookup.
4. If the signature is not in `docs/ffi/`, grep the SPM checkout sources under DerivedData the same way. Never guess.

Worked example (MATRIX-48): `grep -n "func stop(" docs/ffi/matrix_sdk_ffi.swift` → line 14573 `func stop() async` on `SyncService` — non-throwing, async. One grep, one 20-line read.

## Spawning subagents on FFI-adjacent stories

Subagents get one further restriction: they never open `docs/ffi/` at all.

- The orchestrator greps the signature first (steps above) and pastes the verified finding into the subagent prompt, marked as verified with file and line.
- The prompt also carries output hygiene: redirect build/test/lint output to a log file and inspect with grep/tail; never Read snapshot reference PNGs; no `git log -p`.
- A dead agent's worktree under `.claude/worktrees/` often holds finished work. Diff it and salvage before relaunching (MATRIX-52's fix shipped that way).
