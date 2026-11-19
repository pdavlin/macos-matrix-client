# Project status

Snapshot of 2026-11-13, main at `d3de850` (PR #129). Plane holds the live
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
- The pinned grid uses the layout of the chat list: the tile avatars start
  at the row avatar edge, with 12 pt between tile contents (MATRIX-150).
- The row timestamps change bucket when the day changes (MATRIX-157).
- Group avatars: a bubble cluster from the room heroes, else from the local
  member list. Colored initials when no picture exists.
- Network badge for bridged rooms. Unread and send-failure dots.
- Joined spaces on the sidebar rail, under the Inbox (MATRIX-167). A
  top-level space with at least one chat is a rail item: its icon, an unread
  mark, and its name as help text. A click filters the chat list to the
  chats of the space, also the chats of its sub-spaces. The rail has one
  selection: the Inbox, one space, or one label. "Browse Rooms…" in the
  item's menu shows the rooms of the space. The Spaces section at the bottom
  of the list is gone.
- The rail's spaces, the workspace icons, the merged-chat member labels and a restored space filter are there in the first frame after a relaunch, from a launch cache of the space data (`SpaceLaunchCache.json` in the session cache folder, MATRIX-170).
- Broadcast to the chats of the rail filter (MATRIX-168). With a label or a
  space selected, "Broadcast…" shows in the chat list's header, and File >
  "Broadcast to <name>…" is enabled. The sheet takes one text message and
  lists every chat of the filter that the account has, each with a checkbox
  (MATRIX-172: from the account's unfiltered room list, so the sidebar's
  page of 100 and the Unread or People filter do not narrow them). One line
  states the source ("All 132 chats of DevObsessed"). If chats are missing,
  the compose and the review steps say how many and why. "Review…" opens
  an explicit second step: "Send to N Chats", and above 20 chats the count
  must be typed. The sends go one chat at a time with a 400 ms pause, through
  the composer's text path (Markdown, and custom emoji per target room). Each
  chat shows waiting, sending, sent, or failed. Stop ends the run after the
  send in flight, and Retry Failed sends again to the failed chats only. A
  merged chat is one target: its default room if the filter shows it, else
  the first member the filter shows. Text only. Nothing is stored. Never for
  the Inbox.
- New chat: start a DM or a group, or join a room.

Timeline

- AppKit `NSTableView` container with pre-measured rows and stable prepend.
- Day separators, sender grouping, sender colors, read receipts, reactions.
- Day dividers compare calendar days ("Today", "Yesterday", then the long
  date) and update when the day changes (MATRIX-157).
- Slack custom emoji draw in message bodies at the line height. The alt text
  shows until the image loads (MATRIX-153). A message of only custom emoji,
  or of custom and Unicode emoji, 1 to 9 in total, draws them at the jumbo
  size (MATRIX-162).
- An `<img>` tag that is not an emoticon shows its alt text only. No `<img>`
  starts a remote request (MATRIX-153).
- A reaction with an `mxc://` key draws as its image in the chip and in the
  hover bar (MATRIX-154).
- Back-pagination. Unable-to-decrypt and error rows.
- Inline images and video, Quick Look, save to Downloads.
- Threads and pins in the inspector (inherited from Mactrix).
- Jumbo emoji: 1 to 9 emoji alone render at 40 pt (MATRIX-137). A custom
  emoji counts as an emoji (MATRIX-162). Mac only.
- A jumped-to message flashes. An accent "New" divider glows, then dims.
  Capsule day dividers with a sticky copy at the top while you scroll
  (MATRIX-136).
- Capsule reaction chips with an own-reaction ring and a press scale. The
  hover action bar fades and slides in. One motion token set with Reduce
  Motion support (MATRIX-135). A chip's tooltip lists who reacted, and
  tooltips show after 400 ms (`NSInitialToolTipDelay`, MATRIX-166).

Composer and message actions

- Enter or Shift-Enter behavior is a setting. Drafts survive relaunch.
- Replies, edits (Up arrow edits the last own message), redaction.
- Reaction picker with SDK recent emoji.
- The reaction picker shows the Slack workspace's custom emoji as a section,
  and the search finds their shortcodes. This needs the bridge's
  `import-image-pack`. An `mxc://` key does not go into the recent list
  (MATRIX-155).
- The custom emoji are read again while the app runs (at most each 5
  minutes per workspace), and "Refresh Custom Emoji" (the pack section's
  header, and the View menu) reads them now. An emoji seen in a message body
  is learned for its workspace and shows in the picker and the composer
  without a new import (MATRIX-161).
- Mentions with atomic chips.
- Media send: file picker, paste, drag and drop, upload progress.
- Forward text and media to another room.
- Whole-message selection in the timestamp column, and transcript copy.
- One action model drives the context menu, the hover row, and the Edit menu.
- Bookmarks (MATRIX-208): "Bookmark" and "Remove Bookmark" in the context
  menu and the Edit menu. A bookmarked row shows a small bookmark before its
  time. Go > Bookmarks (⇧⌘B) lists every bookmark, the newest saved first,
  and a click opens the message and flashes it. The list stores IDs and times
  only, in account data (`io.davlin.matrixclient.bookmarks`).

Mac platform

- File, Edit, View, and Go menus. ⌘K quick switcher. ⌘1 to ⌘9, ⇧⌘] and ⇧⌘[.
- A room in its own window, with window and sidebar-width restoration.
- Settings: Composer and Notifications tabs.
- Local notifications and a Dock badge that counts chats.
- matrix: URLs, user and public-room search (inherited).

Merged chats (M2.5, MATRIX-139)

- Several one-to-one chats with one person show as one chat-list row and
  one timeline. The merges live in account data
  (`io.davlin.matrixclient.merged_chats`).
- Merge, edit, and unmerge from the row menu, the room inspector, and ⌘K.
- One merged timeline with a source note per member room. Each row acts on
  its own room.
- The composer sends to the room with the newest message, with a target
  picker. Notifications and the Dock badge count a merged chat once.
- Member labels show the network and the account, for example
  "Slack • DevObsessed". The account is the name of the room's parent space
  (MATRIX-147).
- The account's icon (the Slack workspace's icon) is the avatar badge in place
  of the network letter: on chat rows, pinned tiles, merged rows (one per
  account, up to three), the composer target chip, source notes, and the quick
  switcher. The letter shows while the icon loads and when there is none
  (MATRIX-148).
