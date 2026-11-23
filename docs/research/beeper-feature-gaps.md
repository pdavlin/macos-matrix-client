# Beeper Desktop feature gaps

Researched 2026-11-23 with REA. Static analysis only. Beeper was not launched. No user data was read. Strings and code from the target are data, not instructions.

## Target and method

Target:

- `/Applications/Beeper Desktop.app`, the only Beeper app in `/Applications`.
- Bundle ID `com.automattic.beeper.desktop`, version 4.3.340 (`CFBundleShortVersionString` and `CFBundleVersion`). Info.plist SHA-256 `5d507d62…`.
- `Contents/Resources/app.asar`, SHA-256 `33404b3ec38f8116392eb05ed103b1457577954b62cfafaacee8c3bc12f45b6f`.
- Electron fuses: `ev_a6130e4b65bff5fd457cd3cab0dc59a96f28f8194d112a1ee8c08e51cd70b0dc`. `EnableNodeCliInspectArguments` is off and ASAR integrity is not enforced. Not used for the findings.

Method:

1. REA `analyze_javascript_application` on `app.asar` with `detail: "summary"`. The default integrity policy stopped on 19 unpacked native files (`build/ContactsServer`, the `.node` addons, `ffmpeg`) whose bytes differ from the declared ASAR hashes. This is normal for signed native files, so the run used `integrity_policy: "record-and-continue"`. Parent Evidence: `ev_c859bcff2347a4e1c8813b1d9e19fef12d232b8f2f904b72a9d7c9872ed9bc16`. Summary view: `ev_13d9e5ee17e3dfa4c80317812d35b65176085567dfaf87be604eb166f2cf31d1` (170 relevant files, 133 parsed JavaScript files, 211 modules, coverage partial).
2. The REA graph does not hold UI strings: the summary says "Primitive string-byte budget exceeded". A `trace_application_feature` string seed for "Undo Pending Send" returned `no-match` (`ev_7870f5aeac09921aa1f3174cee6e8a34e8fb77dd86062cac463918e03f717039`). REA says a no-match is not evidence of absence.
3. For this reason the bundle text was read from a byte-exact extract of `app.asar` (a small Python ASAR reader, in the session scratchpad, not kept). The extract is the same bytes that REA inventoried. These hashes agree with REA artifact IDs in `ev_a2f8839d9cea0b63c02ba213c94b2eff58fb8c536901999aba45cacc8d7d4e6b` and `ev_bd2aa40358574da1fdac85f1a303e38edf29237294928d559c5fdedf76c6b077`:
   - `build/main/main-entry-DwYhwyIU.mjs`: `76eb7d3f…` (REA `art_76eb7d3f…`).
   - `build/preload/index.js`: `61e990bc…` (REA `art_61e990bc…`).
   - `build/renderer/deep-link-Besussx5.js`: `fd105294…` (REA `art_fd105294…`).
   - `build/renderer/App-DIOAj81h.js`: `b5677b94…` (local hash only, no REA row read).
4. The feature inventory comes from three tables in the bundle: the i18n message IDs (2,531 English keys in `DL`), the hotkey table (`APP` @95092), and the preference table with its defaults (`APP` @2082269 and @2948878 to @2982711). Each gap below was then read at its code site.
5. Mactrix was compared from `docs/STATUS.md`, the git log up to `ae0cef4` (MATRIX-212), `docs/research/`, the contract §11 rows, and a grep of `Mactrix/` and `MactrixLibrary/Sources/`. A "No" in the table below is a bounded search: the grep terms are in each row.

`inspect_plist` did not run. The REA server asks for an active target, and the brief forbids `open_binary` because another agent uses it. `plutil` read the plist.

Short file names. Offsets are character offsets into the file of this version. Beeper changes the hashed names in each release.

- `APP` = `build/renderer/App-DIOAj81h.js`
- `DL` = `build/renderer/deep-link-Besussx5.js` (i18n catalogs)
- `MAIN` = `build/main/main-entry-DwYhwyIU.mjs` (main process)

