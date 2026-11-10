# Beeper Desktop "Merged Chats": implementation notes

Target: Beeper Desktop 4.3.284 (`app.asar`, extracted to a session scratchpad, not kept). Researched 2026-11-10 with REA for MATRIX-139. Static analysis only. No user data was read. Nothing was run from the extract.

Tags used below:

- **[code]**: read directly from the shipped code at the cited location.
- **[inferred]**: a conclusion from the code that the code does not state directly.
- **[rec]**: a recommendation for our client. Not found in Beeper.

Short file names:

- `APP` = `build/renderer/App-DSL3yZLr.js`
- `STORES` = `build/renderer/load-stores-CTkBoRl_.js`
- `DL` = `build/renderer/deep-link-BnyaFF04.js` (shared constants, i18n catalogs)
- `MAIN` = `build/main/index-BH78jOvK.mjs` (main-process Matrix client and SQLite)
- `API` = `build/main/index-Sx7F4iYJ.mjs` (local "Beeper Connect" tool API)

Offsets are character offsets into the file.

REA evidence: an exported bundle in the 2026-11-10 session scratchpad (195 MB, not kept in the repo). The application analysis is `ev_bc9e2442…`. The `com.beeper.union` forward trace is `ev_3662916d…`.

---

## 1. Concept and model

**A merged chat is a real Matrix room on the homeserver.** It is not account data, a tag, or a contact merge.

- **[code]** The room is created with `creation_content: {type: "com.beeper.union", "com.beeper.union": true}`, `preset: "private_chat"`, `visibility: "private"`. See `STORES` @357732, `createUnion(title, roomIDs)`.
- **[code]** The member rooms are listed as `m.space.child` state events in the union room. The `state_key` is the member room ID. The content is `{via: ["beeper.com"]}`. The `via` value is the constant `sf` exported as `a8` from `DL` @1450040.
- **[code]** The name is `m.room.name`. The avatar is `m.room.avatar` (`setUnionAvatar`, `setUnionAvatarMxc`, `clearUnionAvatar` in `STORES`).
- **[code]** One extra state event exists: `com.beeper.derive_dm_sender_names` with state key `""` and content `{enabled: bool}`. See `DL` @1452579 (`cf`) and `setDeriveDmSenderNames` in `STORES`. When this is on, the merged chat's name and avatar override the DM partner's profile everywhere in Beeper. UI label: "Apply merged info to contacts" (`APP` @3172443).
- **[code]** The union is a space-shaped room with a custom room type. The main process stores the children in the same `space_children` table that it uses for labels. The SQL joins `threads.room_type = 'com.beeper.union'`. See `MAIN` @641097 (`Ri.unionMemberships`, `unionMembersForParent`, `unionParentsForChild`).

Identifiers and fields:

| Item | Value | Source |
|---|---|---|
| Union ID | The union room's Matrix room ID | [code] `STORES` `createUnion` resolves to `bapi.createRoom(...)` |
| Members | Ordered list of member room IDs (`space_children.rowid` order) | [code] `MAIN` @641616 |
| Renderer model | `UnionsStore._unions: Map<unionID, {rooms: string[]}>` | [code] `STORES` @355809 (class `Mc`/`Ue`) |
| Thread model | `UnionThreadStore` (minified `lt`, exported as `b3`) extends the normal `ThreadStore` | [code] `APP` @2140469 |
| Default member | Thread prop `unionDefaultMemberRoomId` | [code] `APP` @1245909 (`gs.UNION_DEFAULT_MEMBER_ROOM_ID`) |
| Local API shape | `merge: {chatIDs, defaultChatID}` on the union; `mergedIntoChatID` on a member | [code] `API` @316664 `mapChat` |

---

## 2. Configuration (UI flow)

### Entry points [code]

All entry points open `CreateMergedChatBrowserWindow` (class `Uy`, `APP` @2232087). This is a 340x570 sub-window that renders `MergedChatEditor` (`E0t`, `APP` @~2223000). Each entry point sends a `source` value for analytics.

