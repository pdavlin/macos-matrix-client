# E-M2-01 — Full Send Path and Mac Platform Integration (M2 PRD)

| | |
|---|---|
| **Milestone** | M2 — Full send path + Mac platform integration (Contract §4) |
| **Roadmap bullets** | All seven M2 bullets: authoring actions, media send, markdown and mentions, menus and shortcuts, context menus and selection, windows and restoration, Settings |
| **Contract basis** | §4 M2, §5 order, 2026-09-01 M1 PRD (D-1, D-3), 2026-09-02 S-37 and S-38 rows, 2026-10-27 iOS amendment |
| **Status** | Draft 2026-11-04 — decisions D-1…D-8 wait for Patrick. Only story A1 (no open decision) may start before approval. |

## 1. Goal

Make every action Patrick does daily in Beeper, minus calls, possible in this
app and reachable from the keyboard (contract M2 exit criterion). M1 delivered
the read path, plain text send, and replies. M2 adds authoring actions, media
send, mentions, real menus, a quick switcher, context menus, more windows, and
a complete Settings scene.

M2 is Mac-only. The iOS port gets M2 features only through a later §11 row.

## 2. Decided foundations (do not relitigate)

- **Never hand-roll protocol logic.** Every send, edit, redaction, reaction,
  upload, and mention uses an SDK call (verified table in §4).
- **2026-08-20 (S-15):** the timeline is an `NSTableView` with `NSHostingView`
  rows and pre-measured heights. Any selection or menu work stays inside that
  container. It does not replace the container.
- **2026-09-01 D-1, 2026-09-02 S-37:** Enter sends, Shift-Enter makes a new line,
  Cmd-Enter also sends. The rule lives in `Models.ComposerKeyDecision`. M2
  makes the default configurable.
- **2026-09-01 D-3:** edit, reaction, and redaction authoring is M2 scope.
- **2026-09-02 S-38:** a click on a video opens Quick Look, and inline playback
  is in the context menu. New message menus keep these items.
- **Glass rule:** the navigation layer only. Popovers and sheets may use glass.
  Timeline rows stay opaque.
- **Cmd-F is reserved for M3** in-room search.
- **2026-11-04 (Patrick, in session):** M2 starts now, in parallel with the iOS
  port, because the iOS port waits on the Apple Developer Program (MATRIX-92).
  This changes the 2026-10-27 amendment's "iOS phases run before M2". The §11
  row is added when the open contract-touching PRs merge, so the open PRs do
  not conflict again.

## 3. Current state (survey 2026-11-04)

The survey read main plus the open desktop PRs (#54 inbox list, #55
conversation rhythm, #56 new chat, #57 labels, #58 ImageIO) and #60 (Core
extraction).

| Area | Exists | Missing |
|---|---|---|
| Reactions | Pills and toggle (`MessageEventView.swift:239-250`), three fixed hover emoji (`:186-192`), `toggleReaction(itemId:key:)` at `ChatMessageView.swift:29` | Picker (the button at `:195` has an empty action), frequent-emoji row |
| Edits | `UI.EditedMarker`, "(edited)" display; the composer draft ignores `.edit` drafts (`ChatInputView.swift:96`) | Edit mode in the composer, edit send |
| Redactions | Redacted placeholder row | Redact action |
| Forwarding | none | All |
| Media send | Drag-out of received media (`MessageImageView.swift`) | File picker, paste, drop into composer, upload progress |
| Markdown | `messageEventContentFromMarkdown(md:)` at `ChatInputView.swift:21` | none for basic markdown |
| Mentions | `UserProfileActions.mentionUser()` declared, not implemented | Autocomplete, `Mentions` on sent content |
| Enter setting | `ComposerKeyDecision` with the M2 seam in its doc comment | The setting and its UI |
| Menus | `Commands.swift`: sidebar, inspector, text editing, toolbar, ⌘T tab, font size; #56 adds ⌘N New Chat, ⇧⌘N group, ⌥⌘N New Window | Go menu, ⌘K, ⌘1…9, ⇧⌘] and ⇧⌘[, Edit-menu message actions |
| Room menus | Mark unread, favourite, permalink, leave (`RoomContextMenu.swift`); #57 adds low priority and labels | none for M2 |
| Message menus | Media rows only (Quick Look, Save to Downloads) | Text message menus, all authoring actions |
| Selection | Inside one message only; the table blocks row selection (`TimelineTableView.swift:106`, `:374-380`) | Selection across messages |
| Windows | `WindowGroup(id: "main")`, `@SceneStorage` window state (room, inspector, sections), ⌘T tabs | Room in a new window, sidebar width, verified frame autosave |
| Settings | `Settings` scene with Account, Appearance (font size only), Sessions | Composer and Notifications tabs |

