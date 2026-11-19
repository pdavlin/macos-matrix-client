# Send Later: infrastructure and design

Researched 2026-11-19 for MATRIX-210. Research only. No app code changed. No pin changed. The server was not touched by this spike.

Tags:

- **[observed]**: read directly in source code, a spec text, a changelog, or a shipped bundle at the cited location.
- **[inferred]**: a conclusion from the observed facts. The source does not state it directly.
- **[rec]**: a recommendation for Mactrix.

## Result

- The pinned SDK (`matrix-rust-components-swift` 26.04.01) has no client call for a delayed send. **[observed]**
- The first release with a client delayed-send call is **26.11.11** (2026-11-11). It adds `Room.sendDelayedEvent`, `Room.sendDelayedStateEvent`, and `Client.updateDelayedEvent`. **[observed]**
- The 26.11.11 SDK uses the new dedicated MSC4140 endpoint. Synapse adds that endpoint in **1.164.0**. Our server runs 1.159.0, so the SDK call will fail against it today. **[observed]** (the failure mode is [inferred], see below)
- Neither the SDK nor the merged MSC gives a client a list of its pending delayed events. Mactrix must keep its own list. **[observed]**
- Recommendation: option A (MSC4140 through the SDK). It needs a Synapse upgrade to 1.164.0 or later and an SDK bump story first. **[rec]**

## 1. The pinned SDK

Pin: `matrix-rust-components-swift` 26.04.01, revision `2916f3f9`, upstream `matrix-rust-sdk` commit `388ced09`. Source: `MactrixLibrary/Package.swift` line 27, `Mactrix.xcodeproj/project.pbxproj` line 1065, `docs/ffi/README.md`. **[observed]**

FFI (`docs/ffi/matrix_sdk_ffi.swift`, narrow grep for `delay`, `msc4140`, `scheduled`):

- `WidgetCapabilities.sendDelayedEvent: Bool` and `updateDelayedEvent: Bool` at lines 25849 to 25853. These are capability flags for a widget (Element Call). They are not client calls. **[observed]**
- `Room.sendRaw(eventType: String, content: String) async throws` at line 8240 has no delay parameter. **[observed]**
- No other delay match is a send path. **[observed]**

Rust `matrix-sdk` at `388ced09`:

- `crates/matrix-sdk/src/room/futures.rs` and `room/mod.rs` have no delay code. **[observed]**
- The only delayed send is `pub(crate) fn send` in `crates/matrix-sdk/src/widget/matrix.rs` lines 152 to 201. It builds a raw ruma `delayed_message_event::unstable::Request` and calls `client.send(r)`. **[observed]**
- That widget path does not encrypt. The non-delayed branch calls `room.send_raw`, which encrypts. The delayed branch skips it. The author of upstream PR #6973 states this bug ("It was not encrypting delayed events in encrypted rooms"). **[observed]**
- The widget path is `pub(crate)` and the FFI does not export it. **[observed]**

The SPM checkout under `build/DerivedData/SourcePackages/checkouts/` was not read. The sandbox denied access to it. The checkout holds only the Swift wrapper (a copy is in `docs/ffi/`) and a binary XCFramework, so it has no Rust source to read. The Rust source was read from GitHub at the pinned commit. **[observed]** (checkout contents [inferred] from `docs/ffi/README.md`)

## 2. Newer SDK releases

`matrix-rust-components-swift` releases after the pin: 26.05.13, 26.06.06, 26.07.24, 26.08.10, 26.08.11, 26.09.07, 26.10.02, 26.10.27, 26.11.11. **[observed]** (`gh release list`)