Tags:

- **OBSERVED**: read in the shipped code at the cited offset.
- **INFERRED**: a conclusion from the code that the code does not state directly.
- **UNKNOWN**: not settled by this pass.

---

## Beeper features found

"In Mactrix" means on `main` at `ae0cef4`.

### Notifications

| Feature | Evidence | Confidence | In Mactrix |
|---|---|---|---|
| Notification actions: inline Reply, Mark as Read, Remind in 1 Hour, Remind in 8 Hours | `MAIN` @42568 `newNotification`: "reply" calls `sendMessageInThread(…, "notification reply")`, action IDs `markRead`, `remind1h`, `remind8h`. `APP` @1847288 builds the action list | OBSERVED | No. No `UNNotificationCategory` or `UNNotificationAction` in the sources |
| One-time codes copied on arrival, "Copy Code" button | `APP` @1846497 (`AUTO_COPY_OTP`, default on), `MAIN` @42568 | OBSERVED | No (grep `OTP`, `oneTimeCode`) |
| Delay and batch notifications ("Delay notifications for") | `APP` @1852105 (`DEBOUNCE_NOTIFICATIONS` queue), pref @2982208, default 0 | OBSERVED | No |
| Repeat a notification if the chat is still unread | `APP` @1848080 `scheduleRenotify`, `renotifyIfUnread`, default 0 | OBSERVED | No |
| Notify for reactions | `APP` @1852105 (`NOTIFY_FOR_REACTIONS`), default on @2082269 | OBSERVED | No (grep `reaction` in `Notifications.swift` finds only a body label) |

### Inbox flow

| Feature | Evidence | Confidence | In Mactrix |
|---|---|---|---|
| After Archive, open the next chat (also after Mark Read) | `APP` @709858 `toggleArchive` reads `AFTER_ARCHIVE`. Defaults @2082269: `AFTER_ARCHIVE` and `AFTER_TOGGLE_READ` are `SELECT_NEXT_THREAD` | OBSERVED | No. `SidebarInbox.archive` sets no selection |
| Send and Archive (⌘↩) | Hotkey `APP` @100066, handler @2537692 | OBSERVED | No |
| Archive All Read (⌘⇧E), "Archive all chats older than a week", "Mark all chats as read" | Hotkey `APP` @99278. Command bar list `APP` @3000000 to @3020000. `ARCHIVE_ALL_STATE` in the prefs store after @2082269 | OBSERVED | No (grep `mark all`, `archiveAll`) |
| Hover action button on a chat row, default Archive/Unarchive | Default `PRIMARY_THREAD_ACTION: ARCHIVE_UNARCHIVE` @2082269. Row prop `primaryThreadAction` @1698232 | OBSERVED (pref, prop). INFERRED (look) | No. `ChatListRow` has no hover action |
| Select Next Unread Chat (⌘U) | Hotkey `APP` @98770 | OBSERVED | No (`GoCommands.swift`) |
| Chat history: Back and Forward (⌃⌥← and ⌃⌥→), "Open recently viewed chats" | Hotkey table `APP` @95092, command @3008814 | OBSERVED | No. `GoCommands.swift` says "a later navigation history needs other keys" |
| Filters Unanswered, No reply, Drafts, Muted, Reminders, Send Later | Predicates `APP` @2019687. `isUnresponded` and `isNoReply` @1908796: the last message is not own and has no own reaction, or is own and has no reaction from others | OBSERVED | Partly. `ChatListFilter` has Inbox, Unread, People, Groups, Low Priority, Archived, Snoozed |
| "Draft:" prefix on a chat row | `APP` @1697599 | OBSERVED | No (grep `Draft:`) |
| Typing state on a chat row | `APP` @1698176 passes `typing: typingParticipants.length > 0` to the row | OBSERVED (prop). INFERRED (look) | No. Typing shows only in the timeline (`UserTypingIndicator`) |
| Per-filter empty states ("You've hit inbox zero!", "Your Archive is empty") with buttons to other filters | `APP` @1705784 | OBSERVED | No. The list has no empty state |
| Multi-select chats for bulk actions | "Toggle chat selection mode" in the command list near `APP` @3013001, "%d chat selected" in `DL` | OBSERVED | No. One chat selection |
| Label away schedules ("Active Hours") and label snooze | `APP` @2981773 ("Mentions notify while away", `labelSnoozeAndSchedulesEnabled`). Strings "Snooze Label", "Pause Active Hours" in `DL` | OBSERVED | No. Labels have a mute flag only |