- Command bar: "Merge chats" with the keyword "combine" (`APP` @3032706, `command_bar`).
- Inbox context menu: "Merge Chats" (`APP` @2234910, `inbox_context_menu`).
- Merge suggestion banner in a chat (`APP` @2294271, `chat_suggestion_banner`).
- Chat info pane promo card (`APP` @3173734, `info_panel`).
- Chat info pane "Merged Chats" section, "Manage" menu: "Edit" and "Unmerge" (`APP` @3171294).
- Thread context menu, one chat selected, union thread: "Unmerge" replaces "Delete Chat" (`APP` @1702451).

### Editor steps [code] (`MergedChatEditor.tsx`)

1. **intro**: shown on first use, or when the user is at the limit. Afterwards, `markMergeChatsIntroSeen` is set.
2. **pick**: a checklist of `mergeableThreads`. The list has sections in this order: suggested members (`getSuggestedMembersFor`), top 8 by frecency, top 8 recent history, top 8 by sort time, and a search filter on the title. A minimum of 2 chats is required (`te = S.size >= 2`).
3. **details**:
   - Name: the default is the first chat's title.
   - Avatar: `auto` uses the first member with an image (`n0e`), `custom` uses a file picker, `keep` keeps the current avatar on edit.
   - Default room: a context menu over the members, "{title} · {network}".
4. **confirm**:
   - Create: `createUnion(name, rooms)` with a 30 s timeout. Then the avatar is set. Then the new union is selected and the chosen default is applied. A toast says "You can now message %1$s across %2$d chats from one conversation."
   - Edit: `updateUnion(id, {title, rooms})` sends `m.space.child` adds and removes and `m.room.name`.

### Unmerge [code]

- `threadController.confirmUnmergeUnion` (`APP` @1224600) shows the dialog "Unmerge Chat?" / "This will split this merged chat back into individual chats." with the buttons "Unmerge" and "Keep chats merged".
- `removeUnion` sends `m.room.member` with `{membership: "leave"}` for self, then `forgetRoom`. The `m.space.child` events are not removed (`STORES` `removeUnion`). The member rooms are not changed.
- After an unmerge, the app selects the most recent former member.

### "Same person" suggestions [code] (`STORES` @354502)

A chat is mergeable (`LD` and `isMergeable`) if all of these are true:

- `type === "single"`, not a group, and not a union.
- Not hidden, not disabled, and not read-only.
- Not already in a union.

**Groups cannot be merged through the UI.**

Match keys come from the DM partner (`Ei`):

- `tel:` plus the digits of the phone number.
- `mailto:` plus the lowercased email.
- `name:` plus the normalized full name, **only if the full name has 2 or more words** (`BD`).

The algorithm (`get mergeSuggestions`):

1. Build an inverted index from key to chats.
2. Run a BFS over shared keys to make connected components.
3. Keep the components with 2 or more chats.
4. Sort by size (descending), then by the newest timestamp.

Banner rules:

- `BANNER_SHOW_LIMIT = 3` rooms seen in total.
- A dismissal stores the suggestion's keys in `merge_suggestion_banner_dismissed_keys`. A suggestion that contains any dismissed key stays hidden.

**[inferred]** The owner's example ("Seth Redwine" against "Seth") gets no automatic suggestion from the name, because "Seth" is one word. A suggestion occurs only if the two Slack profiles share an email or a phone number. Otherwise the user merges them by hand.

### Settings and flags [code]

- Feature `max-merge-chats` (`jg`, `STORES` @215037), read from the user's plan features (`clientConfigStore.maxMergeChats`).
  - A missing or invalid value means `1`.
  - `-1` means unlimited.
  - Upsell strings: "Merge %d chat for free", "Unlimited Merged Chats", "You’ve reached your merged chat limit".
- Feature `PERSONAL_ROOM_OVERRIDES` gates the "Apply merged info to contacts" row (or the row shows if the state event is already on).
- Local prefs (`localPrefs` key-value, device-local):
  - `merge_suggestion_banner_dismissed_keys`
  - `merge_suggestion_seen_rooms`
  - `merge_chats_intro_seen`
  - chat-info promo dismissal
  - target-switcher nudge seen and dismissed

---

## 3. Storage and sync