**File moves in #60:** `LiveTimeline`, `WindowState`, and `Notifications` move
to `MactrixLibrary/Sources/Core`. The composer, the timeline container,
`Commands.swift`, and Settings stay in `Mactrix/`.

**Merge hazards:** #55 edits `ChatMessageView` and `MessageEventView`. #56
edits `Commands.swift` and `WindowState`. #57 edits `WindowState`,
`RoomContextMenu`, and `SidebarView`. #60 moves `WindowState` and changes
`AttributedTextView`.

## 4. Verified FFI (pinned 26.04.01, `docs/ffi/matrix_sdk_ffi.swift`)

| Symbol | Line |
|---|---|
| `Timeline.edit(eventOrTransactionId:newContent: EditedContent) async throws` | 15467 |
| `EditedContent` (`.roomMessage`, `.mediaCaption`, `.pollStart`) | 27808 |
| `Timeline.redactEvent(eventOrTransactionId:reason:) async throws` | 15553 |
| `Timeline.toggleReaction(itemId:key:) async throws -> Bool` | 15608 |
| `Client.addRecentEmoji(emoji:) async throws` | 1448 |
| `Client.getRecentEmojis() async throws -> [RecentEmoji]` | 1454 |
| `Timeline.send(msg:) async throws -> SendHandle` | 15564 |
| `Timeline.sendFile/sendImage/sendVideo/sendAudio(params: UploadParameters, …) throws -> SendAttachmentJoinHandle` | 15568 / 15570 / 15587 / 15566 |
| `Timeline.sendGallery(params:itemInfos:) throws -> SendGalleryJoinHandle` | 15619 |
| `UploadParameters` (`source`, `caption`, `formattedCaption`, `mentions`, `inReplyTo`, …) | 25400 |
| `UploadSource` | 39986 |
| `SendAttachmentJoinHandle.cancel()` / `join() async throws` | 12259 |
| `EventSendState.notSentYet(progress: MediaUploadProgress?)` | 29013 |
| `MediaUploadProgress` (`index`, `progress: AbstractProgress`) | 20019 |
| `RoomMessageEventContentWithoutRelation.withMentions(mentions:)` | 11389 |
| `Mentions` (`userIds`, `room`) | 20091 |
| `messageEventContentFromMarkdown(md:)` | 50146 |

Not in the FFI: a forward call. See D-4.

Upload progress arrives on the local echo's send state, not on the join
handle. The progress view therefore belongs in the timeline row, not in the
composer.

## 5. Decisions — open (Patrick)

**D-1 — Story order under the merge queue.**
Recommendation: Cluster A (composer and media) starts now from main, because
#60 does not move its files. Clusters B and C start only after #60 and the
desktop PRs (#54–#57) merge. The other path stacks M2 branches on #60. That
path works, but every new PR then waits on 13 unmerged iOS PRs.

**D-2 — Selection across messages.**
Native text selection across `NSHostingView` rows is not possible with the S-15
container.
- (a) Recommended: message-range selection. Click and Shift-click select whole
  rows, and ⌘C copies a plain-text transcript ("Sender, time: body" per line).
  Character selection inside one message stays as it is.
- (b) A custom selection layer over the table. It is large, and it puts the
  S-15 anchor and height guarantees at risk.
- (c) Drop it from M2.

**D-3 — Reaction picker.**
- (a) Recommended: a popover with the SDK recent-emoji row
  (`getRecentEmojis`), a search field, and a bundled emoji list with Unicode
  CLDR names. Each reaction calls `addRecentEmoji`.
- (b) The system Character Viewer. It inserts into a text field, and a reaction
  has no text field, so it needs a hidden field. This is not reliable.

**D-4 — Forwarding.**
The SDK has no forward call, and building event content from another event is
protocol logic.
- (a) Recommended: forward text by sending the body again with
  `messageEventContentFromMarkdown`. Forward media by downloading it through the
  SDK media call and uploading it again with `sendImage`/`sendFile`. This costs
  bandwidth, but every byte goes through SDK calls.
- (b) Forward text only in M2.

**D-5 — Enter setting.**
Recommendation: Settings > Composer has "Enter sends (Shift-Enter for a new
line)", the default, and "⌘Enter sends (Enter for a new line)". The value goes
into `ComposerKeyDecision`, and its unit tests cover both modes.

**D-6 — Mentions.**
Recommendation: type "@" to get autocomplete over room members, with the SDK
member list as the source. The composer inserts a `matrix.to` pill link in the
markdown and sets `Mentions.userIds`. The bridges convert pills to native
mentions. `@room` is out of M2.

**D-7 — Quick switcher (⌘K).**
Recommendation: a sheet with fuzzy match over the room list (name and alias),
recent rooms first, and Return to open. ⌘1…9 open the first nine pinned
favourites from #57. ⇧⌘] and ⇧⌘[ cycle through the visible chat list.

