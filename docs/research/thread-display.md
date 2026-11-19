# Thread display: Beeper Desktop and Apple Messages

Researched 2026-11-18 for MATRIX-183. Static analysis only. No app was launched. No user data was read. Nothing was run from an extract. No code or assets were copied into the repo.

Targets:

| Target | Path | Version | Identity |
|---|---|---|---|
| Beeper Desktop | `/Applications/Beeper Desktop.app/Contents/Resources/app.asar` | 4.3.326 | asar SHA-256 `fd5103e8e01cfcda81f1ab159f7b0fe6a726d08423610307ee199ee16b21bea4` |
| Apple Messages | `/System/Applications/Messages.app` | 26.0 (1491.300.43) | Mac Catalyst app. UI code is in `ChatKit.framework` (dyld shared cache, not read). Resources read from `/System/iOSSupport/System/Library/PrivateFrameworks/ChatKit.framework/Versions/A/Resources/` |

Method:

- Beeper: REA `analyze_javascript_application`, `detail: "summary"`, `integrity_policy: "record-and-continue"` (the asar declares integrity hashes for unpacked native binaries that were signed after packing), source selection `package.json`, `build/renderer/App-DzfobFE0.js`, `build/renderer/load-stores-CHnKYOS4.js`. Application Evidence `ev_87e7251e781d0f75377603ecdea0323a48637cd2bb150a952ca45b0bbb410d4b` (summary view `ev_511e5dab…`). REA parsed only part of the 3.2 MB minified App bundle, and a `trace_application_feature` seed on `m.thread` returned no match (`ev_c69cc68e…`, "not evidence that the feature is absent"). So most findings come from a direct text read of the extracted bundle and its CSS. The extract was put in a session scratchpad, not kept.
- Messages: `plutil` on the app's and ChatKit's `.loctable` files, and `assetutil --info` on ChatKit's `Assets.car`. No binary was disassembled. The dyld shared cache was not dumped.

Short file names (Beeper, inside `build/renderer/`):

- `APP` = `App-DzfobFE0.js`
- `CSS` = `App-DDFEf930.css`

Offsets are character offsets into the file. Component names come from the `data-sentry-component` / `data-sentry-source-file` tags that the bundle keeps.

Tags:

- **[code]**: read directly from shipped code or resources at the cited location.
- **[inferred]**: a conclusion from the code that the code does not state directly.
- **[public]**: widely known public behavior. Not found in the shipped files in this pass.
- **[rec]**: a recommendation for Mactrix.

---

## 1. Current Mactrix thread UI

What the code does today:

- **[code]** The main column shows a thread root with `MessageThreadSummary` under the body: an italic label "Thread (N messages)" with the `arrow.turn.down.right` symbol, and one secondary line with the latest reply text. The chip is a plain button on a 5% background (`BubbleToken.threadSummaryBackgroundOpacity`). A click calls `WindowState.focusThread(rootEventId:)` (`ChatMessageView.swift` 256).
- **[code]** `focusThread` opens the inspector with `.focusThread(threadTimeline:)`, a `LiveTimeline` with `TimelineFocus.thread(rootEventId:)` (`WindowState.swift` 233, `LiveTimeline.swift` 164).
- **[code]** The panel is `ThreadTimelineHeader` plus a full `ChatView` (`InspectorScreen.swift` 31). The header is a `.thinMaterial` strip with a leading `xmark.circle.fill` button and the word "Thread". It shows no room name, no root author, and no reply count.
- **[code]** The panel `ChatView` is the same view as the main column: the same AppKit table, the same row views, and the same floating glass composer (`TimelineComposerLayout`, MATRIX-198). The composer placeholder is "Message <room name>" in both places (`ChatInputView.swift` 199).
- **[code]** Per the MATRIX-169 smoke check, the panel shows the root and then each reply. The root row is drawn with the same row view as a reply.
- **[inferred]** The root row in the panel can also carry its own thread summary chip, because the SDK gives the root its summary in the thread timeline too. A click on it is a no-op, because `focusThread` returns early for the thread that is already open. Verify on the dev account.
- **[code]** The main column does not mark which root is open. Rows have a focus background (`AccentToken.activeBackgroundOpacity`) for a focused event, but nothing sets it for the open thread.
- **[code]** A reply from the main composer to a root goes into the thread (`ReplyRoute`, MATRIX-169). It does not show as a row in the main column. A failed send shows `ThreadReplyNoticeBar` above the main composer (MATRIX-173).