| What | Where | Syncs? |
|---|---|---|
| Union existence, name, avatar, member list | Union room state on the homeserver (`m.room.create` type, `m.room.name`, `m.room.avatar`, `m.space.child`) | **Yes**, through normal Matrix sync to every device [code + inferred] |
| Derive-names toggle | `com.beeper.derive_dm_sender_names` state in the union room | Yes [code + inferred] |
| Local index | SQLite `space_children(parent_room_id, child_room_id, via)` joined with `threads.room_type` | Device-local cache, rebuilt from sync [code] `MAIN` @641097 |
| Default member room | `thread_props.props.unionDefaultMemberRoomId`, SQLite, per account | **No**, device-local [code] `MAIN` @584186 (`setThreadProp` writes `thread_props`) |
| Composer target in a draft | `send_room_id` in the draft record (and in `syncedDraft` when drafts sync is on) | Only through the drafts-sync feature [code: field] [inferred: sync path] |
| Suggestion and nudge state | `localPrefs` | No [code] |

- **[code]** No Beeper HTTP endpoint is specific to merges. Creation uses the generic `bapi.createRoom` and `sendStateEventToMatrixDirectly`.
- **[code]** The main process sends app events when union state changes (`MAIN` @636364):
  - `UNION_STATE_UPDATED` (full state, `{rooms}`)
  - `UNION_CHILD_UPDATED` (`{childRoomID, added: via.length > 0}`)
  - `UNION_REMOVED` (room delete)