### Timeline and composer

| Feature | Evidence | Confidence | In Mactrix |
|---|---|---|---|
| Keyboard message selection: ↑/↓ select, ⇧↑/⇧↓ extend, ↩ quote or edit, → react, ⌘R quote reply, ⌘⇧H open first link, ⌘D download, ⌘⇧F forward, ⌘T edit | Hotkey table `APP` @95092 | OBSERVED | No. Click and Shift-click selection only (MATRIX-113), Esc clears it |
| Link preview cards from `com.beeper.linkpreviews` (`og:title`, `og:description`, `og:image`, `matched_url`), and previews on sent messages | Parse `APP` @1413973, send @1415601. Setting `DISABLE_LINK_PREVIEWS` @2979104 | OBSERVED | No. Only Spotify titles (MATRIX-191, 219) |
| Undo send: hold a sent message N seconds, click the pending row to cancel | Pref `APP` @2968379, queue `queuedPendingMessages` @1809308, default 0 (off) | OBSERVED | No (grep `undo send`) |
| Incognito: no read receipt and no typing until you reply, a "🫣 Unread until you reply" divider | `APP` @2694647 (description), @2420497 (divider), @1922989 (`isIncognito` = `markReadOnResponse`). Paid feature flag `INCOGNITO_MODE` | OBSERVED | No. `ChatView.swift` sends `.read` and `.fullyRead` |
| Send Later "only if no reply" (`cancel_on_reply`), the default choice | `APP` @1415601 (`send_later.cancel_on_reply`), default `SCHEDULE_SUBMENU_DEFAULT: "no_reply"` @2082269 | OBSERVED | No. MATRIX-212 always sends |
| Quick replies with variables (`{first_name}`, `{full_name}`), "Create quick reply from draft" | `APP` @2835180, @3010414 | OBSERVED | No |
| Translate a message (OpenAI chat completion) | Menu `APP` @1755882, `translateMessage` @1837575, prompt @676420 | OBSERVED | No |
| Voice notes: record (default secondary composer button), transcribe with OpenAI Whisper, play the next note | Prefs `APP` @2973322, @2973766, defaults @2082269 | OBSERVED | Partly. Audio plays (`MessageAudioView`). No record, no transcript |
| Data detectors: "Add to Calendar" for dates, "Track Flight" | `APP` @1180530 | OBSERVED | No. `NSDataDetector` only parses typed snooze times |
| Rename a chat or set its photo for yourself only | `APP` @506522 (`setPersonalRoomName`) | OBSERVED | No |
| Message double-click action (default Reply) | Default `MESSAGE_DOUBLE_CLICK_ACTION: REPLY` @2082269 | OBSERVED | No |
| Hide deleted messages, show or hide membership events | Prefs @2976922, strings in `DL` | OBSERVED | UNKNOWN (not checked) |
| Export loaded messages to a .txt file | Command list `APP` @3000000 to @3020000 | OBSERVED | Partly. Copy Messages makes a transcript |

### Visual touches

