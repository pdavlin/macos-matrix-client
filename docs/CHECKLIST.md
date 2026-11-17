# Checks for Patrick

Last update: 2026-11-16. The orchestrator keeps this list. Each item is a
check on the running app or a decision that only Patrick can make. Tick an
item in Plane (the issue is in Review, assigned to Patrick) or tell the
orchestrator the result.

The app runs from `build/DerivedData/Build/Products/Debug/Mactrix.app`.

## 1. Check first (new and not yet seen on real data)

- [ ] **Broadcast (MATRIX-168).** Select a small label or space (2 or 3
  chats). Click "Broadcast…" at the top of the chat list. Send a short
  message. Each chat shows waiting, then sent. The message is in each chat
  and in Slack.
- [ ] **Thread panel (MATRIX-169).** Open the thread of a Slack message that
  has replies. The root and the replies show. Reply to the root from the main
  composer: the count goes up, the panel shows the reply, Slack gets a thread
  reply. Open a second thread: it shows its own messages.
- [ ] **Rail at launch (MATRIX-170).** Quit and open the app two times. On
  the second launch the spaces, the workspace icon badges, and a saved space
  filter show at once.
- [ ] **Tooltip delay (MATRIX-166 follow-up).** Rest the pointer on a
  reaction chip. The names show after about 0.4 seconds. Say a number if it
  is still too slow.

## 2. Custom emoji (MATRIX-151)

- [ ] Run `list-logins` in the Slack bridge bot's room. Then run
  `import-image-pack <login id> <team domain>` for the two other workspaces.
- [ ] **Refresh with no restart (MATRIX-161).** After an import, open the
  reaction picker in a chat of that workspace and press the refresh button in
  the emoji section's header. The count shows. If the chat has no emoji
  section, use View > Refresh Custom Emoji.
- [ ] **Picked reaction (MATRIX-155).** React with a custom emoji. It shows
  in Slack as that emoji.
- [ ] **Composer (MATRIX-156).** Type `:` and two letters, pick an emoji,
  send. It shows in Slack as that emoji.
- [ ] **Message body (MATRIX-159).** A Slack message with a custom emoji in
  its text shows the image, not `:name:`.
- [ ] **Jumbo (MATRIX-162).** A Slack message of only custom emoji draws
  them large.
- [ ] **Reaction chip (MATRIX-154).** A custom emoji reaction shows as an
  image.

## 3. Earlier stories still in Review

- [ ] **Merged-chat labels and icons (MATRIX-147, 148).** The Merge Chats
  sheet and the Add Chat picker show "Slack • <workspace>". Chat rows and
  pinned tiles show the workspace icon.
- [ ] **Edit menu in a merged chat (MATRIX-149).** The Edit menu acts on the
  hovered message. The inspector shows the member chats.
- [ ] **Pinned grid (MATRIX-150).** The grid lines up with the list. Say if
  the names under the tiles must be centered. Check the selection highlight
  of a first-column tile.
- [ ] **Day dividers (MATRIX-157).** A timeline with messages from yesterday
  evening and today shows "Yesterday" and "Today".
- [ ] **Visual flair batch (MATRIX-135 to 138, 145).** Hover bar, reaction
  chips, jump flash, "New" divider, jumbo emoji, reaction picker popover.
- [ ] **Merged chats (MATRIX-141 to 144).** Merge, send, reply, react, edit,
  notification click, unmerge.

## 4. Decisions

- [ ] **Thread replies in the main column.** A reply into a thread no longer
  shows as a row in the main column; the count under the root goes up. Keep
  this, or show thread replies in the main column for everyone?
- [ ] **Pin in a merged chat (MATRIX-149).** Pin is off there. Turn it on?
- [ ] **Day divider wording (MATRIX-157).** Today, Yesterday, then a full
  date. Add a weekday name for the last week?
- [ ] **Emoji alt text (MATRIX-153).** While an image loads or after a failed
  load, a long name is cut to fit the image's square (`:pa…`). Keep this, or
  show the full name at the cost of a row that changes height?
- [ ] **Read-path exception.** The app makes one kind of read-only request
  for room state outside the SDK (the emoji list; one DM per workspace for
  your Slack image). Keep it, or schedule the SDK bump that removes it?
- [ ] **Broadcast rules (MATRIX-168).** Text only; one chat at a time; a
  merged chat gets one message; the count typed above 20 chats; Stop has no
  resume; no history. Change any of these?
- [ ] **Space rail (MATRIX-167).** One selection at a time (Inbox, a space,
  or a label); a second click does not clear a filter; ⌃1 to ⌃9 count the
  spaces before the labels. Change any of these?

## 5. Only Patrick can do these

- [ ] **MATRIX-160.** File a Feedback with Apple for the SwiftUI text field
  height fault (the reproducer is
  `MactrixLibrary/Tests/UITests/TextFieldLineHeightTests.swift`). Say if a
  search field or the composer shows text that sits slightly off.
- [ ] **MATRIX-124, 66.** Run `spike/run-gate.sh` on the 120 Hz display.
- [ ] **MATRIX-125.** Daily-action keyboard checklist and a full day with
  Beeper closed.
- [ ] **MATRIX-92.** Apple Developer enrollment, Team ID, keys.
- [ ] **MATRIX-72, 73, 74.** Bridge work on the server needs SSH with Touch
  ID: Google Chat and GroupMe bridges, then the Beeper cutover.
- [ ] **MATRIX-71, 23, 130.** Slack backfill depth; a window for the
  failover rehearsal; one day of use with no crash in the sidebar.

## 6. In work while you are away (2026-11-16)

- MATRIX-171: the space data survives an offline launch; your Slack image
  follows a new Slack login.
- MATRIX-172: broadcast reaches every chat of the filter, not only the first
  100, and says how many.
- MATRIX-173: a failed send into a thread shows above the main composer.
- MATRIX-174: a timeline performance check after the November changes.