- Upstream PR [matrix-rust-sdk#6973](https://github.com/matrix-org/matrix-rust-sdk/pull/6973) "Add support for delayed event (MSC4140)" merged 2026-11-10 as `96c2bd22`. **[observed]**
- Release 26.11.11 builds from `matrix-rust-sdk` `5e0a2b83`, which is 7 commits ahead of `96c2bd22`. **[observed]**
- The 26.11.11 `matrix_sdk_ffi.swift` has the calls. 26.10.27 does not. **[observed]** (grep of both release files)

Exact signatures in 26.11.11 `Sources/MatrixRustSDK/matrix_sdk_ffi.swift`: **[observed]**

```swift
// Room, line 11230 (protocol), 13427 (open func)
func sendDelayedEvent(eventType: String, content: String, delayMs: UInt64,
                      requestConfigOverride: RequestConfigOverride?) async throws -> String

// Room, line 11257
func sendDelayedStateEvent(eventType: String, stateKey: String, content: String, delayMs: UInt64,
                           requestConfigOverride: RequestConfigOverride?) async throws -> String

// Room, line 11290 (feature unstable-msc4354, sticky events, not needed here)
func sendStickyDelayedEvent(eventType: String, content: String, delayMs: UInt64, stickyDurationMs: UInt64,
                            requestConfigOverride: RequestConfigOverride?) async throws -> String

// Client, line 1765 (protocol), 4331 (open func)
func updateDelayedEvent(delayId: String, action: DelayedEventUpdateAction,
                        requestConfigOverride: RequestConfigOverride?) async throws

// line 34843
public enum DelayedEventUpdateAction { case cancel, restart, send }
```

The `String` return value is the `delay_id`. The `open func` forms give `requestConfigOverride` a default of `nil`. **[observed]**

What 26.11.11 does not have: **[observed]**

- No call to get one delayed event or to list delayed events. Ruma has `get_delayed_event` and `get_all_delayed_events`, but the FFI does not export them.
- No `delay_id` field on a timeline item.
- No delayed-event value on `HomeserverCapabilities`. The app cannot read `max_delay_ms` or `max_scheduled` through the FFI.

Upstream source on `main` (same as 26.11.11 for these files):

- [bindings/matrix-sdk-ffi/src/room/delayed_events.rs](https://github.com/matrix-org/matrix-rust-sdk/blob/main/bindings/matrix-sdk-ffi/src/room/delayed_events.rs)
- [bindings/matrix-sdk-ffi/src/client.rs](https://github.com/matrix-org/matrix-rust-sdk/blob/main/bindings/matrix-sdk-ffi/src/client.rs) (`update_delayed_event`, `DelayedEventUpdateAction`)
- [crates/matrix-sdk/src/room/futures.rs](https://github.com/matrix-org/matrix-rust-sdk/blob/main/crates/matrix-sdk/src/room/futures.rs) (`into_delayed`, `prepare_message_like_event`)
- [26.11.11 release](https://github.com/matrix-org/matrix-rust-components-swift/releases/tag/26.11.11)

How the 26.11.11 call works: **[observed]**

- `sendDelayedEvent` calls `room.send_raw(...).into_delayed(delay)`. It runs the same `prepare_message_like_event` as a normal send. That function calls `ensure_room_encryption_ready` and `encrypt_room_event_raw` if the room is encrypted (`futures.rs` lines 400 to 428).
- It then sends ruma `send_delayed_event::msc4140::Request`. The path is `PUT /_matrix/client/unstable/org.matrix.msc4140/rooms/{roomId}/delayed_event/{eventType}/{txnId}` (ruma rev `5133d4ec`, `send_delayed_event.rs` line 27).
- `updateDelayedEvent` sends `POST /_matrix/client/unstable/org.matrix.msc4140/delayed_events/{delay_id}/{action}` (ruma `update_delayed_event::msc4140_v2`).
- The delayed send does not go through the SDK send queue. So the timeline shows no local echo for it. **[inferred]** from `room.client.send(request)` in `futures.rs`.
- The content is a raw JSON string. The app must make the `m.room.message` content JSON itself (body, `format`, `formatted_body`, `m.mentions`, `m.relates_to` for a reply). **[observed]** (the signature) The normal send path gives the app an opaque `RoomMessageEventContentWithoutRelation`. Whether the FFI can turn that into JSON was not checked. **[inferred]** risk, check it in the SDK bump story.

## 3. MSC4140 and Synapse

MSC4140 merged into the spec proposals repo on 2026-09-08 (label `matrix-2.0`). Source: [proposals/4140-delayed-events-futures.md](https://github.com/matrix-org/matrix-spec-proposals/blob/main/proposals/4140-delayed-events-futures.md). **[observed]**

### Send call

- `PUT /_matrix/client/v3/rooms/{roomId}/delayed_event/{eventType}/{txnId}`. Unstable: `/_matrix/client/unstable/org.matrix.msc4140/...`. **[observed]**
- Body: `delay_ms` (required, positive integer), `state_key` (state events only), `content` (required). **[observed]**
- Response: `{"delay_id": "..."}`. No `event_id`, because the server cannot make the event ID before the send. **[observed]**
- The server must not send before the time. It may send up to 30 seconds after the time. **[observed]**
- The server checks the event is well formed at schedule time. It checks auth at send time, against the room state at send time. **[observed]**

### Management actions

`POST /_matrix/client/v1/delayed_events/{delay_id}/{action}`, body `{}`. **[observed]**

- `send`: send now.
- `cancel`: never send.
- `restart`: set the send time to now plus the original `delay_ms`. This does not set a new time. **[observed]**
- Unknown `delay_id`: 404 `M_NOT_FOUND`. A conflict with a finalised event (for example `cancel` on a sent event): 409. A repeat of the same outcome: 200. **[observed]**

There is no edit action. Edit is cancel plus a new schedule, with a new `delay_id`. **[inferred]**

### Get and list

- `GET /_matrix/client/v1/delayed_events/{delay_id}` returns one event: `room_id`, `type`, `delay_ms`, `delayed_since_ts`, `content`, and `finalised` (`event_id` or `error`, and `finalised_ts`). **[observed]**
- The server keeps finalised records for a limited time. The MSC suggests 7 days or 1000 events per user. **[observed]**
- The merged MSC has no list endpoint. It moved bulk listing to [MSC4486](https://github.com/matrix-org/matrix-spec-proposals/pull/4486) "Listing delayed events with filtering & pagination". MSC4486 is open, label `needs-implementation`. **[observed]**
- Synapse still serves an unstable list: `GET /_matrix/client/unstable/org.matrix.msc4140/delayed_events` returns all of the user's delayed events. It is in 1.159.0 and in `develop` (`synapse/rest/client/delayed_events.py`, `DelayedEventsServlet`). **[observed]** The SDK FFI does not call it. **[observed]**
- After the send, the room event carries `delay_id` in `unsigned` (unstable key `org.matrix.msc4140.delay_id`), only for the sender. It has no `transaction_id`. Synapse added this in 1.150.0. **[observed]**

### Limits

- `max_event_delay_duration`: the maximum delay. If unset, delayed events are off. Default `null`. Source: [Synapse config docs](https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html#max_event_delay_duration). Our server now has `365d` (orchestrator, 2026-11-19). **[observed]**
- Per-user count limit: `experimental_features.msc4140_max_delayed_events_per_user`, default 100 (Synapse 1.159.0 `synapse/config/server.py` line 976). Over the limit: 429 `M_LIMIT_EXCEEDED` with `Retry-After`. **[observed]**
- Too long a delay: 400 `M_DELAY_TOO_LARGE` (unstable `ORG.MATRIX.MSC4140_DELAY_TOO_LARGE`). **[observed]**
- Capability: `org.matrix.msc4140.delayed_events` with `max_delay_ms` and `max_scheduled` (Synapse 1.159.0 `capabilities.py` line 112). **[observed]**
- Scheduling uses the `rc_message` rate limit. Management uses `rc_delayed_event_mgmt`. A send at the scheduled time that hits a rate limit is not retried. It becomes a finalised event with `error`. **[observed]**
- Account deactivation cancels the user's delayed events (Synapse 1.163.0). **[observed]**

### Synapse version matters

Synapse 1.159.0 (2026-08-18) serves only the old shape: **[observed]** (`v1.159.0` `synapse/rest/client/room.py` line 529 and `delayed_events.py`)

- Schedule: the normal `PUT .../send/{eventType}/{txnId}` with the query parameter `?org.matrix.msc4140.delay=<ms>`.
- Manage: `POST .../org.matrix.msc4140/delayed_events/{delay_id}` (action in body) and `.../{delay_id}/cancel|restart|send`.
- List: `GET .../org.matrix.msc4140/delayed_events`.
- No `.../rooms/{roomId}/delayed_event/...` route. No single GET (added in 1.161.0).

Synapse changes by version (from `CHANGES.md` on `develop`): **[observed]**

| Version | MSC4140 change |
|---|---|
| 1.157.0 | Per-user count limit. New error format. |
| 1.161.0 | `GET /delayed_events/{delay_id}`. |
| 1.163.0 | Cancel on account deactivation. |
| 1.164.0 | Dedicated `PUT .../delayed_event/...` endpoint (#19354). Management endpoints need auth. Reject a schedule the sender could not send now. |
| 1.165.0 | Sticky delayed event update. Current stable release (2026-11-10). |

The 26.11.11 SDK calls the dedicated endpoint. On 1.159.0 that route does not exist, so the call fails with an error (likely 404 `M_UNRECOGNIZED`). It does not send the message early. **[inferred]** The upstream PR notes the opposite risk for the old query-parameter shape: a server that ignores the parameter sends the event at once. The dedicated endpoint removes that risk. **[observed]** (PR #6973 body)

Prerequisite for option A: upgrade Synapse to 1.164.0 or later. **[rec]**

## 4. Encryption

The Slack bridge rooms are encrypted (orchestrator, 2026-11-19). So the client must encrypt the event when it schedules it. The server stores the ciphertext and sends it later. **[observed]** (SDK doc comment on `into_delayed`)

### At schedule time

- The SDK runs the normal prepare path. It makes sure an outbound megolm session exists, shares the room key over to-device messages to the devices of the current members, and encrypts the content with that session. **[observed]** (`futures.rs` lines 400 to 428, `ensure_room_encryption_ready`)
- The server gets `m.room.encrypted` content. It cannot read the text. **[inferred]**
- The SDK doc says: "a member joining before the delay elapses won't be able to decrypt the event, and restarting the delay does not re-encrypt it." **[observed]**

### Failure modes

| Case | Result | Tag |
|---|---|---|
| A new member joins before the send | The member never got the key for that megolm index. A later key share starts at a later index. The member sees an unable-to-decrypt (UTD) message. | SDK doc [observed], mechanism [inferred] |
| A current member adds a new device before the send | Same as a new member, for that device. | [inferred] |
| A member leaves before the send | The server builds the event from the room state at send time, so it does not deliver the event to that member. The member's device still holds the key. | [observed] (MSC auth rule), key part [inferred] |
| Megolm session rotates (time, count, or a member leaves) before the send | No effect on this event. Rotation changes only the next outbound session. The ciphertext uses the old session, and recipients keep that key. | [inferred] |
| The sender device logs out before the send | Synapse still sends. It stores the scheduling `device_id` and builds a requester from it with no check that the device exists (`handlers/delayed_events.py` lines 564 to 571). Recipients hold the key and can decrypt. They may see a warning that the sender device is unknown or deleted. | send [observed], decrypt and warning [inferred] |
| Mactrix logs in again as a new device | The new device lacks the outbound session. It may fail to show its own scheduled message after the send, unless key backup holds the session. | [inferred] |
| Account deactivated | Synapse cancels all pending delayed events (1.163.0+). | [observed] |
| The user leaves the room or loses power before the send | The send fails at send time. The record becomes finalised with `error`. The app learns this only through a GET, which the FFI does not have. | [observed] (MSC), FFI gap [observed] |

### The mautrix-slack bridge

- The bridge bot device is a room member at schedule time. So it gets the room key then, like any other member device. **[inferred]**
- At send time, the bridge gets the `m.room.encrypted` event in an appservice transaction. It decrypts it with the stored key and posts it to Slack. Slack users see plaintext at the send time. **[inferred]**
- Slack users who join the Slack channel later are not Matrix members. The bridge decrypts once for all of them. So the new-member UTD case does not apply on the Slack side. **[inferred]**
- Risk: if the bridge resets its crypto store or device between schedule and send, it cannot decrypt. The message then never reaches Slack, and Mactrix gets no error. **[inferred]**
- The event `origin_server_ts` is the send time, not the schedule time. So a bridge check on message age does not drop it. **[inferred]**
- Smoke test on the dev account: schedule a message 2 minutes ahead in a bridged Slack room. Confirm it shows in Slack. **[rec]**

## 5. Beeper

Beeper Desktop 4.3.326, `app.asar` read with a plain text search. No app was launched. No user data was read. **[observed]**

- A local SQLite table `scheduled_messages (pendingMessageID, accountID, threadID, options)`. `options` is JSON with `addedOn`, `sendOn`, and `canceled`. **[observed]**
- Store and UI names: `ScheduledStore`, `scheduledMessages`, `nextScheduledMessageTime`, `hasScheduledMessages`, `editScheduledMessage`, `deleteScheduledMessage`, `updateScheduledTime`, `ToggleScheduledMessages`, `showScheduled` (an inbox filter), `scheduled_message_timeline_header`, and the label "Send later". **[observed]**
- No `msc4140`, `delay_id`, or `delayed_event` string is in the bundle. **[observed]**
- So Beeper Desktop keeps scheduled messages on the client and sends them from the client. This matches option B. **[inferred]** Whether the Beeper cloud also sends them when the app is closed was not checked.
- UI to copy: a scheduled list per chat, a timeline header for scheduled items, the next scheduled time in the chat list, edit, and delete. **[observed]** (names), layout not read.

## 6. Options

### A. MSC4140 through the SDK

The app calls `sendDelayedEvent` and `updateDelayedEvent`. The server holds the ciphertext and sends it.

- The send occurs when the Mac sleeps or the app is closed. It works from iOS (`MactrixiOS`) too. **[inferred]**
- The SDK does the encryption. No protocol logic in the app. This keeps hard rule 1. **[observed]** (rule), [inferred] (fit)
- Cancel and send now are one SDK call each. **[observed]**
- Cost: a Synapse upgrade to 1.164.0 or later, and an SDK bump from 26.04.01 to 26.11.11. The bump spans 9 releases and will have breaking FFI changes. **[inferred]**
- Gaps: no list, no status GET, no capability read in the FFI. The app keeps its own list. It cannot see a send failure. **[observed]**
- New members and new devices that join before the send cannot read the message. **[observed]**

### B. A local timer in the app

The app keeps scheduled messages in a local store. At the time, it sends through the normal send path.

- Encryption occurs at send time, so new members can read it. The send queue gives a local echo and retries. **[inferred]**
- Works today on the pinned SDK and the current server. **[inferred]**
- Sends only while the Mac is awake and the app runs. A closed lid at the time means a late or missed send. **[inferred]**
- On iOS it does not work. The OS does not run the app at a set time. **[inferred]**
- Two devices with the same list can send twice unless they coordinate. **[inferred]**
- Beeper Desktop appears to use this model. **[inferred]**

### C. A server-side sender

A service on the server sends at the time.

- To send as Patrick into an encrypted room, the service must be a logged-in device of Patrick's account with its own crypto store. It must hold the plaintext until the send. It must be verified. **[inferred]**
- A bot that sends as itself changes the sender. Slack users would see the bot, not Patrick. **[inferred]**
- This is a second Matrix client to run, update, and secure. MSC4140 gives the same result with no new service. **[inferred]**

### Recommendation

**[rec]** Option A.

- It is the only option that sends on time with the Mac asleep and that works on iOS.
- It keeps all protocol and crypto work in the SDK.
- The UI work (composer action, scheduled list, cancel, send now, edit) is the same for A and B. If the SDK bump stalls, B can use the same UI with a different transport.

Do not build B as a first step. A missed send with no signal hurts trust more than a short wait for the bump. **[rec]**

### Where the scheduled list lives

The FFI cannot list delayed events. So the app keeps a registry. **[rec]**

- Global account data, one event type (name to pick, for example `io.mactrix.scheduled_messages`). Entries: `delay_id`, `room_id`, `send_at_ms`, `created_at_ms`. No message text. The pinned FFI has `Client.accountData(eventType:)` and `Client.setAccountData(eventType:content:)` (`docs/ffi/matrix_sdk_ffi.swift` lines 832 and 1277). **[observed]**
- Account data is not encrypted on the server. So the text preview stays in a local store on the device that scheduled it. Other devices show "Scheduled message" with the time only. **[rec]**
- Remove an entry after the send time plus a grace period (the MSC allows 30 seconds), on cancel, and on send now. **[rec]**
- A failed send is not visible through the FFI. An upstream PR to export `get_delayed_event` would close that gap. Ruma already has the request type. **[rec]**

## 7. Story breakdown

Each story has its own Plane issue. The §11 decision row goes in when Patrick picks an option. **[rec]**

1. **Server: Synapse 1.164.0 or later.** Orchestrator owns it. Keep `max_event_delay_duration: 365d`. Confirm `/versions` still shows `org.matrix.msc4140`. Confirm the dedicated `PUT .../delayed_event/...` route answers on the dev account.
2. **SDK bump 26.04.01 to 26.11.11.** Own story, changelog review, refresh `docs/ffi/`. Check how to get `m.room.message` content JSON (with mentions, formatting, and replies) for `sendDelayedEvent`.
3. **Core: `ScheduledMessageService`.** Schedule (`sendDelayedEvent`), cancel and send now (`updateDelayedEvent`), edit (cancel then schedule again), the account data registry, the local preview store, and cleanup after the send time. Map `M_LIMIT_EXCEEDED`, `M_DELAY_TOO_LARGE`, and `M_FORBIDDEN` to clear errors. Unit tests with a fake SDK layer.
4. **UI: composer "Send Later…".** A menu item on the send button and a shortcut. A sheet with presets (later today, tomorrow morning, Monday morning) and a date and time picker. Show the time in the local time zone. Clear the composer on success.
5. **UI: per-chat scheduled list.** A bar above the composer: "2 scheduled". It opens a list with time and preview. Row actions: Send Now, Edit, Cancel. A small clock badge in the sidebar row for chats with scheduled messages. Snapshot tests.
6. **iOS parity.** The same service and a compact list.
7. **Optional upstream.** A matrix-rust-sdk PR to export `get_delayed_event` (and the list when MSC4486 lands) in the FFI.

## Open questions for Patrick

1. Can the orchestrator upgrade Synapse from 1.159.0 to 1.165.0? Option A does not work without 1.164.0 or later.
2. Do you accept that Matrix-side members or devices that join between schedule and send cannot read a scheduled message? (Slack-side readers are not affected.)
3. Where does the preview text live: local only (other devices show the time only), or plaintext in account data on your own server?
4. Is 365 days the right maximum lead time, and is the default limit of 100 pending messages enough?

## Sources

- MSC4140 text: https://github.com/matrix-org/matrix-spec-proposals/blob/main/proposals/4140-delayed-events-futures.md
- MSC4486 (listing): https://github.com/matrix-org/matrix-spec-proposals/pull/4486
- matrix-rust-sdk PR #6973: https://github.com/matrix-org/matrix-rust-sdk/pull/6973
- matrix-rust-components-swift 26.11.11: https://github.com/matrix-org/matrix-rust-components-swift/releases/tag/26.11.11
- Pinned widget path: https://github.com/matrix-org/matrix-rust-sdk/blob/388ced09a6b3f5e63521e0c8f7c2eec811ffd37a/crates/matrix-sdk/src/widget/matrix.rs
- Ruma delayed events (rev `5133d4ec`): https://github.com/ruma/ruma/tree/5133d4ec2846884b1d80a3769004524c34273c02/crates/ruma-client-api/src/delayed_events
- Synapse 1.159.0 REST: https://github.com/element-hq/synapse/blob/v1.159.0/synapse/rest/client/delayed_events.py and https://github.com/element-hq/synapse/blob/v1.159.0/synapse/rest/client/room.py
- Synapse 1.159.0 handler: https://github.com/element-hq/synapse/blob/v1.159.0/synapse/handlers/delayed_events.py
- Synapse changelog: https://github.com/element-hq/synapse/blob/develop/CHANGES.md
- Synapse config docs: https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html#max_event_delay_duration
- Beeper Desktop 4.3.326: `/Applications/Beeper Desktop.app/Contents/Resources/app.asar` (text search only)