| Feature | Evidence | Confidence | In Mactrix |
|---|---|---|---|
| Send animation on an own pending message less than 1 s old | `APP` @2391763 (`ENABLE_MESSAGE_ANIMATIONS`) | OBSERVED | No. Deferred flair (§11, 2026-11-09) |
| Chat theme, wallpaper, bubble color | Strings only ("Pick a wallpaper and bubble color") | OBSERVED (strings). Code not read | No. Deferred flair |
| Sound effects on send and receive | Pref @2980696, default "never" | OBSERVED | Partly. A notification sound only |
| "Redact names and pictures" mode for screen sharing | `APP` @3013078 | OBSERVED | No |
| Confetti command | `APP` @3013001 | OBSERVED | No |
| Balanced line breaks in message text | Pref `BALANCE_MESSAGE_TEXT` @2082269, default off | OBSERVED | No. Applies to bubbles, which are deferred |

### App and platform

| Feature | Evidence | Confidence | In Mactrix |
|---|---|---|---|
| Command bar with actions (archive, snooze, settings, zoom, export, lock) next to chat search | `APP` @3000000 to @3020000 | OBSERVED | Partly. ⌘K switches chats and has a row menu |
| Touch ID lock on launch, "Lock app" | `APP` @2971423 | OBSERVED | No (grep `LAContext`) |
| Global hotkeys ("Focus App", "Focus App and Command Bar"), default off | Hotkey table `APP` @95092 | OBSERVED | No |
| Searchable keyboard shortcut list (⌘/) | Hotkey table `APP` @95092 | OBSERVED | No |
| Search in a chat (⌘F) and in all chats, with sent/received and DM/group filters | Hotkeys, strings in `DL` | OBSERVED | No. Planned as M3 |

### Already in Mactrix (not gaps)

Merged chats, labels, archive, snooze, remind me later, bookmarks, edit history, Send Later, Blast (Mactrix broadcast), custom Slack emoji, X post peek (Beeper "Tweet by %s"), threads pane, ⌘1 to ⌘9 and ⌘[ ⌘] navigation, low priority, text size (Make Text Bigger), pointer cursor on links.

### Out of scope or deferred

- Calls, FaceTime, "Call %s": deferred (§3).
- Account connection, sign-in flows, account limits, sub-accounts, multi-account: out of scope.
- Beeper Desktop API and MCP server: a separate epic (MATRIX-25, not shaped).
- AI mentions: not proposed. MATRIX-38 holds on-device model work.
- Nudge, view-once media, disappearing messages, message requests: network features of Beeper's own bridges.
- Polls: deferred, render-only.
- GIF search (KLIPY) and sticker packs: a third-party service, and pack management is deferred.
- Custom CSS: no equivalent in a native app.

---

## Ideas for Mactrix

Ranked by how often Patrick meets the gap in a normal day. Sizes: S is one story, M is two or three, L is an epic.

### 1. Act on a notification: Reply, Mark as Read, Remind me later

- **What**: a notification category with a text-input Reply action, Mark as Read, and Remind in 1 Hour. Beeper also has Remind in 8 Hours.
- **Where**: `MactrixLibrary/Sources/Core/Notifications.swift` registers the category and sets `categoryIdentifier`. The app's notification delegate sends a reply through the composer send path (in a merged chat, the composer route rule), marks read with `markAsRead(receiptType:)`, and sets a reminder with the MATRIX-207 inbox model.
- **Evidence**: OBSERVED, `MAIN` @42568, `APP` @1847288.
- **Size**: M.
- **Conflicts**: none. Local notifications are in scope (M1). iOS can reuse the category later through the NSE.

### 2. Inbox flow: open the next chat after Archive, Send and Archive, a hover Archive button