Likely sources of the confusion that Patrick reported:

1. **Two identical columns.** The panel looks like a second, narrow copy of the main chat. Same rows, same glass composer, same placeholder. Nothing tells you "this column is one thread".
2. **The root looks like a reply.** The first row has no visual rank. If it also shows its own "Thread (N messages)" chip, that chip points at the panel you are already in.
3. **The header names nothing.** "Thread" with no room, no author, and no count. The close button is on the leading edge, which is the iOS sheet convention, not the macOS inspector one.
4. **No link between the columns.** After you click a chip, the main column gives no sign of which message the panel belongs to. If you scroll the main column, the link is gone.
5. **The chip reads as a status.** Italic "Thread (N messages)" counts messages, not replies, and has no button shape or chevron.

---

## 2. Beeper Desktop

Beeper uses the word "thread" for a chat. A Matrix-style thread is a "threaded reply" in its code (`useThreadedReplies`, `ThreadedRepliesPane`, `ThreadedRepliesView`). Beeper has **two different reply UIs**, and it picks one by network capability:

- **Threaded replies** (networks with real threads, such as Slack and Matrix `m.thread`): a side pane.
- **Reply threads** (networks with quote replies only, such as iMessage and WhatsApp): a blurred overlay over the conversation, with connector lines in the main timeline.

### 2.1 How a thread root shows in the main timeline

- **[code]** `ThreadRepliesButton` (`APP` @2284948, styles `.ThreadRepliesButton-module__*` in `CSS`). It sits in the message footer's reactions row, next to the reaction chips (`MessageFooter`, `APP` @2296585). It shows when `useThreadedReplies` is on and the root has replies.
  - It uses the same pill classes as a reaction chip (`message-reaction-container`).
  - Up to **3 distinct replier avatars**, 16 pt (`I0t=3`).
  - The label "%d reply" / "%d replies".
  - An unread badge with the count, plus a mention marker, only for a followed thread.
  - A trailing `chevron-compact-right`.
  - The pill has a 2 px border in the page background color, so it reads as a raised chip.
- **[code]** No last-reply text preview on the chip. The last-reply preview appears only in the "Unread threads" list (`UnreadThreadCard`).
- **[code]** Thread-only replies are hidden from the main timeline. A reply sent with "also send to channel" (`extra.broadcastOutsideThread === true`) shows in the main timeline with a `ThreadRootLine` above it: "**Replying to:** <root text>", a small button that opens the thread (`APP` @2272245, `u8`).
- **[code]** Keyboard: Cmd+Down is "Show Replies" (`SHOW_REPLY_THREAD`, `APP` @98368).

### 2.2 How a thread opens

- **[code]** `showThreadedReplies(id)` sets `openThreadedReplies` and makes the threaded-replies pane visible (`APP` @1913357). The pane is the right part of the chat area, beside the conversation (`Sjt`, `APP` @3072896). It shares that slot with the chat info pane: one or the other shows (`visibleThreadPane` is `THREADED_REPLIES` or `INFO`).
- **[code]** The pane width is a fraction of the chat area, with a drag handle and a double-click reset (`ThreadedRepliesPane.tsx`, `setThreadedRepliesPaneFraction`).
- **[code]** If the thread is already open in its own window, Beeper focuses that window instead (`focusThreadedRepliesWindow`).
- **[code]** "Open in New Window" makes a 380x700 window titled "Thread in %s" (the chat title) with the same view (`ThreadedRepliesBrowserWindow`, `APP` @2589847).

### 2.3 Root and replies in the pane