- **[code]** The renderer handlers are `handleUnionSync`, `handleUnionChildUpdate`, and `handleUnionRemoved`.
- **[inferred]** The `initial_state` sets no `m.room.encryption`, so the union room is unencrypted. Its name (often a person's real name) and the member room IDs are plaintext on the homeserver.
- **[inferred]** The `via: ["beeper.com"]` value is hard-coded. A self-hosted homeserver needs its own server name.

---

## 4. Presentation

### Inbox row [code] (`UnionThreadStore` in `APP` @2140469, base `ThreadStore` in `APP` @1885600)

- **Name**: the union room's `m.room.name` (`computedTitle`).
- **Avatar**: the union room's `m.room.avatar`. If the room has no avatar, `ThreadAvatar` draws the title initials (`Sp` with `username: computedTitle`) because `extra.roomType === "com.beeper.union"` (`APP` @1276413). This is the "letters" case found earlier.
- **Network badge**: the platform brand is `merged-chat` (`_L`), with the display name "Merged Chat". The suggestion UI shows a stack of member network icons (`MergeSuggestionNetworkIcons.tsx`).
- **Preview**: `lastNonSilentMessage` is the newest message across all members.
- **Sort time**: `sortTimestamp` is the max of the members' `sortTimestamp`.
- **Unread count and mentions**: the sum over the members (MobX reactions in the constructor). The union's own counts from the server are discarded (`assignProps` strips `unreadCount` and `unreadMentionsCount`).
- **Mute**: the union room's own mute (`mutedRoomIDs.has(unionID)`). The class does not override it.
- **Archive**: the union archives all member rooms (`archiveRooms`). A union with no members on this device cannot be archived ("Merged chats without conversations on this device can't be archived").
- **Inbox visibility**: the union is visible if any member matches the inbox visibility rules.

Member rooms in an active union:

- `isHidden` is true (`isUnionMember`), so they leave the inbox.
- `isPinned` is forced to false.
- They are not sticky.
- The search and the dock or space counts map a member to its union (`r.unionThread ?? r`) and remove duplicates (`APP` @2038469, @2081346).
- Selecting a member selects the union instead (`setSelectedThread`, `APP` @2057424).

### Timeline [code]

- **Interleaved by timestamp.** `syncMergedMessages` concatenates the members' `messages` and sorts them with `c3`: timestamp, then `threadID`, then `sortKey` (`APP` @514479).
- **Source labels.** When a message's `threadID` differs from the previous message's `threadID`, the list inserts a `TimelineNote` (`key: chat-source-<id>`, `APP` @2550530).
  - The text is `chatSourceLabel(threadID)`: the network name, for example "Slack".
  - If 2 or more members share that network, the text adds " • " and an identifier (`fht`).
  - The identifier is the account's `userDisplayText` if the members are on different accounts. Otherwise it is the DM partner's name.
  - Owner's case: two Slack workspaces are two accounts, so the label is "Slack • <account label>".

### Back-pagination [code] (`APP` @514794–515170 and the `lt` methods)

- `memberTimelines` holds `{member, hasOlderMessages, oldestLoadedTime}` for each member.
- `timelineBoundary` (`nAe`) is the **max** `oldestLoadedTime` over the members that still have older messages.
- `clampVisibleMessages` hides messages older than the boundary. The user never sees a gap where one room has history loaded and another room does not.
- `boundaryHolders` (`sAe`) are the members whose oldest loaded message equals the boundary. `paginateBoundaryHolders` paginates only those members (`loadOlderMessages`). This is a k-way merge pagination.
- Jump-to-message and jump-to-unread call `loadMessagesUntil(predicate)`. This repeats `paginateBoundaryHolders` up to `pht = 20` rounds (or `xN` for jumps).
- `onThreadSelected` loads members that have no messages yet (`loadUnloadedMembers`).
- Attachments, bookmarks, and scheduled messages are merged and sorted the same way.

---

## 5. Sending [code] (`lt`, `APP` @~2150000–2156000)

The composer has one target member, `composeTarget`.

The auto-target rule (`seedComposeTarget`, `retargetToActivity`) is the same in `API` `resolveUnionSendTarget` (@317943):

1. If the draft has a `send_room_id` that is still a member, use it and pin it.
2. Else find the member with the newest non-silent message (`latestMemberActivity`).
3. If that newest message is **from the user and older than 30 minutes** (`1800*1e3`), use the default member (`unionDefaultMemberRoomId`, else the first member).
4. Else use the member with the newest message.
5. While auto mode is on and the composer has no content (no draft, quote, edit, or open thread), new activity changes the target.

Manual control:

- `composeSwitchTargets` shows a "Switch chats" picker when there are 2 or more members. The subtitle is the network or the identifier.
- A manual choice sets `shouldAutoUpdateTarget = false` and is stored in the draft (`setComposeTarget`).
- A one-time "target switcher nudge" shows in up to 3 rooms.
- The placeholder is "Message {member title} on {network}".

Per-action routing (all **[code]**):

- **Reply, quote, thread reply, edit**: `targetComposerAtMessage` / `startEditMessage` move the target to the member that owns the message. After the edit, the target goes back to the previous one.
- **Reactions, delete, retry, polls, translations, attachments**: `memberForMessage(msg)` or `memberForThreadID` delegate to the owning member.
- **Typing**: sent only to `composeTarget`. Incoming typing is the union of the typing participants of all members.
- **Read receipts**: `markAsRead(messageID)` takes the message's timestamp. For each member, it marks the newest message at or before that time (`YIe`). With no message ID, it marks every member read. `markUnreadFrom` works per member.
- **Queued sends and undo**: queues are per member. Sending to a new target flushes the other members' queues first.
- **Local API**: `sendMessage` with `replyToMessageID` uses `resolveUnionMessageTarget`, which probes each member with `getMessage`. Otherwise it uses `resolveUnionSendTarget`.

---

## 6. Notifications and badges [code]

- When a member room receives a message, it routes sound and notification through `m = this.unionThread ?? this` (`APP` @1919809–1920071). Mute and snooze are checked on the **union** (`shouldSuppressNotification`, `areNotificationsMuted`).
- `notificationSender` on the union replaces the sender's name and image with the union's title and avatar (`APP` @2143567).
- Typing notifications, error notifications, and the clearing of shown notifications are forwarded to the union.
- When all members are read, the union clears its shown notifications.
- In an active union, the per-member "Notification sound" setting is hidden (`APP` @3162410).
- Badges and counts treat the union as one chat (deduplication through `unionThread ?? r`).
- **[inferred]** This is desktop-only logic. Server push rules for member rooms do not change, so phone push still fires per member room unless a Beeper mobile client does the same mapping. A member room's own mute is not checked once the room is merged. The union's mute and the account's mute are checked.

---

## 7. Edge cases

- **Cross-network or same-network** [code]: the code has no network restriction. The only difference is the source label, which adds an identifier when 2 or more members share a network.
- **Cross-account** [code]: allowed. The identifier then uses the account label.
- **A member room is left or deleted** [code] (`MAIN` @856870):
  - Beeper sends `m.space.child` with `{}` for that room.
  - If it was the last member, Beeper leaves the union room (`leaveUnionSpace`).
  - A leave on "this device only" is skipped.
- **A member room is not on this device** [code]: `memberThreads` filters out unknown rooms. An empty union shows "This merged chat is empty on this device." or "This merged chat's conversations aren't on this device. Edit the merged chat to add conversations, or unmerge it."
- **Unmerge** [code]: Beeper leaves and forgets the union room. Member rooms are not changed.
- **Groups** [code]: `isMergeable` excludes groups, so the UI cannot merge them. The data model (`m.space.child`) does not block groups. **[inferred]** A union made by another client with group members probably still renders.
- **Limits** [code]:
  - `max-merge-chats` caps the active unions (default 1, `-1` for unlimited).
  - If the user has more unions than the cap (for example after a plan downgrade), only the **oldest by `createdAt`** stay active (`activeUnionIds`).
  - An inactive union is hidden, and its members show again as separate chats.
  - The code has no limit on rooms per union. The minimum is 2.
- **One room in two unions** [code]: `isMergeable` blocks this in the UI. `roomToUnion` is a single-valued map, so the last union wins.
- **Pending creation** [code]: a temporary ID maps to the create promise (`_pendingCreation`, `resolveUnion`). The UI updates before the server responds and rolls back on failure.

---

## 8. Mapping to our matrix-rust-sdk client [rec]

**These are recommendations, not findings.**

Pure presentation over existing rooms. Our project allows this:

- An inbox row that combines members: sum of unread counts, newest preview, max sort time, hidden members.
- An interleaved timeline with source notes.
- Boundary-clamped k-way back-pagination over one `Timeline` per member room.
- Composer target selection, including the 30-minute heuristic.
- Routing of replies, reactions, edits, and read receipts to the owning room.
- Notification remapping.

All of these use normal SDK calls per member room. None of them needs Matrix semantics that we write ourselves.

Persistent state:

- Option A (Beeper-compatible): a `com.beeper.union` room with `m.space.child` children. This uses only SDK room creation and state calls (`create_room` with `creation_content.type`, `send_state_event_raw`). This is not hand-written protocol. It also interoperates with Beeper if the owner keeps Beeper on mobile. Costs: an extra unencrypted room per merge, and the person's name in plaintext on the homeserver.
- Option B (smaller): one account-data event, for example `dev.ourclient.merged_chats`, with content `{ "merges": [{ "id", "name", "rooms": [...], "default_room" }] }`. Read and write it with the SDK account-data API. It syncs across our devices, adds no room, and Beeper does not read it.

Suggested minimal design:

1. Store merges in account data (Option B), unless Beeper interop is a goal. If interop is a goal, use Option A.
2. Make a `MergedChat` view model that owns N room timelines. It merges items by `origin_server_ts`, then room ID, then event order. It clamps at the max oldest-loaded timestamp and paginates only the rooms at the boundary.
3. Use the composer target rule "last active room, unless my own last message is more than 30 min old, then the default room". Add a visible picker in the composer, and pin the target on a manual choice.
4. Allow DMs only in v1. Do not add suggestions at first. Phone and email keys from bridge profiles are a cheap later addition.
5. Keep push rules unchanged. Remap only the local notification title and avatar.

Before you build this, check the scope. Contract §11 does not list merged chats as deferred or in scope. A new feature probably needs a §11 amendment.

---

## Confidence and gaps

**Overall confidence: high** for the data model, storage, timeline merge, composer routing, and notifications. Each of these comes from code read in the shipped bundle.

Gaps:

- **Server behavior.** The notes do not show if Beeper's homeserver or bridges do anything special with `com.beeper.union` rooms, for example push-rule changes or bridge behavior. The client code treats the union as a plain room.
- **Mobile clients.** iOS and Android behavior is not in this bundle. Phone push per member room is inferred.
- **Drafts-sync transport.** The code shows the `send_room_id` field, but this pass did not trace how drafts sync.
- **Union room encryption.** The inference comes from the missing `m.room.encryption` in `initial_state`. A server default could still turn on encryption.
- **The free-plan limit of 1** is the client fallback. The real plan values come from server features.
- **User data.** None was read. The code answers how merges are stored, so user data was not necessary.
- **REA coverage.** The REA graph seeds did not match minified identifiers. `trace_application_feature` returned `no-match`, and the `com.beeper.union` semantic trace was too large to return inline. That trace is in the exported bundle. Most of the detail came from targeted Python context reads of the minified files.