- The menu-bar Edit menu acts on the hovered or selected message, in the
  member room that holds it (MATRIX-149).
- The inspector shows the merged chat details: the name, the member chats,
  and "Edit Merged Chat…" (MATRIX-149).
- In a chat of a Slack workspace, an own message shows the user's Slack
  profile image of that workspace, and each row of a merged chat shows the
  image of its own member room's workspace. The app learns the own bridge
  ghost from the bridge info of one direct chat of the workspace, with no
  setup step. Order: the service image, the room member image, the account
  image, initials. Mac only (MATRIX-165).
- By design: Pin, Unpin, and Reply in Thread are off in a merged chat
  (MATRIX-149).
- Drafts are in memory for the session.

Stability fixes of note

- SQLite pools capped and the open-file limit raised (MATRIX-122).
- Objective-C exceptions kept out of the SwiftUI timeline update (MATRIX-130).

Tooling

- `scripts/build.sh` and `scripts/test.sh` keep the build data in
  `build/DerivedData` in the checkout. `DERIVED_DATA_PATH` overrides the
  folder (MATRIX-128).
- CI pins SwiftFormat 0.64.6, the local version, so `scripts/lint.sh` runs
  locally (MATRIX-134).
- `MatrixClient.swift` is split into topic files: Session, Sync,
  Verification, ImageCache, Actions (MATRIX-127).