- **[code]** The pane list is the root message, then a **"%d reply / %d replies" divider**, then the replies. The divider is a list item (`ThreadRepliesDivider`, `APP` @2417874) put right after the root (`l5t`, `APP` ~@2421000). CSS: centered secondary text in label-sm weight 600, with a 1 px hairline on each side (`.thread-replies-divider` in `CSS`).
- **[code]** On open, an **unread divider** is put at the last-read point of the thread (`replyThreadDividerOnOpen`), and the list scrolls to it (`ThreadedRepliesView`, `APP` @2578455).
- **[code]** The root is drawn with the normal message component. Its own replies button is hidden in the pane (`.ThreadedRepliesView-module__messages .message-show-replies-button{display:none}`). Typing indicators and "seen by" text are hidden too.
- **[code]** Replies are not grouped into quote chains in the pane (`groupReplies: false`).

### 2.4 Pane header

- **[code]** `ThreadedRepliesHeader` (`APP` @2439223): a leading "More Options" button (`dots`), a **centered title "Thread"**, a trailing "Close" button. In the pop-out window the title is "Thread in <chat>".
- **[code]** The header floats over the list (`position:absolute`), and the list has a top padding of the header height plus a top fade mask (`.fadeout-top`).
- **[code]** The "More Options" menu (`Bfe`, `APP` @2591586): "Mark as Read" (if unread), follow or unfollow, "Open in New Window", and **"View in Chat"**, which selects the chat, scrolls the main timeline to the root, and selects it.

### 2.5 Pane composer

- **[code]** A composer at the bottom of the pane with its own store per root (`replyComposerStore(rootID)`), autofocus on open, and file drop (`ThreadedRepliesView`).
- **[code]** Its placeholder is **"Reply in thread…"** (`replyComposerProperties`, `APP` search `placeholder:g("Reply in thread…")`). The main composer keeps its own placeholder. So the two composers say different things.

### 2.6 How the main timeline marks the open thread

- **[code]** In the message row `K0` (`APP` @2390577), a flag is true when the threaded-replies pane is visible and `openThreadedRepliesRootID === message.id`. The row then gets the class `is-selected` (`APP` @2396795), the same class as a selected message.
- **[code]** `is-selected` darkens the bubble: `filter: brightness(.7)` on the message contents (`CSS`). So the root of the open thread stays visibly selected in the main column while the pane is open.

### 2.7 Plain replies (quotes) vs threads

- **[code]** On quote-reply networks, adjacent messages in the same quote chain get **connector line segments** in the gutter: along the message body, along the avatar, and from the quoted message (`n2t` reply-line logic, `APP` @2381388, `replyLineSegments`, styles `.MessageContainer-module__replyLine*`). The line is a fixed-width gutter element. It does not change row height.
- **[code]** The footer of a quoted message shows "%d Reply" / "%d Replies" as a small info-line button (`Z0t`, `APP` @2291333).
- **[code]** A click opens the **reply-thread overlay** (`_5t`, `APP` @2438500): a `section.reply-thread` over the whole conversation with `background: rgba(surface/.6)` and `backdrop-filter: blur(8px)`. It fades in over 0.2 s. The message list inside moves up 10 px over 0.6 s. A close button sits at the top right. A click on the backdrop closes it. Reply buttons, quote previews, and reply lines are hidden inside the overlay. This is the iMessage model.
- **[code]** On thread networks, a quote inside a thread is a normal quote in the pane.

### 2.8 i18n strings (en, from `APP`)

"Thread", "Thread in %s", "%d reply" / "%d replies", "%d Reply" / "%d Replies", "%d unread reply" / "%d unread replies", "%d new reply" / "%d new replies", "Reply in thread…", "Replying to:", "Show Replies", "View in Chat", "Open in New Window", "Follow Thread", "Unfollow Thread", "Unread threads", "Select a thread".

---

## 3. Apple Messages

### 3.1 Evidence from the shipped resources

