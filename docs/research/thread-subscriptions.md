# Thread subscriptions: design check for MATRIX-260 and MATRIX-261

Researched 2026-11-25 for MATRIX-263. Read-only research. No app code changed. No pin changed. The server was not touched. No authenticated endpoint was called.

Sources:

- matrix-rust-sdk at the pin, commit `5e0a2b834cb81195fba12e8dec93ca9acf816ab1` (the source of `matrix-rust-components-swift` 26.11.11). Upstream `main` was also read at `c08126df5d` (2026-11-25, 179 commits after the pin, newer than the 26.11.23 Swift release).
- Synapse at tag `v1.165.0`. That is the server's version: the public `/_matrix/federation/v1/version` of `davlin-matrix.exe.xyz` returns `{"server":{"name":"Synapse","version":"1.165.0"}}`.
- The server's public `/_matrix/client/versions` (2026-11-25): `org.matrix.msc4306: false`, `org.matrix.msc3773: false`, `org.matrix.msc3771: true`, `org.matrix.msc3440.stable: true`, versions up to `v1.17`.
- MSC4306 at `212345a7350d91eaeefc05e87f9e42039e3b4331` (PR 4306, still open). MSC3773 and MSC3771 on `main` of matrix-spec-proposals.
- ruma at `5133d4ec2846884b1d80a3769004524c34273c02` (the SDK's pin, with the `unstable-msc4306` and `unstable-msc4308` features).

Short names in the citations:

- `SDK/` = `https://github.com/matrix-org/matrix-rust-sdk/blob/5e0a2b834cb81195fba12e8dec93ca9acf816ab1/`
- `SYN/` = `https://github.com/element-hq/synapse/blob/v1.165.0/`
- `RUMA/` = `https://github.com/ruma/ruma/blob/5133d4ec2846884b1d80a3769004524c34273c02/`
- `MSC4306:n` = line n of `https://github.com/matrix-org/matrix-spec-proposals/blob/212345a7350d91eaeefc05e87f9e42039e3b4331/proposals/4306-thread-subscriptions.md`
- `FFI:n` = line n of `docs/ffi/matrix_sdk_ffi.swift` in this repo.

Tags:

- **[observed]**: read directly in source code, a spec text, or a changelog at the cited location.
- **[inferred]**: a conclusion from the observed facts. The source does not state it directly.
- **[rec]**: a recommendation.

## Summary

- **The server change is one key.** Synapse 1.165.0 has MSC4306 and MSC4308 behind `experimental_features.msc4306_enabled`. The minimum version is 1.139.0. No upgrade is necessary. **[observed]**
- **MATRIX-261 works on the pinned SDK, with three gaps.** The FFI can read and set a subscription. The server applies the push rules for every device, and MSC4308 syncs the state to other clients. The gaps: the Mac banners ignore the follow state, an unfollow does not hold in an All Messages room or a DM (SDK issue #6735), and a new mention always follows the thread again (MSC4306 design). **[observed]**
- **MATRIX-260 does not work on the pinned SDK or on upstream `main`.** The room's latest event accepts thread replies, and the FFI value has no event ID and no thread root, so the app cannot even see that a preview is a thread reply. With threads on, the SDK leaves every thread event out of the room counts, followed or not, mentions included. Per-thread counts exist in Rust but are not in the FFI and are not added to the room counts. **[observed]**
- **The count gap is an under-count, not an over-count.** Today a thread reply adds nothing to any count or badge, in any thread. A mention inside a thread adds nothing either. The missing half of MATRIX-260 is "count the threads he takes part in". **[observed]**
- **MSC3773 does nothing for Round.** Round uses sliding sync, Synapse sends 0 for the server counts there, and MSC3773 changes only sync v2. MSC3771 (threaded receipts) works today. **[observed]**
- **"Takes part" under MSC4306 is not Patrick's rule.** No party follows a thread for the root author, for a reply sent from another client or from Slack itself, or for a reply sent before the switch. And the SDK follows every thread with a new reply in an All Messages room or a DM. See the table in section 3. **[observed]**
- **On day one, unfollowed threads go quiet on the iPhone.** The default state is "not followed", and no subscription exists yet. In encrypted rooms (the Slack portals) the server cannot see a mention, so a mention in an unfollowed thread does not push. **[inferred]**

## 1. The room's latest event with threads on

**Answer:** the SDK does not skip thread replies, and it has no option to do so. A thread reply becomes the chat-list preview.

- The room's latest event comes from the room event cache. `RoomLatestEvents::update_with_event_cache` gets `event_cache.room(room_id)` (`SDK/crates/matrix-sdk/src/latest_events/room_latest_events.rs:153-215`). `Builder::new_remote` scans it from the end with `rfind_map_event_until_gap_by` (`SDK/crates/matrix-sdk/src/latest_events/latest_event/builder.rs:60-160`). **[observed]**
- The room event cache holds every event, in-thread events included. The read receipt code says so and filters them: "The room event cache contains all events, including in-thread events. We need to filter them!" (`SDK/crates/matrix-sdk/src/event_cache/caches/read_receipts.rs:347-352`). The latest event code does not filter them. **[observed]**
- `filter_any_message_like_event_content` (`builder.rs:752-812`) treats only `Relation::Replacement` (an edit) in a special way. Every other relation, `m.thread` included, goes to `filter_break()`, which accepts the event (`builder.rs:768-777`). Polls, stickers and call events are accepted with no relation check (`builder.rs:781-786`). The file has no thread check at all. **[observed]**
- The send queue path uses the same filter (`builder.rs:220-228`). So Patrick's own thread reply from Round also becomes the local preview. **[observed]**
- No option exists. `LatestEvent::new` builds the room value with no thread input. The per-thread value is a stub: `Some(_thread_id) => LatestEventValue::default()` (`SDK/crates/matrix-sdk/src/latest_events/latest_event/mod.rs:60-79`). Per-thread latest events are upstream issue #6013 (open). **[observed]**
- The app cannot detect a thread reply in the value. `LatestEventValue.remote(timestamp:sender:isOwn:profile:content:)` has no event ID (`FFI:38355-38362`). `content` is a `TimelineItemContent` whose `MsgLikeContent.threadRoot` (`FFI:24965-24978`) is always nil for a latest event: `TimelineItemContent::from_event` passes `thread_root: None` (`SDK/crates/matrix-sdk-ui/src/timeline/event_item/content/mod.rs:169-188`), and the local path calls `TimelineAction::from_content(content, None, None, None)` (`SDK/crates/matrix-sdk-ui/src/timeline/latest_event.rs:138`). **[observed]**
- Upstream `main` (`c08126df5d`) has the same `builder.rs` with no thread check. No PR for this change was found. **[observed]**

Choices:

1. **Upstream PR (recommended).** In `filter_timeline_event` (`builder.rs:713`), return `filter_continue()` for an event with a thread root when threading is on. Use `extract_thread_root` (`SDK/crates/matrix-sdk-common/src/serde_helpers.rs:71`), the same test as `RoomReadReceiptEventFilter`. In `new_local`, use `extract_thread_root_from_content` (`serde_helpers.rs:53`). Then a pin bump story (hard rule 6). The change is small. Element X uses the same code, so the maintainers can ask for it behind an option. **[rec]**
2. **A patched local build of `matrix-rust-components-swift`.** Possible, but it needs the Rust toolchain and an XCFramework build for macOS, iOS and the extension, and it replaces the exact-version pin with a local binary. Not recommended. **[rec]**
3. **An app rule over SDK data.** Not possible. The value has no event ID and no thread root. A hidden-thread timeline for each chat row would cost one timeline for each row and copy the SDK's latest-event logic (hard rule 1). **[rec]**

## 2. Unread counts with threads on

**Answer:** with threads on, the SDK leaves every in-thread event out of `numUnreadMessages`, `numUnreadNotifications` and `numUnreadMentions`. A subscription does not change this. The server counts are 0 under sliding sync, and MSC3773 has no effect on them.

Client counts:

- `RoomInfo.numUnreadMessages`, `numUnreadNotifications` and `numUnreadMentions` are `read_receipts.num_unread`, `num_notifications` and `num_mentions` (`SDK/crates/matrix-sdk-base/src/room/mod.rs:217-236`, FFI binding `SDK/bindings/matrix-sdk-ffi/src/room/room_info.rs:208-210`). `compute_unread_counts` makes them from the room linked chunk (`SDK/crates/matrix-sdk/src/event_cache/caches/room/state.rs:717-758`, `read_receipts.rs:594-670`). **[observed]**
- `RoomReadReceiptEventFilter::filter` drops every event with a thread root when threading is on (`read_receipts.rs:347-352`). The flag is `ThreadingSupport::Enabled { .. }`, with or without subscriptions (`SDK/crates/matrix-sdk/src/event_cache/caches/mod.rs:110-111`). The test `test_compute_unread_counts_with_threading_enabled` asserts 0 unread, 0 notifications and 0 mentions for in-thread events from anyone (`read_receipts.rs:1133-1196`). **[observed]**
- Result today: a thread reply adds nothing to the chat-list capsule, the Dock badge, the rail badges or the iOS badge. A mention inside a thread adds nothing too. **[observed]**
- The filter has no subscription input. **[observed]**
- Per-thread counts exist. Each thread cache keeps `ThreadInfo.read_receipts` (`SDK/crates/matrix-sdk/src/event_cache/caches/thread/state.rs:506-546`, `SDK/crates/matrix-sdk-base/src/event_cache/thread.rs:24-42`). The SDK makes a thread cache for each thread that gets events from sync (`caches/mod.rs:349-385`). The Rust API is `ThreadEventCache::num_unread_*` (`caches/thread/mod.rs:176-198`) and `EventCache::thread_info` (`SDK/crates/matrix-sdk/src/event_cache/mod.rs:519-538`). The FFI has none of them. **[observed]**
- Upstream PRs #7507 and #7509 tried to expose and list these counts. Both were closed unmerged on 2026-11-23. The maintainer said the per-thread counts already exist, and the author found no bulk API. **[observed]**
- The per-thread counts match only threaded receipts (`ReceiptThread::Thread(id)`, `read_receipts.rs:420-425`). MSC3771 says an unthreaded receipt clears notifications across all threads. So the chat list's Mark as Read (`Room.markAsRead(receiptType: .read)`, an unthreaded receipt) does not clear the SDK's per-thread counts. PR #7107, which tried to fix this, was closed unmerged. **[observed]**
- The push actions that the counts read come from the base sync processing. Its push context has no thread subscription check (`SDK/crates/matrix-sdk-base/src/response_processors/timeline.rs:53` and `223-257`). Without the check, ruma's condition is false (`RUMA/crates/ruma-common/src/push/condition.rs:450-480`), so both MSC4306 rules are skipped and the room rule decides. **[observed]**

Server counts:

- `RoomInfo.notificationCount` and `highlightCount` are the sliding sync `unread_notifications` (`SDK/crates/matrix-sdk-base/src/response_processors/room/msc4186/mod.rs:170-171`). **[observed]**
- Synapse's sliding sync sends 0 for both: "TODO: These are just dummy values" (`SYN/synapse/handlers/sliding_sync/__init__.py:1519-1523`). The app does not read them (`ChatList+SDK.swift:231-240`, `DockBadge.swift`). **[observed]**

MSC3773:

- MSC3773 changes only the sync v2 response. With the filter key `unread_thread_notifications: true`, `unread_notifications` leaves out thread events, and per-thread counts go in a new `unread_thread_notifications` object. **[observed]**
- In Synapse, `msc3773_enabled` only adds the unstable-prefixed filter and response keys (`SYN/synapse/api/filtering.py:347-356`, `SYN/synapse/rest/client/sync.py:715-720`). The stable keys work without it. **[observed]**
- Sliding sync (MSC4186) has no per-thread counts, and the SDK has no MSC3773 code. Do not set `msc3773_enabled`: it changes nothing for Round. **[observed]** **[rec]**

## 3. MSC4306 on Synapse, and who subscribes

**Synapse version.** MSC4306 came in three steps (`SYN/CHANGES.md`):

- 1.135.0 (2025-08-01): "experimental and incomplete support" (#18674).
- 1.136.0 (2025-08-12): the endpoints (#18726), the push rules (#18762), the `/versions` flag (#18722), and conflict prevention for automatic subscriptions (#18756).
- 1.139.0 (2025-09-30): the MSC4308 sliding sync extension (#18695), and the push rules of the newer draft with the `postcontent` kind (#18846).

The minimum for this plan is **1.139.0**, because the SDK uses the MSC4308 extension and the rules of the newer draft. The server runs 1.165.0. **[observed]**

**Config keys.**

- `experimental_features: { msc4306_enabled: true }` (`SYN/synapse/config/experimental.py:299-301`). The comment says it also enables MSC4308. **[observed]**
- It sets `org.matrix.msc4306` in `/versions` (`SYN/rust/src/handlers/versions.rs:333`). It registers `/_matrix/client/unstable/io.element.msc4306/rooms/{roomId}/thread/{eventId}/subscription` and `/_matrix/client/unstable/io.element.msc4308/thread_subscriptions` (`SYN/synapse/rest/client/thread_subscriptions.py:36-42`, `121-125`, `244-247`). It turns on the sliding sync extension (`SYN/synapse/handlers/sliding_sync/extensions.py:91`) and the push rules (section 4). **[observed]**
- `msc3773_enabled`: not useful (section 2). **[observed]**

**What the server does by itself.** Nothing automatic. Only the REST servlet writes a subscription (`SYN/synapse/handlers/thread_subscriptions.py:59-147`). The server:

- checks that the root event exists and that the user can see it. It does not check that the root has replies (`:88-98`). **[observed]**
- checks that an automatic cause event is in the thread, else 400 `IO.ELEMENT.MSC4306.M_NOT_IN_THREAD` (`:100-116`). **[observed]**
- refuses an automatic subscription whose cause event is older than an unsubscription, with 409 `IO.ELEMENT.MSC4306.M_CONFLICTING_UNSUBSCRIPTION` (`:131-136`). **[observed]**
- wakes the user's sync streams after a change (`:138-145`). **[observed]**

MSC4306 agrees: "The server does not perform this action on the client's behalf" (`MSC4306:134`). The client must subscribe when the user sends in a thread (a manual subscription, from the sending client only, `MSC4306:122-125`) and when the user is mentioned (an automatic one, `MSC4306:130-150`). **[observed]**

**What the SDK does at `5e0a2b8`.** Both, by itself, but only when `Client::enabled_thread_subscriptions()` is true: the client flag (set by `threadsEnabled(enabled: true, threadSubscriptions: true)`, `MatrixClient+Session.swift:34`) and `org.matrix.msc4306` in the server's features (`SDK/crates/matrix-sdk/src/client/mod.rs:4084-4101`). Today the server says false, so the SDK does nothing, and no subscription exists. **[observed]**

- **Own send.** The thread subscriber task watches the send queue. When an event with a thread relation is sent, it calls `subscribe_thread_if_needed(root, Some(sent_event_id))` (`SDK/crates/matrix-sdk/src/event_cache/tasks.rs:257-347`, call at `:343`). That is an automatic subscription with his own event as the cause, not the manual one of the MSC. So a reply after an unfollow follows the thread again, because the cause is newer than the unfollow. Every Round send goes through the send queue (`Timeline.send`, `Timeline.sendReply`). **[observed]**
- **Mention.** For new events in a thread cache, the task evaluates the push rules with `with_thread_subscriptions = false` and subscribes if any action notifies (`tasks.rs:358-436`, `:396`, `:417`). With no thread check, the room rule decides. In an All Messages room, and in a DM (`.m.rule.room_one_to_one`), every reply notifies. So the SDK follows every thread that gets a new reply while a client runs, and an unfollow there does not hold. Upstream issue #6735 (open since 2026-07) reports exactly this. Upstream `main` still has line 396. **[observed]**
- **Back-pagination.** A thread that loads older events (the thread panel) runs the same check (`SDK/crates/matrix-sdk/tests/integration/event_cache/threads/mod.rs:515`). **[observed]**
- **Sync of the state.** The room list asks for the MSC4308 extension (limit 10) when the feature is on (`SDK/crates/matrix-sdk-ui/src/room_list_service/mod.rs:188-197`). Changes go to the state store. **[observed]**
- **FFI.** `setThreadSubscription(threadRootEventId:subscribed: true)` is a manual subscription, `false` is an unsubscription (`SDK/bindings/matrix-sdk-ffi/src/room/mod.rs:1359-1373`, `FFI:11017`). `fetchThreadSubscription(threadRootEventId:)` sends a GET on each call and updates the store (`SDK/crates/matrix-sdk/src/room/mod.rs:4657-4701`, `FFI:10620`). It returns nil if there is no subscription, the event is unknown, or the server answers 404 (a server without MSC4306). `ThreadSubscription.automatic` (`FFI:30682-30687`) is true for both an own-send follow and a mention follow. **[observed]**

**Patrick's rule against MSC4306 and the SDK:**

| Case | Patrick's rule | MSC4306 + SDK `5e0a2b8` |
|---|---|---|
| He replied in the thread from Round | follows | follows (automatic, cause = his reply) |
| He replied from Slack itself, Beeper, or Element | follows | no (`MSC4306:125` forbids it for other clients) |
| He replied before the server switch | follows | no |
| The root is his message | follows | no (no party does this) |
| He is mentioned in the thread | not stated | follows |
| Any reply in an All Messages room or a DM | no | follows (#6735) |

## 4. Push

**Condition.** `io.element.msc4306.thread_subscription` with `subscribed: bool` (`MSC4306:281-293`, `SYN/rust/src/push/mod.rs:370-373`, `RUMA/crates/ruma-common/src/push/condition.rs:68`). It is true only for an event in a thread. **[observed]**

**Default rules.** Two rules of the new `postcontent` kind, which runs after `content` and before `room` (`SYN/rust/src/push/base_rules.rs:335-356`):

- `.io.element.msc4306.rule.unsubscribed_thread`: condition `subscribed: false`, actions `[]` (no notification).
- `.io.element.msc4306.rule.subscribed_thread`: condition `subscribed: true`, actions `notify` and sound.

**[observed]**

**Does Synapse evaluate it?** Yes, when the flag is on. It hides the two rules when the flag is off (`SYN/rust/src/push/mod.rs:643-645`). It evaluates the condition only when the flag is on (`SYN/rust/src/push/evaluator.rs:422-428`). It reads the local subscribers of the thread from the database for each thread event (`SYN/synapse/push/bulk_push_rule_evaluator.py:484-516`). **[observed]**

**Rule order.** override (mentions, `@room`, a muted room) → content (user name, keywords) → postcontent (the two thread rules) → room (All Messages, Mentions and Keywords) → sender → underride (DM, encrypted, message). The SDK writes Mute as an override rule and the two other modes as room rules (`SDK/crates/matrix-sdk/src/notification_settings/mod.rs:321-334`). **[observed]**

**Answer: yes.** With the flag on, an unfollowed thread stops phone push with no client change, because Synapse decides the push for each event and each user. The details:

- Every thread starts unfollowed (`MSC4306:29`). On day one, all thread replies stop pushing, except mention and keyword matches that the server can see. **[inferred]**
- In an encrypted room the server cannot see `m.mentions` or the body. A mention in an unfollowed thread does not push. The Slack portals are encrypted (bridge default). A Round client that syncs the mention follows the thread, so later replies push, but not the mention itself. **[inferred]**
- A followed thread pushes in a Mentions and Keywords room, because postcontent runs before the room rule. It does not push in a muted room, because the mute is an override rule. MSC4306 wants it to notify in a muted room too (`MSC4306:177`). **[inferred]**
- The iPhone extension honors the follow state. `NotificationClient` gets the push actions through `Room::push_context()` (`SDK/crates/matrix-sdk-ui/src/notification_client.rs:336`, `:888`), which adds the thread check when the feature is on (`SDK/crates/matrix-sdk/src/room/mod.rs:3697-3755`). The SDK tests both cases (`SDK/crates/matrix-sdk-ui/tests/integration/notification_client.rs:96`, `:202`). **[observed]**
- The Mac banners do not honor it. The Mac uses `registerNotificationHandler` (`MatrixClient+Sync.swift:70`, `FFI:1408`). That handler gets the notifications of the base sync processing (`SDK/crates/matrix-sdk-base/src/response_processors/notification.rs:59-80`), whose push context has no thread check (section 2). So an unfollowed thread reply still shows a banner by the room's mode, and a followed thread in a Mentions room shows none. **[observed]**
- Element Web, Element X and any other client of the account get the same server push behavior. **[inferred]**

## 5. Plan

### What the app does, and what must come from elsewhere

| Need | Pinned SDK | Server | App |
|---|---|---|---|
| Thread replies not in previews (260) | no: needs upstream change A | nothing | nothing (no data to work with) |
| Followed threads add to counts (260) | no: needs upstream change B | nothing | read the new counts after the bump |
| Follow and unfollow (261) | yes: `fetchThreadSubscription`, `setThreadSubscription` | `msc4306_enabled` (264) | the control and its state |
| Follow state on every device (261) | yes: MSC4308 extension | `msc4306_enabled` | nothing |
| No phone push for an unfollowed thread (261) | yes: server rules, and the iOS notification extension honors them | `msc4306_enabled` | nothing |
| No Mac banner for an unfollowed thread (261) | no: needs upstream change C | nothing | stopgap filter (decision) |
| Unfollow holds in All Messages rooms and DMs (261) | no: needs upstream change D (#6735) | nothing | nothing |

Upstream changes (none exists today, on `5e0a2b8` or on `main` `c08126df5d`):

- **A.** The room's latest event skips in-thread events when threading is on (section 1).
- **B.** The room counts include the threads that the user follows, from `ThreadInfo.read_receipts`, and an unthreaded receipt clears thread counts as MSC3771 says. Expose them in `RoomInfo`.
- **C.** The base sync push context gets the thread subscription check from the state store (`get_push_room_context`, `SDK/crates/matrix-sdk-base/src/response_processors/timeline.rs:223-257`). This fixes the Mac banners and the push actions that B counts.
- **D.** Auto-follow on mention uses a real mention, or evaluates with the thread rules, so that All Messages does not follow every thread (#6735). It waits for a clarification of MSC4306, which the issue raised on the MSC PR.

### What Patrick sees after each step

| Step | Chat-list preview | Capsule, Dock and iOS badge | iPhone push for a thread reply | Mac banner for a thread reply | Follow state |
|---|---|---|---|---|---|
| Today (SDK 26.11.11, flag off) | can be a thread reply | thread replies never count, mentions in threads included | as any message in that room | as any message in that room | does not exist |
| After MATRIX-264 (flag on, app relaunched after the SDK's `/versions` cache refresh) | no change | no change | only followed threads push, plus mentions and keywords the server can see. Nothing is followed on day one. Encrypted rooms: a mention in an unfollowed thread is silent | no change | the SDK follows a thread when he replies from Round, when he is mentioned, and on every reply in an All Messages room or a DM. Synced to his other clients |
| After MATRIX-261 (Follow and Unfollow control) | no change | no change | Unfollow stops push for that thread on every device. His next reply or a new mention follows it again. In an All Messages room or a DM, the next reply follows it again | with the stopgap filter: an unfollowed thread reply shows no banner unless it mentions him. Without it: no change | he sees and sets it in the Mac thread panel and the iOS thread screen |
| After MATRIX-260 (pin bump with A, B, C, D) | never a thread reply | followed threads count (messages, notifications, mentions). Unfollowed threads do not | as after 261, and an unfollow holds in All Messages rooms | follows the same rules as the phone (no stopgap) | as after 261 |

### Order

1. MATRIX-261 app code. It can land before the server flag, because the control handles the error of a server without MSC4306.
2. MATRIX-264, the server flag, in the same session as the 261 smoke test. Patrick can then follow important threads on day one.
3. MATRIX-261 smoke test on the dev account.
4. MATRIX-260: upstream changes first, then a pin bump story, then the app change.

### MATRIX-264: the server change

Do this when Patrick is present (the SSH key needs Touch ID). Use the conf.d pattern with the health check and the automatic rollback.

1. Find an existing block. Run `sudo grep -rn '^experimental_features' /etc/matrix-synapse/homeserver.yaml /etc/matrix-synapse/conf.d/`.
2. If no file has the key, write `/etc/matrix-synapse/conf.d/thread-subscriptions.yaml`:

   ```yaml
   experimental_features:
     msc4306_enabled: true
   ```

   If a file has the key, add `msc4306_enabled: true` under that block. Do not write a second top-level `experimental_features` key. Synapse merges config files shallowly, so a later file replaces the whole block (`SYN/synapse/config/_base.py:975-997`).
3. Restart: `sudo systemctl restart matrix-synapse`.
4. Check:
   - `curl -s https://davlin-matrix.exe.xyz/_matrix/client/versions | jq '.unstable_features["org.matrix.msc4306"]'` returns `true`.
   - `curl -s -o /dev/null -w '%{http_code}\n' https://davlin-matrix.exe.xyz/_matrix/client/unstable/io.element.msc4308/thread_subscriptions` returns `401` (missing token). Before the change it returns `404` (unrecognized request).
   - `sudo journalctl -u matrix-synapse --since '5 min ago' | grep -iE 'error|msc4306'` shows no error.
   - Optional, dev account only: `GET /_matrix/client/v3/pushrules/` shows `global.postcontent` with the two `.io.element.msc4306.rule.*` rules.
5. Do not set `msc3773_enabled`. Do not upgrade: 1.165.0 is above the 1.139.0 minimum.
6. Rollback: remove the file and restart. Stored subscriptions stay in the database, unused.
7. App pickup. The SDK keeps `/versions` for 24 hours (`SDK/crates/matrix-sdk-common/src/ttl.rs:45`) and refreshes it in the background after that (`SDK/crates/matrix-sdk/src/client/mod.rs:2773-2781`). The thread subscriber task and the room list's MSC4308 extension read the flag once, at start (`tasks.rs:187-201`, `room_list_service/mod.rs:188-197`). Without help, the app uses MSC4306 from the first launch after the refresh: up to 24 hours and a relaunch. MATRIX-261 step 4 removes the wait.

### MATRIX-261: Follow and Unfollow

1. Core: a small type over the two FFI calls, with these exact signatures:
   - `Room.fetchThreadSubscription(threadRootEventId: String) async throws -> ThreadSubscription?` (`FFI:10620`)
   - `Room.setThreadSubscription(threadRootEventId: String, subscribed: Bool) async throws` (`FFI:11017`)
   - `ThreadSubscription.automatic: Bool` (`FFI:30682-30687`)

   Map nil to "not followed" and a value to "followed". Do not show "because you were mentioned" for `automatic`: it is also true after his own reply. On an error (for example `M_UNRECOGNIZED` before the flag), hide the control.
2. UI: one button in the Mac thread panel header and in the iOS thread screen toolbar: "Follow Thread" or "Unfollow Thread" (bell and bell.slash). Both places are navigation chrome. Default wording is Slack's, cheap to change. A context menu item on the Threads pane rows is optional.
3. Read the state when the thread opens and after each set. The FFI has no listener for subscription changes. MSC4308 updates the SDK store, but `fetchThreadSubscription` always asks the server.
4. Call `Client.resetSupportedVersions() async throws` (`FFI:1421`) one time after this update (a UserDefaults flag), so the SDK sees MSC4306 at the next launch with no 24 hour wait.
5. **Decision for Patrick: Mac banners.** (a) A stopgap app rule, with the MATRIX-77 label mute as precedent: no banner for a `NotificationItem` with a `threadId` (`FFI:25250`) when `fetchThreadSubscription` returns nil and `hasMention` (`FFI:25249`) is not true. Cost: one GET for each such banner. It is close to the server's `unsubscribed_thread` rule, but a keyword match with no highlight is lost. Remove it when upstream change C lands. (b) Wait for C. **[rec]** (a), with a contract §11 row, because the phone and the Mac otherwise disagree.
6. **Decision for Patrick: the root-author rule.** (a) Accept the MSC4306 meaning: a reply from Round or a mention follows a thread, and Follow is the manual path. (b) The app follows each top-level message he sends from Round, after the send completes. Synapse accepts a subscription to a root with no replies (section 3). Cost: one PUT for each message, and it does not cover a post made in Slack itself. **[rec]** (a).
7. Record the known limits in the §11 row: a new mention or his own reply follows the thread again (`MSC4306:257`, no permanent mute). In an All Messages room or a DM, the next reply follows it again (#6735). The workaround is to set that room to Mentions and Keywords.
8. Tests: unit tests for the state mapping, snapshots of the header in both states. Smoke test on the dev account after MATRIX-264: unfollow on the Mac, reply from a second account, make sure that the iPhone gets no push, and make sure that the iOS thread screen shows "Follow Thread" after a reopen.

### MATRIX-260: previews and counts

1. Upstream PR for change A in `SDK/crates/matrix-sdk/src/latest_events/latest_event/builder.rs` (`filter_timeline_event` at `:713`, `new_local` at `:220-228`), with tests in the same file and in `crates/matrix-sdk/tests/integration/latest_event.rs`, and a changelog line. Link issue #6013.
2. Upstream issue first, then a PR, for change B. Ask the maintainers before code: on 2026-11-23 they closed two PRs in this area as duplicates (#7507, #7509), and they changed the thread receipt code the same day (`311b34fdbd`, `597a1eb158`, `b0eb8bd373`).
3. Upstream PR for change C in `get_push_room_context`.
4. Follow issue #6735 for change D. It waits for the MSC.
5. A pin bump story (hard rule 6) to the first `matrix-rust-components-swift` release that has A and B. Releases came on 2026-10-27, 2026-11-11 and 2026-11-23. After the bump the app needs no change for previews. For counts, it needs no change if B adds the thread counts to `numUnread*`, else new fields in `ChatListUnread`, `UnreadChatState` and `DockBadge`.
6. With B: the iOS thread screen sends a threaded receipt (`Timeline.markAsRead(receiptType: .read)` on the thread timeline, `FFI:19729`), and the Mac panel is checked to send one (see "Other findings"). Thread counts clear only with threaded receipts.
7. Not recommended: an app workaround for either part (section 1, choice 3, and hard rule 1).

## Other findings

- The Mac thread panel calls `markAsRead(receiptType: .read)` on the thread timeline through `ChatView` → `ChatJoinedRoom` (`Mactrix/Views/ChatView/ChatView.swift:91-102`, `Mactrix/Views/Inspector/InspectorScreen.swift:45`). The SDK sends a threaded receipt for a thread focus (`FFI:19714-19729`). The 2026-11-25 contract row says the panel sends no receipts. One of them is out of date. Check it before change B, because thread counts clear only with threaded receipts. **[observed]**
- On panel close, `ChatJoinedRoom` calls `markAsRead(receiptType: .fullyRead)` on the thread timeline (`ChatView.swift:103-112`). The FFI doc says a fully-read receipt is unthreaded and can target an event in a thread. So closing a thread panel can move the room's fully-read marker to a thread reply. Not checked on the dev account. **[inferred]**
- The iOS thread screen sends no read receipts: `TimelineScreen` sends them only for a room timeline (`isRoomTimeline`, `MactrixiOS/Timeline/TimelineScreen.swift:144-165`). So on iOS, the per-thread counts of change B never clear. MATRIX-260 must add a threaded receipt there. **[observed]**