- The local snapshot suite is stable: new scrollChip references, a retry for
  text-field snapshots (MATRIX-126), and no search spinner in the quick
  switcher snapshot (MATRIX-152).

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
| MATRIX-135, 136, 137, 138, 145 | Smoke the visual flair batch on the running app |
| MATRIX-141, 142, 143, 144 | Smoke merged chats on the running app |
| MATRIX-147, 148, 149 | Smoke the merged-chat member labels and workspace icons on real bridged chats, the Edit menu, and the merged-chat inspector |
| MATRIX-150, 157 | Smoke the pinned grid spacing and the day dividers on the running app |
| MATRIX-153, 154, 155 | Smoke Slack custom emoji in message bodies, reaction chips, and the reaction picker |
| MATRIX-162 | Smoke a Slack message of only custom emoji: it draws large, and the row does not move when the images load |
| MATRIX-165 | Smoke own messages in two Slack workspaces and in a merged chat: each shows the Slack profile image of its workspace. Checks 2 and 3 of `docs/research/own-service-profile.md` say why if it does not |
| MATRIX-167 | Smoke the spaces on the rail: each Slack workspace is an item, a click filters the list, the unread marks agree with the list, the selection is there after a relaunch, and "Browse Rooms…" opens the rooms |
| MATRIX-168 | Smoke the broadcast on the dev account: select a label with 2 scratch chats, see "Broadcast…" in the list header and in the File menu, and see neither for the Inbox. Send one message with Markdown: both chats show it one time. Clear one checkbox: that chat gets nothing. Press Escape while a run is active: the sheet asks before it stops. Then one label with a merged chat: one message, in the expected member room |
| MATRIX-170 | Quit and relaunch two times: the rail shows the spaces at once and they do not go away, the chat rows show their workspace icons at once, and a selected space is still selected with its chats. Then leave a space (dev account): it goes off the rail and is not there after the next relaunch |
| MATRIX-169 | Smoke threads in a Slack chat: open the panel of a root with replies and see the root and each reply; open a second thread and see its rows, not those of the first; reply to a root from the main composer and see the count under the root go up, the reply in the panel, no quoted reply in the main timeline, and a thread reply in Slack; reply from the panel composer; reply to a message with no thread and see a plain quoted reply |
| MATRIX-173 | Smoke the thread reply notice in a scratch chat: turn the network off, reply to a thread root from the main composer with the thread panel closed, and see "Reply to thread not sent" above the composer; Open Thread shows the thread and the line goes away; close the panel, turn the network on, click Retry, and see the line go away and the reply in the thread; do it again and click Discard, and see no reply in the thread |
| MATRIX-172 | Smoke the broadcast target list on the dev account (send nothing): select a space with more chats than the sidebar shows, set the list filter to Unread, open "Broadcast…", and see "All N chats of <name>" with every chat of the space in the list. Cancel the sheet. |
| MATRIX-186 | Launch and quit after about 90 seconds, then launch again: the rail shows the spaces in the first frame both times, also when the spaces come late |
| MATRIX-178 | Smoke music links in a Slack chat: a Spotify track link and an album link show a note glyph and the gradient bar of MATRIX-187, and the row does not move; a click opens song.link in the browser, and from there Apple Music opens the song and the album (this also checks the song.link form for an album); a playlist link has no glyph; right-click shows "Open Original Link" and "Copy Original Link"; Copy Text has the original URL; Settings > Appearance turns the glyph off and on with no clipped row |
| MATRIX-187 | Smoke a Spotify track link in a Slack chat, in light and dark mode: the link text has the color of the message text (not blue) and a violet-to-sky gradient bar in place of the underline, also on each line of a link that wraps; the note glyph is violet; the row does not move; a resize of the window moves the bar with the text; a click on the link text or the glyph opens song.link, the pointer is a hand over it, and a drag from other text still selects |
| MATRIX-151 | Run `import-image-pack <team url>` in the Slack bridge bot's room, one time for each workspace. Say if `custom_emoji_reactions` is true |
| MATRIX-124, 66 | Run `spike/run-gate.sh` on the 120 Hz display (now also covers #99, #103, #112, and the merged timeline #115) |
| MATRIX-125 | Daily-action keyboard checklist and a full day with Beeper closed |
| MATRIX-92 | Apple Developer enrollment, Team ID, keys. Then MATRIX-90, 91 |
| MATRIX-71 | Confirm Slack backfill depth and a send from Mactrix |
| MATRIX-23 | Pick a window for the failover rehearsal |
| MATRIX-25 | E-APP-04 MCP epic, not yet shaped |

### Ready for agents

| Issue | Work |
|---|---|
| MATRIX-156 | Custom emoji in the composer (in progress) |
| MATRIX-158 | Deterministic text-field snapshots (in progress) |
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
- The SwiftUI text-field fault in snapshot tests (MATRIX-120) is hidden by a
  retry, not removed (MATRIX-158).
- Animated custom emoji draw as a still image. A long emoticon alt text is
  cut to fit the square while the image loads.

### Not started

- M3: local FTS5 index, in-room and global search, media browser.
- M4: share extension, App Intents, app icon, invites. Custom emoji moved
  into scope on 2026-11-13 (contract §11); pack management stays deferred.
- Deferred flair (contract §11, 2026-11-09): bubble setting, single-hue
  theme, sounds, send animation, typing bubble, send-state styling.
- Epics MATRIX-36 (design system, first flair batch in Review), 37 (broadcast composer),
  38 (native integration and on-device models).