- **[code]** ChatKit `ChatKit.loctable`, en:
  - `REPLY_COUNT`: "%@ Reply" / "%@ Replies" (plural rule). This is the link under a message that has replies.
  - `HIDE_REPLIES`: "Hide Replies".
  - `INLINE_REPLY_MENU`: "Reply…". `REPLY_TO_MESSAGE`: "Reply to Message…". `REPLY_TO_LAST_MESSAGE`: "Reply to Last Message…". `REPLY_TO_REPLY`: "Continue Last Reply…".
  - `INLINE_REPLY_TEXT_ENTRY_PLACEHOLDER`: "Reply". The focused reply view has its own entry field with its own placeholder.
  - `INLINE_REPLY_ORB_TITLE`: "Reply". `QUOTED_REPLY`: "“%@”".
  - `INLINE_REPLY_%@_REPLYING_TO_%@`: "%@ replying to %@". `INLINE_REPLY_%@_REPLYING_TO_YOU`: "%@ replying to you".
- **[code]** The app's own `Localizable.loctable` and `MessagesAppKitBridge.bundle` hold no reply strings. The bridge bundle holds settings windows only.
- **[code]** ChatKit `Assets.car` color assets (sRGB, light / dark):
  - `CKInlineReplyTranscriptBackgroundColor`: white at 0.60 / black at 0.40. The wash over the transcript behind the focused reply view.
  - `CKReplyLineColor`: black at 0.08 / white at 0.16. High contrast: 0.38 / 0.46. The connector line between a reply and its original.
  - `CKReplyGrayBalloonColor`: black at 0.20 / white at 0.22. `CKReplyBlueBalloonColor`: system blue at 0.40 / 0.42. `CKReplyGreenBalloonColor`: a light green. With matching `CKReply*TextColor` values (gray text black at 0.44). These are the faded balloons that show the original message above a reply.
  - `CKInlineReplyButtonColor`: white at 0.90 / gray at 0.70, with `CKInlineReplyButtonBorderColor` black or white at 0.07 and `CKInlineReplyButtonShadowColor`. A small raised button, most likely the reply-count control.
  - Image sets `bubble-reply`, `bubble-reply-min`, `bubble-reply-multiline`, `bubble-reply-stroked*`, each with `mac-`, `decreased-`, `increased-` and `-ax` variants. A separate balloon shape family for the quoted original.
- **[inferred]** Messages draws a quoted original as a smaller, faded balloon of its own shape, not as a quote block inside the reply balloon. The connector is a very low-contrast line (8% black).

### 3.2 PUBLIC KNOWLEDGE (iOS 14 / macOS 11 onward, not confirmed in this pass)

- **[public]** In the transcript, a reply shows a faded copy of the original above it. A curved connector line runs from the original to each reply in the gutter.
- **[public]** Under an original with replies, a small "N Replies" link shows.
- **[public]** A click on the link or on a reply opens a focused reply view. The rest of the conversation fades behind a wash. The original shows at the top, then its replies in order, then an entry field with the placeholder "Reply". A click outside or "Hide Replies" closes it.
- **[public]** The focused view does not leave the conversation. It is an overlay on top of it, with a short fade and lift.
- **[public]** Messages has no separate thread panel and no thread list.

### 3.3 Answers per question

| Question | Messages |
|---|---|
| Root in the main transcript | Normal balloon plus "N Replies" link. Each reply shows a faded original above it and a connector line. [code strings, assets] [public layout] |
| How it opens | Focused overlay over the transcript, with a wash (60% white / 40% black). [code color] [public] |
| Root vs replies | Original at the top, replies below. [public] |
| Header | None found. "Hide Replies" closes. [code string] |
| Composer | Its own field in the focused view, placeholder "Reply". [code string] |
| Open-thread mark | The wash dims every message except the focused set. [public] |
| Plain replies vs threads | One model only: inline replies. [public] |

---

## 4. Three variants for Mactrix

Rules that every variant keeps:

- No glass on timeline content. Glass only on the navigation layer and the composer.
- No row height change from motion. A mark on a row is a background, a stroke, or a gutter element of fixed size.
- The timeline stays the AppKit table. Any new row type is a fixed-height virtual row built from the SDK items, with no new Matrix logic.
- No new thread features. Every item below is presentation of data the SDK already gives (the root, the replies, the summary count, the latest reply).