**D-8 — More windows.**
Recommendation: "Open in New Window" on the room context menu and ⌥-Return in
the quick switcher, through `WindowGroup(for:)` with the room id. Each window
restores its room through `@SceneStorage`. The app persists sidebar width and
frames.

## 6. Stories

### Cluster A — Composer and media (start now, no #60 conflict)

All Cluster A stories touch `ChatTextView` or `ChatInputView`, so they run one
after another, not in parallel.

- **A1 — Enter behavior setting and the Settings Composer tab.**
  `ComposerKeyDecision` gets the mode, Settings gets a Composer tab, and unit
  plus snapshot tests cover both. No open decision (D-5 is the contract default
  plus one option).
- **A2 — Media send: file picker, paste, drop into the composer.** Composer
  attachment chips, `sendImage`/`sendVideo`/`sendFile` with `UploadParameters`
  (caption, `inReplyTo`), `sendGallery` for more than one item, and cancel
  through the join handle. Waits on #58 (ImageIO decode in `Data+Mime.swift`).
- **A3 — Upload progress in the timeline row.** Read
  `EventSendState.notSentYet(progress:)` on the local echo and show a
  determinate progress view in media rows. Fingerprint the progress as
  height-neutral (MATRIX-63) so progress ticks do not re-measure rows.
- **A4 — Mentions autocomplete.** D-6.

### Cluster B — Message actions (after #55 and #60 merge)

- **B1 — Message context menu and Edit-menu actions.** One menu model drives
  the right-click menu, the hover row, and the Edit menu. Keep the S-38 video
  items.
- **B2 — Edit authoring.** Up-arrow in an empty composer edits the last own
  message. The composer shows edit mode and Esc cancels it. Send calls
  `edit(eventOrTransactionId:newContent:)`.
- **B3 — Redaction.** Confirm with an optional reason, then
  `redactEvent(eventOrTransactionId:reason:)`.
- **B4 — Reaction picker and recent emoji.** D-3.
- **B5 — Forwarding.** D-4. The quick switcher from C1 picks the target room.
- **B6 — Message-range selection and copy.** D-2.

### Cluster C — Menus, switcher, windows (after #56, #57, and #60 merge)

- **C1 — ⌘K quick switcher.** D-7.
- **C2 — Go menu, ⌘1…9, ⇧⌘] and ⇧⌘[.** D-7.
- **C3 — Room in a new window, restoration, sidebar width.** D-8.

### Cluster D — Settings completion

- **D1 — Settings Notifications tab.** Global notification on/off, sound, and
  dock badge. Per-room mute stays where it is. Starts after #60, because
  `Notifications` moves to Core.

## 7. Sequencing

1. A1 now. Then A4, A2 (after #58), and A3, one at a time.
2. B1 first in Cluster B, because B2–B6 add items to its menu model.
3. C1 before B5, because forwarding uses the switcher to pick the room.
4. D1 any time after #60.
5. The §11 row for this PRD lands when #54–#56 merge, so it does not make a
   new contract conflict on them.

## 8. Exit criteria (binary)

- Each daily Beeper action on the checklist below has a keyboard path, and
  Patrick confirms each one on the dev account: send text, reply, edit last
  message, react, redact, forward, send an image, paste a screenshot, mention,
  switch room by name, open a room in a new window, mark unread.
- A full day of bridged traffic handled in this app with Beeper closed and no
  Beeper desktop use for any of those actions.
- The timeline gate (MATRIX-87 methodology, Mac) shows no regression after
  Clusters A3 and B1.

## 9. Out of scope

- M3: search, ⌘F, the media browser.
- Thread authoring (M4 lists a read-only thread view).
- `@room` mentions, polls, voice messages, stickers.
- Any iOS change.

## 10. Risks

| Risk | Mitigation |
|---|---|
| The merge queue (19 open PRs) makes every M2 PR conflict | D-1: Cluster A only until the base merges |
| Contract §11 rows conflict on every merge | Add the M2 §11 row after #54–#56 merge |
| Upload progress ticks re-measure rows | A3 marks progress as height-neutral (MATRIX-63) |
| Media forward re-upload doubles bandwidth for large files | Show the size before forward. Revisit if the SDK adds a forward call |
| The emoji dataset grows the bundle | CLDR annotations for one locale only, measured in the A/B story PR |

## 11. Definition of done for this epic

Every story meets the project definition of done: `scripts/build.sh` clean,
`scripts/test.sh` green with snapshots, a manual smoke on the dev account, no
new SwiftLint violations, and a §11 row for each architectural decision. The
epic is done when the §8 exit criteria pass.
