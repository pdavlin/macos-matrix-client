# Checks for Patrick

Last update: 2026-11-18, after the second guided smoke test run. The orchestrator
keeps this list. Each item is a check on the running app or a decision that
only Patrick can make. Tick an item in Plane (the issue is in Review,
assigned to Patrick) or tell the orchestrator the result.

The app runs from `build/DerivedData/Build/Products/Debug/Mactrix.app`.

Passed on 2026-11-17 and moved to Done: MATRIX-135 to 138, 141 to 145, 147
to 151, 153 to 157, 159, 161, 162, 166, 168 to 170, 172, 175, 178.

Passed on 2026-11-17 to 2026-11-19 and moved to Done: MATRIX-183, 185 to 199.

## 1. Checks that wait for a convenient time

- [ ] **Thread reply notice (MATRIX-173).** Close the thread panel. Turn off
  Wi-Fi. Reply to a thread root from the main composer. After about 30
  seconds a notice above the composer says "Reply to thread not sent", with
  Retry, Open Thread and Discard. Turn on Wi-Fi and click Retry: the reply
  goes into the thread and the notice goes away.
- [ ] **Low priority badges (MATRIX-180, 184).** An unread low priority chat
  in a space adds nothing to the space badge on the rail or to the Dock
  badge. Remove the tag: both badges count it at once.
- [ ] **Offline launch (MATRIX-171).** Start the app with no network, wait 70
  seconds, quit, start again with the network on. The spaces show at once on
  both launches. MATRIX-186 is on main, so this check can occur now.

## 2. Checks after the next build

None.

## 3. Questions

- [ ] **Plane API key.** Rotate it, because it showed in a session
  transcript on 2026-11-17. Put the new value in
  `.claude/settings.local.json`.

## 4. Decisions

Each has a shipped default. Answer only where you want a change.

- [ ] **Thread replies in the main column.** A reply into a thread does not
  show as a row in the main column; the count under the root goes up. Keep
  this, or show thread replies in the main column for everyone?
- [ ] **Pin in a merged chat (MATRIX-149).** Pin is off there. Turn it on?
- [ ] **Emoji alt text (MATRIX-153).** While an image loads or after a failed
  load, a long name is cut to fit the image's square (`:pa…`). Keep this, or
  show the full name at the cost of a row that changes height?
- [ ] **Read-path exception.** The app makes two kinds of read-only request
  outside the SDK: room state (the emoji list; one DM per workspace for
  your Slack image), and the homeserver URL preview of a Spotify link (the
  music link titles, MATRIX-191). Keep them, or schedule the SDK bump that
  removes them?
- [ ] **Broadcast rules (MATRIX-168).** One chat at a time; a merged chat
  gets one message; the count typed above 20 chats; Stop has no resume; no
  history. Images are MATRIX-177 (Backlog). Change any of these?
- [ ] **Space rail (MATRIX-167).** One selection at a time (Inbox, a space,
  or a label); a second click does not clear a filter; ⌃1 to ⌃9 count the
  spaces before the labels. Change any of these?
- [ ] **Low priority notifications.** Low priority chats no longer count in
  the rail and Dock badges. Must they also give no system notification?

## 5. Only Patrick can do these

- [ ] **MATRIX-160.** File a Feedback with Apple for the SwiftUI text field
  height fault (the reproducer is
  `MactrixLibrary/Tests/UITests/TextFieldLineHeightTests.swift`). Say if a
  search field or the composer shows text that sits slightly off.
- [ ] **MATRIX-124, 66, 181.** Run `spike/run-gate.sh` on the 120 Hz display,
  on a quiet machine (no VM, no builds).
- [ ] **MATRIX-125.** Daily-action keyboard checklist and a full day with
  Beeper closed.
- [ ] **MATRIX-92.** Apple Developer enrollment, Team ID, keys.
- [ ] **MATRIX-72, 73, 74.** Bridge work on the server needs SSH with Touch
  ID: Google Chat and GroupMe bridges, then the Beeper cutover.
- [ ] **MATRIX-71, 23, 130.** Slack backfill depth; a window for the
  failover rehearsal; one day of use with no crash in the sidebar.