### Variant A: Label and mark (minimal fixes in the current panel)

Fix the five confusion sources with labels and marks. No new rows. No new windows.

- **Panel header.** Title "Thread" with a subtitle "in <room name>" and the reply count, for example "Thread" / "#general · 4 replies". Close button on the trailing edge (macOS inspector convention). Keep the material strip, it is the navigation layer.
- **Root in the panel.** The first row (the root) gets a permanent tinted band: the existing focus background at a low opacity plus a 2 pt accent bar in the leading column. No height change. Hide the root's own summary chip inside the panel (`timeline.focusedThreadId == event id`).
- **Replies.** Unchanged rows.
- **Panel composer.** Same position (floating glass at the bottom of the panel). Placeholder "Reply in thread…" instead of "Message <room>". This one string is the cheapest fix with the highest value.
- **Main column mark.** While the panel shows a thread, its root row in the main column gets the existing focus background (Beeper does the same with `is-selected`). The mark goes away when the panel closes or shows another thread.
- **Main column chip.** Relabel to "N replies" (not "Thread (N messages)"), not italic, with a trailing chevron. Keep the latest-reply line.
- **Motion.** None.

```
 main column                               | thread panel (inspector)
-------------------------------------------+-------------------------------
                                           | Thread                      x |
  Ana    Can someone check the deploy?     | #general · 4 replies          |
 ######################################### |-------------------------------|
 # Ben   It failed on step 3.            # | |Ben  It failed on step 3.    |  <- root band
 #       [ 4 replies  >  ]               # | |                             |     + accent bar
 #       Cy: fixed, rerun now            # |-------------------------------|
 ######################################### |  Cy   Looking                 |
  Dee    lunch?                            |  Ana  Thanks                  |
                                           |  Cy   fixed, rerun now        |
                                           |                               |
 ( Message #general                  )     | ( Reply in thread…          ) |
```

`#` marks the existing focus background on the open root.

Files to change:

- `MactrixLibrary/Sources/UI/Timeline/ThreadTimelineHeader.swift` (title, subtitle, close position, with room name and count as inputs)
- `Mactrix/Views/Inspector/InspectorScreen.swift` (pass room name and count)
- `MactrixLibrary/Sources/UI/Timeline/MessageThreadSummary.swift` (label, chevron)
- `Mactrix/Views/ChatView/ChatMessageView.swift` (hide the chip on the panel root, root band, open-root mark from `WindowState.inspectorContent`)
- `Mactrix/Views/ChatView/ChatInputView/ChatInputView.swift` (placeholder when `timeline.focusedThreadId != nil`)
- Snapshot tests for the chip, the header, and a root row with the band.

Size: **small**.

Caution: the open-root mark must not re-measure the row. Draw it in the same layer as the hover and focus background, which the code already keeps out of the height fingerprint.

### Variant B: Focused reply view (Messages model)

Replace the inspector thread panel with a focused overlay on top of the main column, as Messages does. The thread replaces your view of the chat for a moment, then gives it back.

- **Open.** A click on "N replies" lays an opaque scrim over the main timeline: the window background at about 0.85 opacity. No blur and no glass, because the scrim covers scrollable content. A thread view sits on the scrim in the same column.
- **Root.** A root card at the top of the thread view, pinned (it does not scroll away). Full text up to 4 lines, then "Show more". Author, time, room. It reads as the subject of the view.
- **Replies.** A list under the card. A connector line runs in the leading column from the card down to each reply avatar, at `CKReplyLineColor` strength (black 8% / white 16%). Each row draws its own segment in a fixed-width gutter, so no height change. Thread-only quotes inside the thread keep the normal embedded reply.
- **Header.** None. A "Hide Replies" button at the top trailing corner, and Esc closes. A click on the scrim closes.
- **Composer.** The main composer stays where it is and changes target while the view is open: placeholder "Reply in thread…" and a small leading chip "Thread: <root excerpt> x". Closing the view returns the composer to the room. This reuses `ReplyRoute.thread(root:inReplyTo:)`.
- **Main column mark.** The scrim is the mark. Everything except the thread is dimmed.
- **Motion.** Scrim fades in over 0.2 s. The thread view moves up 10 pt and fades in over 0.3 s (Beeper uses 0.2 s and 0.6 s). Motion is on the overlay layer only. No timeline row moves or changes height.
- **Plain replies.** Optional later step: the same connector line between a plain reply and its original in the main column, when both rows are adjacent (Beeper does this with `replyLineSegments`).

