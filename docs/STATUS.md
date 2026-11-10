# Project status

Snapshot of 2026-11-10, main at `135863a` (PR #105). Plane holds the live
state of each story. The contract (`docs/PROJECT_CONTRACT.md`) holds scope and
decisions. Update this file when a milestone or an epic changes state.

## Summary

| Track | State |
|---|---|
| M0 Foundation | Done (MATRIX-1 to 15) |
| M1 Read path | Built and merged. The manual exit day is open (MATRIX-125). The gate bars are not re-derived (MATRIX-66) |
| M2 Send path and Mac integration | All 14 stories merged (#72 to #93). Exit checks open (MATRIX-124, 125) |
| M3 Search and archive | Not started |
| M4 Refinement | Not started. Room creation came forward (MATRIX-75) |
| E-APP-05 iOS port | Code for P1 to P4 merged. Blocked on the Apple Developer Program (MATRIX-92) |
| E-HS-01 Homeserver | davlin.io runs on Synapse on exe.dev. The failover rehearsal is open (MATRIX-23) |
| E-HS-03 Bridges | Slack runs on davlin.io (5 workspaces). Google Chat, GroupMe, and the Beeper cutover are open |

## Mac app: what works

Accounts and security

- Password and SSO sign-in, session restore from the keychain.
- Emoji device verification, recovery setup and use, identity reset.
- Sign-out closes open rooms and stops the client.

Chat list (sidebar)

- Dense rows: 36 pt avatars, one preview line, small secondary time.
- Pinned favourites as tiles, SDK filters, labels with a space-bar filter.
- Group avatars: a bubble cluster from the room heroes, else from the local
  member list. Colored initials when no picture exists.
- Network badge for bridged rooms. Unread and send-failure dots.
- Joined spaces in the sidebar.
- New chat: start a DM or a group, or join a room.

Timeline

- AppKit `NSTableView` container with pre-measured rows and stable prepend.
- Day separators, sender grouping, sender colors, read receipts, reactions.
- Back-pagination. Unable-to-decrypt and error rows.
- Inline images and video, Quick Look, save to Downloads.
- Threads and pins in the inspector (inherited from Mactrix).
- Jumbo emoji: 1 to 9 emoji alone render at 40 pt (MATRIX-137).
- A jumped-to message flashes. An accent "New" divider glows, then dims.
  Capsule day dividers with a sticky copy at the top while you scroll
  (MATRIX-136).
- Capsule reaction chips with an own-reaction ring and a press scale. The
  hover action bar fades and slides in. One motion token set with Reduce
  Motion support (MATRIX-135).

Composer and message actions

- Enter or Shift-Enter behavior is a setting. Drafts survive relaunch.
- Replies, edits (Up arrow edits the last own message), redaction.
- Reaction picker with SDK recent emoji.
- Mentions with atomic chips.
- Media send: file picker, paste, drag and drop, upload progress.
- Forward text and media to another room.
- Whole-message selection in the timestamp column, and transcript copy.
- One action model drives the context menu, the hover row, and the Edit menu.

Mac platform

- File, Edit, View, and Go menus. ⌘K quick switcher. ⌘1 to ⌘9, ⇧⌘] and ⇧⌘[.
- A room in its own window, with window and sidebar-width restoration.
- Settings: Composer and Notifications tabs.
- Local notifications and a Dock badge that counts chats.
- matrix: URLs, user and public-room search (inherited).

Stability fixes of note

- SQLite pools capped and the open-file limit raised (MATRIX-122).
- Objective-C exceptions kept out of the SwiftUI timeline update (MATRIX-130).

## iOS app: what works (simulator and code)

- Sign-in, restore, verification, recovery.
- Room list, iPhone stack and iPad split navigation, settings, invites.
- `UICollectionView` timeline, composer, text send, replies, media view.
- App Group store, shared keychain group, Notification Service Extension,
  pusher registration, cross-process lock.
- No device test has run. Every device check waits on MATRIX-92.

## Incomplete work

### Needs Patrick

| Issue | What is needed |
|---|---|
| MATRIX-130 | One day of use with no SIGBUS in `SidebarRoom.updateRoom` |
| MATRIX-135, 136, 137 | Smoke the visual flair batch on the running app |
| MATRIX-124, 66 | Run `spike/run-gate.sh` on the 120 Hz display (now also covers #99, #103) |
| MATRIX-125 | Daily-action keyboard checklist and a full day with Beeper closed |
| MATRIX-92 | Apple Developer enrollment, Team ID, keys. Then MATRIX-90, 91 |
| MATRIX-71 | Confirm Slack backfill depth and a send from Mactrix |
| MATRIX-23 | Pick a window for the failover rehearsal |
| MATRIX-25 | E-APP-04 MCP epic, not yet shaped |
| MATRIX-134 | Decide the SwiftFormat pin (local 0.64.6, CI 0.64.4) |

### Ready for agents

| Issue | Work |
|---|---|
| MATRIX-126 | scrollChip snapshots fail on this Mac only |
| MATRIX-127 | Split `MatrixClient.swift` (544 lines) |
| MATRIX-128 | Remove stale worktrees (48) and DerivedData folders (89) |
| MATRIX-72, 73, 74 | Google Chat and GroupMe bridges, then the Beeper cutover |

### Watch list (no new evidence)

- MATRIX-62: NSException during window layout (last seen 2026-09-15).
- MATRIX-76: NSHostingView use-after-free in row dealloc (last seen 2026-10-23).
- MATRIX-97: sign-in client has no session delegate. No effect while
  davlin.io has no OIDC provider.

### Known limits

- The member-list fallback reads the local store first, so "+N" can be low
  until the full member list loads.
- The pinned "+N" text can touch the third bubble. Tiny bubbles show
  initials that are hard to read. Both are polish items noted on MATRIX-129,
  not filed.
- Local `scripts/test.sh` stays red on the three scrollChip snapshots
  (MATRIX-126). CI is green.

### Not started

- M3: local FTS5 index, in-room and global search, media browser.
- M4: custom emoji, share extension, App Intents, app icon, invites.
- Deferred flair (contract §11, 2026-11-09): bubble setting, single-hue
  theme, sounds, send animation, typing bubble, send-state styling.
- Epics MATRIX-36 (design system, first flair batch in Review), 37 (broadcast composer),
  38 (native integration and on-device models).