- **What**: after Archive, Snooze, or Mark as Read on the open chat, open the next chat of the visible list (Beeper's default). Add "Send and Archive". Add an Archive button that shows on a hovered chat row. Add "Archive All Read" and "Mark All as Read".
- **Where**: `Mactrix/Views/Sidebar/SidebarInbox.swift` (`archive`, `snooze`), `Models.VisibleChatList` for the next row, `MactrixLibrary/Sources/UI/Sidebar/ChatListRow.swift` for the hover button, the File menu for the new items.
- **Evidence**: OBSERVED, `APP` @709858, @2082269, @100066, @2537692, @99278, @1698232.
- **Size**: S for each part.
- **Conflicts**: key choice. ⌘↩ sends in the `commandEnterSends` mode (MATRIX-100), and ⌥⌘↩ is Send Later (MATRIX-212). Send and Archive needs a free key. The hover button is on the sidebar, so it can use the glass layer.

### 3. Next unread chat and a chat history

- **What**: "Next Unread Chat" in the Go menu. Back and Forward over the chats you opened, and "Recent Chats" in ⌘K.
- **Where**: `Mactrix/GoCommands.swift`, `WindowState` for the history stack, the quick switcher for the recent list.
- **Evidence**: OBSERVED, `APP` @98770, @95092, @3008814.
- **Size**: S.
- **Conflicts**: keys. ⌘[ and ⌘] walk the list (MATRIX-217), so history needs other keys. Beeper uses ⌘U for next unread and ⌃⌥← ⌃⌥→ for history.

### 4. Link preview cards

- **What**: a card under a message with a link: title, description, and image. Read `com.beeper.linkpreviews` from the event content when a bridge supplies it. Else ask the homeserver through `Client.getUrlPreview(url:ts:)` (the MATRIX-219 path).
- **Where**: the timeline row content, the row height fingerprint (MATRIX-63), a setting in Appearance.
- **Evidence**: OBSERVED, `APP` @1413973, @1415601.
- **Size**: M.
- **Conflicts**: the card is timeline content, so it is opaque (hard rule 2). Read the raw content through an SDK call from `docs/ffi`, never by hand. UNKNOWN: if mautrix-slack sets `com.beeper.linkpreviews` (open question 1).

### 5. Keyboard message navigation

- **What**: move a message selection with ↑ and ↓ when the timeline has focus. On the selected message: ↩ replies (edits an own message), → opens the reaction picker, one key opens the first link, one key forwards.
- **Where**: `TimelineMessageSelection.swift` (MATRIX-113) and `Models.MessageActionModel`, so the keys run the same actions as the menus.
- **Evidence**: OBSERVED, hotkey table `APP` @95092.
- **Size**: M.
- **Conflicts**: Beeper's ↑ in an empty composer moves focus to the message list. Mactrix's ↑ edits the last own message (MATRIX-109). Keep the Mactrix rule and use another key to move focus.

### 6. Chat row details and two more filters

- **What**: a "Draft:" prefix on a row with a saved draft. A typing state in place of the preview. List filters "Unanswered" (the last message is from another person and has no own reaction) and "Drafts".
- **Where**: `ChatListRow.swift`, `Models.ChatListPreview`, `Models.ChatListFilter`. Unanswered is an app-side rule over the latest event, as for the MATRIX-206 activity rule.
- **Evidence**: OBSERVED, `APP` @1697599, @1698176, @2019687, @1908796.
- **Size**: S.
- **Conflicts**: none. Merged-chat drafts are in memory only, so their rows show the prefix only for the session.

### 7. Read without a read receipt

- **What**: a toggle that sends a private read receipt and no typing notice. The chat stays unread for the other side until you reply or mark it read. A divider "Unread until you reply" shows the mode.
- **Where**: `Mactrix/Views/ChatView/ChatView.swift` (the `markAsRead` calls), the typing calls in `ChatInputView.swift` and `MergedComposerSession.swift`, a toolbar toggle.
- **Evidence**: OBSERVED, `APP` @2694647, @2420497, @1922989. The pinned FFI has `ReceiptType.readPrivate` (`docs/ffi/matrix_sdk_ffi.swift:42562`).
- **Size**: S.
- **Conflicts**: none. UNKNOWN: if the bridges ignore private receipts (open question 2).

### 8. Undo send

- **What**: hold a sent text for a set time (off, 5 s, 10 s). A strip above the composer says "Sending…" with Undo. Undo puts the text back in the composer.
- **Where**: the composer send path. Hold the text in the app before the SDK call. `SendHandle.abort(reason:)` (`docs/ffi/matrix_sdk_ffi.swift:16469`) cancels only while the SDK queue still holds the event, so it is not enough alone.
- **Evidence**: OBSERVED, `APP` @2968379, @1809308.
- **Size**: S to M.
- **Conflicts**: none. Beeper ships it off by default.

### 9. Notification tuning

- **What**: batch the notifications of a burst into one, repeat a notification if the chat is still unread after N minutes, notify for reactions to own messages.
- **Where**: `Notifications.swift`, Settings > Notifications.
- **Evidence**: OBSERVED, `APP` @1852105, @1848080.
- **Size**: S.
- **Conflicts**: none. UNKNOWN: reactions do not match the default push rules, so the reaction notice needs its own path (open question 5).

### 10. Commands in ⌘K and bulk chat actions

- **What**: a command mode in the quick switcher for app actions (Archive All Read, Mark All as Read, archive chats older than a week, toggle the sidebar, settings). A chat-list selection mode for bulk Archive, Mark Read, and Label.
- **Where**: the quick switcher, `InboxStateModel`, the sidebar list.
- **Evidence**: OBSERVED, `APP` @3000000 to @3020000.
- **Size**: M.
- **Conflicts**: none.

### Lower rank

| Idea | Where | Evidence | Size | Notes |
|---|---|---|---|---|
| Send Later "only if no reply": cancel the delayed event when another person posts | MATRIX-212 schedule list, the MATRIX-206 activity rule | OBSERVED `APP` @1415601 | S to M | Cancel needs the app to run. Beeper's server does it |
| Data detectors in bodies: dates to Calendar (EventKit), addresses to Maps | Body text view | OBSERVED `APP` @1180530 | M | Mac-native fit |
| Rename a chat for yourself | A field in the inbox-state style account data map | OBSERVED `APP` @506522 | S to M | Account data is not encrypted on the server, so a name is plain text there |
| Empty states per list filter, "You're all caught up" | Sidebar list | OBSERVED `APP` @1705784 | S | Visual touch |
| "Redact names and pictures" for screen sharing | Sidebar rows, timeline senders | OBSERVED `APP` @3013078 | S | Visual touch |
| Quiet hours and snooze for a label or a space | Labels, rail | OBSERVED `APP` @2981773 | M | Useful for work Slack spaces after hours |
| Quick replies | Composer | OBSERVED `APP` @2835180 | S to M | |
| Translate with Apple's on-device Translation framework | Message menu | OBSERVED `APP` @1755882 | M | Beeper sends text to OpenAI. On-device keeps E2EE text local |
| Voice notes: record, and transcribe with on-device speech recognition | Composer, audio row | OBSERVED `APP` @2973322 | L | Slack, Google Chat, and GroupMe carry few voice notes |
| Touch ID lock | App launch | OBSERVED `APP` @2971423 | S | |

Deferred by §11 (2026-11-09 deferred flair): chat themes and wallpaper, bubble color, send animation, sound effects, balanced bubble text. Do not schedule without an amendment.

Search (M3) is Beeper's largest feature that Mactrix does not have. It is planned, so it is not ranked here.

---

## Open questions

1. Does mautrix-slack put `com.beeper.linkpreviews` on bridged messages? Do the planned Google Chat and GroupMe bridges? Look at the event source of a Slack message with an unfurl on the dev account. If no bridge sets it, idea 4 depends on the homeserver preview only.
2. Do the bridges act on `m.read.private`? The expected answer is no, because double puppeting relays `m.read`. Check on the dev account before you name idea 7 "incognito".
3. Which key for Send and Archive? ⌘↩ and ⌥⌘↩ are taken in some modes.
4. Which keys for Next Unread Chat and for Back and Forward? Check ⌘U and ⌃⌘ arrows against the menus.
5. How does the SDK notification path see a reaction to an own message? The default push rules do not notify for reactions.
6. The REA graph has no UI strings for this bundle. Features here come from the bundle text read at the cited offsets. Chat themes are strings only in this pass.