```
 main column (thread view open)                                  inspector
--------------------------------------------------------------+-------------
 . . . . . . . . . . . . . . . . . . . . . . . [Hide Replies]  |  (room info,
 . +--------------------------------------------------------+  |   unchanged)
 . | Ben · #general · 10:42                                 |  |
 . | It failed on step 3. The log says the runner ran out   |  |
 . | of disk.                                               |  |
 . +--------------------------------------------------------+  |
 .   |                                                         |
 .   +-- Cy    Looking                                         |
 .   |                                                         |
 .   +-- Ana   Thanks                                          |
 .   |                                                         |
 .   +-- Cy    fixed, rerun now                                |
 . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . |
 ( [Thread: It failed on step 3. x]  Reply in thread…      )   |
```

`. .` is the opaque scrim over the main timeline.

Files to change:

- New `MactrixLibrary/Sources/UI/Timeline/ThreadFocusOverlay.swift` (scrim, root card, connector gutter)
- `Mactrix/Views/ChatView/ChatView.swift` (overlay over `TimelineComposerLayout`, composer target chip)
- A second `TimelineViewRepresentable` for the thread list, or a new compact list. The thread list needs the connector gutter in its row views.
- `MactrixLibrary/Sources/Core/WindowState.swift` (`focusThread` opens the overlay, not the inspector)
- `Mactrix/Views/ChatView/ThreadReplyNoticeBar.swift` ("Open Thread" target)
- `Mactrix/Views/ChatView/ChatInputView/ChatInputView.swift` (target chip, placeholder)
- Remove the `.focusThread` case from `InspectorScreen.swift`.
- Snapshot tests for the overlay and the gutter.

Size: **large**.

Risks:

- You cannot read the chat and the thread at the same time. This is the main cost of the Messages model. It fits short quote chains, not long Slack threads with 40 replies.
- A second table timeline inside an overlay doubles the scroll and height-cache work that the spike already measured for one.
- The scrim is close to the rule "the timeline is opaque". An opaque scrim keeps the rule. A blur would break it.
- It throws away MATRIX-169 and MATRIX-173 work on the panel.

### Variant C: Thread pane with divider and pop-out (Beeper model)

Keep a side pane, but make it a thread pane with its own structure, as Beeper does.

- **Header.** Centered title "Thread". Leading "..." menu with "View in Chat" (scroll the main column to the root and focus it) and "Open in New Window". Trailing close. The header floats over the list with a top fade, so the list scrolls under it. The header is the navigation layer, so material is allowed.
- **Root.** First row, normal row view, with its own chip hidden.
- **Divider.** A fixed-height virtual row right after the root: "4 replies" in secondary label-sm semibold, centered, with a hairline on each side. This one row gives the root its rank without a new row style.
- **Unread.** On open, the SDK's read marker (if the thread timeline gives one) shows as the existing unread divider, and the list scrolls to it. No new receipt logic.
- **Replies.** Normal rows.
- **Composer.** Bottom of the pane, "Reply in thread…", autofocus on open.
- **Main column chip.** A pill in the reactions row, styled like a reaction chip: up to 3 replier avatars from the latest replies the summary gives, "4 replies", chevron. If the summary does not give the repliers, show the latest reply's sender avatar only.
- **Main column mark.** The open root keeps the focus background while the pane shows it (same as A).
- **Pop-out.** "Open in New Window" opens a narrow window (about 380x700) titled "Thread in <room>" with the same pane content. This is presentation of the same thread timeline, not a new thread feature. It is the first part to cut if scope is tight.
- **Pane width.** Beeper uses a draggable fraction. Mactrix gets this for free from `.inspectorColumnWidth`. Raise the ideal width so a thread reads as a column, not a sidebar.
- **Motion.** The pane slides in with the system inspector animation. Nothing else.

```
 main column                               | thread pane
-------------------------------------------+-------------------------------
                                           | ...        Thread           x |
  Ana    Can someone check the deploy?     |~~~~~~~~~~~ (fade) ~~~~~~~~~~~~|
 ######################################### |  Ben  It failed on step 3.    |
 # Ben   It failed on step 3.            # |                               |
 #       (o)(o)(o) 4 replies  >          # |  ------- 4 replies -------    |
 ######################################### |  Cy   Looking                 |
  Dee    lunch?                            |  ------------ New ----------  |
                                           |  Ana  Thanks                  |
                                           |  Cy   fixed, rerun now        |
                                           |                               |
 ( Message #general                  )     | ( Reply in thread…          ) |

 "..." menu: View in Chat · Open in New Window
```

Files to change:

- `MactrixLibrary/Sources/UI/Timeline/ThreadTimelineHeader.swift` (menu, centered title, floating layout)
- `Mactrix/Views/Inspector/InspectorScreen.swift` (header over the list, width)
- New `MactrixLibrary/Sources/UI/Timeline/ThreadRepliesDivider.swift` and a new virtual row case in the thread timeline item list (`TimelineViewRepresentable` coordinator and the row height fingerprint)
- `MactrixLibrary/Sources/UI/Timeline/MessageThreadSummary.swift` (pill with avatars and chevron)
- `Mactrix/Views/ChatView/ChatMessageView.swift` (hide the panel root chip, open-root mark)
- `Mactrix/Views/ChatView/ChatInputView/ChatInputView.swift` (placeholder, autofocus)
- New window scene for the pop-out (optional)
- Snapshot tests for the divider row, the pill, and the header.

Size: **medium** (small to medium without the pop-out window).

Risks:

- A client-made virtual row in the table must keep a stable identity and height, or it breaks the scroll anchoring that the spike tuned. Date dividers already do this, so follow that path.
- A floating header with a fade over the list puts material over scrolled content edges. Keep the fade a mask on the list, and keep the header itself as navigation chrome, to stay inside rule 2.

---

## 5. Recommendation

**[rec] Ship Variant A now, then add the divider row and the pill from Variant C as a second step.**

Reasons:

- Patrick's report is about hierarchy, not layout. All five confusion sources in section 1 are fixed by A: a header that names the room and count, a root with rank, a composer with its own placeholder, a mark on the open root, and a chip that reads as a button. None of these needs a new row type or a new window.
- Both reference apps agree on the same four signals: the panel composer says "Reply in thread" or "Reply", the root has rank (Beeper's divider, Messages' card at the top), the open root is marked in the main view (Beeper's `is-selected`, Messages' wash), and the chip is a counted button ("N replies"). A gives three of the four at small cost. C's divider gives the fourth.
- Variant B fits quote chains, not long threads. Mactrix threads come from Slack and Matrix, where threads run long and you want the channel visible beside them. Beeper, which handles both cases, uses the overlay only for quote-reply networks and uses a side pane for real threads. That split is the strongest evidence here.
- B also costs a second timeline in an overlay and drops the MATRIX-169 and MATRIX-173 panel work.

Questions to answer before you build:

- Does the root in the panel show its own summary chip today? Check on the dev account. If not, drop that item from A.
- Does the SDK thread timeline give a read marker? If not, skip the unread divider in C. Do not compute one in the app (hard rule 1).
- Does the thread summary give the senders of the latest replies? The pinned FFI shows `numReplies()` and the latest event. If it gives no list of senders, the pill shows one avatar, not three. Read `docs/ffi/` before you write the call (hard rule 5).
- Is the narrow inspector the real constraint? At the current ideal width of 400 pt, a reply with media gets about 300 pt of text width. A wider default may fix as much as any of the above.
