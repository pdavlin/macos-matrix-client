# Own profile image per service: research notes

Researched 2026-11-16 for MATRIX-164. Static analysis only. No user data was read. No app was started. No homeserver or bridge was called. No app code was changed.

The question: in a bridged chat, an own message must show the user's image on that service (Slack workspace A, Slack workspace B). How does the client learn which bridge ghost is "me" in each workspace, with no manual setup step?

Sources:

- `SLACK` = mautrix-slack at commit `2a84859bad1d` (main, 2026-11-16).
- `GO` = mautrix-go at tag `v0.33.0`, the version that `SLACK` pins in `go.mod:19`. The framework is `GO bridgev2/`.
- `FFI` = `docs/ffi/matrix_sdk_ffi.swift`, the vendored interface of the pinned SDK. Read with `grep` only.
- `GROUPME` = beeper/groupme, default branch `main`, `go.mod` and `pkg/connector/id.go` only.
- `GCHAT` = mautrix/googlechat, branches `master` and `megabridge`, top level only.

Tags:

- **[code]**: read directly at the cited location.
- **[inferred]**: a conclusion from the code that the code does not state directly.
- **[rec]**: a recommendation for our client.

---

## Findings A: the bridge

### A1. The own ghost is not in the rooms [code]

The framework picks the Matrix user for each remote member in one function. `GO bridgev2/portal.go:2882-2887`:

```go
if sender.IsFromMe {
    intent = source.User.DoublePuppet(ctx)
    if intent != nil {
        return
    }
    extraUserID = source.UserMXID
}
```

- With a double puppet, the function returns the double puppet and stops. The ghost is not invited and not joined. This applies to the first member list (`getInitialMemberList`, `portal.go:4855`) and to each later sync (`syncParticipants`, `portal.go:5098`).
- Without a double puppet, the bridge joins the ghost and also invites the Matrix user (`extraUserID`).
- mautrix-slack sets `IsFromMe` for the own Slack user in each room type (`SLACK pkg/connector/id.go:31-36`, used in `chatinfo.go:246-282`).
- The workspace space has one remote member, the own user (`SLACK chatinfo.go:423-427`). With a double puppet, the space holds the bot and the Matrix user only.
- The bridge has no step "ghost leaves because the double puppet joined". A stale own ghost (joined before double puppeting was set up) is removed only by the general cleanup, and only when the member list is complete (`members.IsFull`, `portal.go:5116-5141`, reason "User is not in remote chat"). Slack marks a list complete only when it has all members (`chatinfo.go:254`). The space list is never complete (`chatinfo.go:424`). So a stale own ghost can stay in a large channel or in the space. [inferred]

Result: the member list of a room does not show the own ghost in the usual case.

### A2. What a client can reach

**Bridge info state (`m.bridge` and `uk.half-shot.bridge`, same content) [code].** `GO event/state.go:247-269` and `GO bridgev2/portal.go:4638-4674`. All fields that the framework writes:

| Field | Value |
|---|---|
| `bridgebot`, `creator` | the bot MXID |
| `protocol.id`, `displayname`, `avatar_url`, `external_url` | the network (`slack`, "Slack") |
| `network.id`, `displayname`, `avatar_url` | the top parent portal. For Slack: the team ID and the workspace name |
| `channel.id` | the portal ID. For Slack: `TEAMID-CHANNELID`, or `TEAMID` on the workspace space |
| `channel.displayname`, `channel.avatar_url` | the room name and image |
| `channel.fi.mau.receiver` | `portal.Receiver`: **the login ID that owns the portal**. Omitted when empty |
| `channel.com.beeper.message_request`, `channel.com.beeper.user_blocked` | flags |
| `com.beeper.room_type` (`dm`), `com.beeper.room_type.v2` | the room type |

- The state key is `<homeserver domain>/<appservice id>` (`GO bridgev2/matrix/connector.go:718-720`), unless `no_bridge_info_state_key` is set.
- mautrix-slack has no `FillPortalBridgeInfo`. It adds no field.
- **Slack sets a receiver on DMs and group DMs only.** `SLACK pkg/connector/id.go:28`:

```go
return slackid.MakePortalKey(s.TeamID, ch.ID, s.UserLogin.ID, s.Main.br.Config.SplitPortals || ch.IsIM || ch.IsMpIM)
```

- So `m.bridge` of a Slack DM or group DM carries `channel.fi.mau.receiver` = the user's login ID, `TEAMID-USERID`. This is the user's own remote ID for that workspace.
- A channel room and the workspace space carry no receiver, unless the bridge runs with `split_portals: true` (default `false`, `GO bridgev2/matrix/mxmain/example-config.yaml:19`). Then each room carries it.

**Other places [code].**

- Member event content: membership, display name, avatar, `fi.mau.will_auto_accept`, `com.beeper.exclude_from_timeline` (`portal.go:5000-5012`). No remote ID.
- Double-puppeted messages: `fi.mau.double_puppet_source` = the bridge name (`mautrix-slack`, `SLACK cmd/mautrix-slack/main.go:35`, `GO appservice/intent.go:202-226`), plus a timestamp key. No remote ID, no profile.
- `com.beeper.per_message_profile`: the framework reads and writes it for relay mode only (`portal.go:875-883`, `matrix/intent.go:92`). The bridge does not put it on double-puppeted messages.
- Account data written through the double puppet: `m.direct` (the other ghost, `matrix/intent.go:708`), marked-unread, mute, tags. No login ID.
- Personal filtering space: the framework writes `m.bridge` with `channel.id = "__personal_filtering_space__"` and `fi.mau.receiver = <login ID>` into it (`GO bridgev2/space.go:159-170`). **mautrix-slack turns this space off** (`SLACK pkg/connector/connector.go:50`: `bridge.Config.PersonalFilteringSpaces = false`). The Slack workspace space is a portal, not this space.
- Bridge status (`BridgeState`, with `remote_id` and `remote_profile`): goes to a status endpoint or a websocket, not to a room (`GO bridgev2/matrix/connector.go:523-535`).
- Management room: only the replies to commands (A3).

### A3. `list-logins`, login ID, ghost MXID [code]

`GO bridgev2/user.go:187`:

```go
logins = append(logins, fmt.Sprintf("* `%s` (%s) - `%s`", key, val.RemoteName, val.BridgeState.GetPrev().StateEvent))
```

- One line per login: the login ID, the remote name, the state. For Slack the remote name is `<team name> - <email>` (`SLACK login-cookie.go:154`).
- Login ID: `TEAMID-USERID`, case kept (`SLACK pkg/slackid/id.go:67-69`). Example form: `T01ABCDEF-U02GHIJKL`.
- Ghost user ID: the same two IDs in lowercase (`id.go:63-65`). `UserLoginIDToUserID` is `strings.ToLower` (`id.go:92-94`).
- Ghost MXID: `@<username_template applied to the ghost ID>:<homeserver domain>` (`GO bridgev2/matrix/connector.go:629-632`). The template is `appservice.username_template` in the bridge config, default `<network id>_{{.}}` (`example-config.yaml:281`). The Slack network ID is `slack` (`SLACK connector.go:71`).
- So with the default template: own ghost = `@slack_` + lowercase(login ID) + `:davlin.io`.
- The app already depends on this template: `ChatListNetwork` detects Slack by the localpart prefix `slack_` (`MactrixLibrary/Sources/Models/ChatListNetwork.swift:53`).

### A4. Provisioning API [code]

- Path: `/_matrix/provision/v3/...` on the **bridge's own appservice HTTP listener** (`GO bridgev2/matrix/provisioning.go:191`). The homeserver does not serve it. A client reaches it only if a reverse proxy exposes the bridge port.
- Enabled by default: `shared_secret: generate`, `allow_matrix_auth: true` (`example-config.yaml:316-322`). `shared_secret: disable` turns it off (`provisioning.go:257-260`).
- Auth: `Authorization: Bearer <shared secret>` or `Bearer <Matrix access token>`, plus the query `user_id=<MXID>`. For a Matrix token, the bridge calls the homeserver's `whoami` with that token and compares the user ID (`provisioning.go:194-212`). The user needs the `login` permission.
- `GET /v3/logins` returns `{"login_ids": [...]}` (`provisioning.go:418-425`).
- `GET /v3/whoami` returns `network`, `homeserver`, `bridge_bot`, `command_prefix`, `management_room`, `login_flows`, and `logins[]` (`provisioning.go:314-340`). Each login:

| Field | Value |
|---|---|
| `id` | the login ID (`TEAMID-USERID`) |
| `name` | the remote name |
| `profile` | `phone`, `email`, `username`, `name`, `avatar` (an `mxc://` URI), `avatar_file` (`GO bridgev2/status/bridgestate.go:85-93`) |
| `space_room` | the personal filtering space. Empty for Slack (A2) |
| `state`, `state_event`, ... | the connection state |

- For Slack, `profile.name` and `profile.avatar` are the own ghost's name and avatar. They are set at connect only (`SLACK pkg/connector/client.go:356-361`, the one assignment). They can be old until the next connect. [inferred]

### A5. The own ghost's avatar stays current [code]

- At each connect the bridge updates the own ghost from the boot response (`SLACK client.go:351-355`).
- Slack `user_change` and `user_profile_changed` events update the ghost (`SLACK handleslack.go:161-164`, `203-210`).
- Each remote event from the own user calls `ghost.UpdateInfoIfNecessary` before the double puppet check (`GO portal.go:2873-2880`).
- The ghost's avatar goes to its global Matrix profile (`ghost.Intent.SetAvatarURL`, `GO bridgev2/ghost.go:204`). A profile lookup by MXID can read it. The ghost needs no room membership for that.

### A6. Framework or Slack only

| Answer | Level |
|---|---|
| Double puppet replaces the ghost in member lists (A1) | framework |
| Bridge info fields, `fi.mau.receiver` = owner login ID (A2) | framework |
| Which portals have a receiver | connector. Slack: DMs and group DMs. All portals with `split_portals: true` (framework) |
| Personal filtering space with the login ID in `m.bridge` | framework default `true`. Slack turns it off |
| `list-logins` format, provisioning API (A3, A4) | framework |
| Login ID and ghost ID format, `RemoteProfile` content | connector |

- GroupMe: `GROUPME go.mod:14` pins mautrix-go `v0.31.1-0.2026...`, and the code has a `pkg/connector` with `NetworkID: "groupme"`. It is bridgev2. The framework answers apply. Its receiver rule and its login ID format were not read.
- Google Chat: `GCHAT` `master` is the Python bridge. It is not bridgev2, and none of the answers above apply to it. The `megabridge` branch is Go on mautrix-go `v0.23.3`, last commit 2025-04-30. Which code the Beeper-hosted Google Chat bridge runs is not known.

---

## Findings B: this app and the pinned SDK

### B1. Today's rule

`MessageAvatarRule.avatarUrl(memberAvatarUrl:accountAvatarUrl:isOwn:)` in `MactrixLibrary/Sources/Models/OwnProfile.swift`: the room member avatar, then (own messages only) the account avatar, then initials. The one call site is `MactrixLibrary/Sources/UI/Timeline/MessageEventView.swift:145`.

### B2. What the SDK gives [code]

| Call | `FFI` line |
|---|---|
| `func getProfile(userId: String) async throws -> UserProfile` (Client) | 997 |
| `struct UserProfile { userId: String, displayName: String?, avatarUrl: String? }` | 25565 |
| `func accountData(eventType: String) async throws -> String?` (Client) | 832 |
| `func setAccountData(eventType: String, content: String) async throws` | 1277 |
| `func session() throws -> Session` (`accessToken` 23250, `homeserverUrl` 23268) | 1270 |
| `func searchUsers(searchTerm: String, limit: UInt64) async throws -> SearchUsersResults` | 1245 |
| `func member(userId: String) async throws -> RoomMember` (Room) | 8089 |
| `func memberAvatarUrl(userId: String) async throws -> String?` (Room) | 8091 |
| `func members() async throws -> RoomMembersIterator`, `membersNoSync()` | 8107, 8109 |
| `func heroes() -> [RoomHero]` | 7970 |

- No match for `func roomAccountData`, `func joinedMembers(`, or a read of raw room state. The word "bridge" occurs in tracing names only.
- `getProfile(userId:)` is in use already (`Mactrix/Views/Inspector/InspectorUserInfo.swift:60`, `MatrixClient+NewChat.swift:30`). It reads any user's global profile. This is the call that gives the ghost's image.
- Not verified: that the homeserver answers a profile request for a ghost that shares no room with the user. Synapse limits profile lookups only when `limit_profile_requests_to_users_who_share_rooms` is set. The ghost shares no room with the user (A1). See Unknowns.

### B3. The one request outside the SDK

- `Models.ImagePackStateReader` makes `GET /_matrix/client/v3/rooms/{roomId}/state` with the session token. `Core/MatrixClient+ImagePacks.swift` gives it an ephemeral `URLSession` that refuses redirects.
- Contract §11, row 2026-11-13 (MATRIX-151, decision b) allows it as a bounded exception to hard rule 1. Row 2026-11-16 (MATRIX-161) says it "stays the only Matrix HTTP request outside the SDK: one read-only `GET …/rooms/{spaceId}/state`", at most once per 5 minutes per space.
- The room is always a parent space. The reader's doc comment says "Do not add a second request here".
- The state of the Slack workspace space has no receiver (A2). The data that the app fetches today does not hold the login ID.

### B4. Room to workspace

`Core/RoomAccountNames.swift` maps a room to its joined parent spaces through the SDK (`spaceService.joinedParentsOfChild(childId:)`), once per room, with retries. `ImagePackStore.Source.parentSpaces` uses the same call and keeps the space ID.

---

## Options

| Option | Needs | Automatic | Cost | Fails when | Stays current |
|---|---|---|---|---|---|
| (a) Provisioning API `whoami` | The bridge port reachable from the Mac. A bridge URL setting. | No. The URL is a setup step, and maybe a proxy rule. | A second HTTP request kind, to a second host, with the Matrix token. A new exception to hard rule 1. | The port is not exposed. `shared_secret: disable`. The avatar in the answer is from the last connect. | One call per session gives all logins. |
| (b) `m.bridge` of one DM per workspace | One DM or group DM in the workspace. The default username template, or a ghost MXID to copy the prefix from. | Yes. | The same request as image packs (same host, same endpoint), on one more room per workspace, once. A §11 row to widen the exception. Then `getProfile` through the SDK. | The workspace has no bridged DM. A custom username template with a suffix. The homeserver limits profile lookups. | The login ID changes only on a new Slack login. The image comes from `getProfile`, refreshed on a timer. |
| (c) Member list or DM members | Nothing. | Yes. | SDK only. | Always, in the usual case: the own ghost is not a member (A1). A stale ghost is luck. | No. |
| (d) Paste the login IDs once | The user sends `list-logins` and pastes each ID into Settings. | No. One step per workspace. | No request, no exception. A settings field. | A typing error. A new workspace needs the step again. | Same as (b) after the paste. |
| (e) Match ghost names to the account name | A user directory search. | Yes. | SDK only (`searchUsers`). | See below. | No. |
| (f) Personal filtering space state | A bridge that keeps that space. | Yes. | Zero new requests: the app reads space state already. | Slack: always, the space is off (A2). | Good for other bridgev2 bridges. |

Why (e) is unsafe:

- A display name is not an identity. A colleague with the same name, or a second account of the user (guest account, Slack Connect), gives two matches or the wrong match.
- The Slack display name and the Matrix display name are set apart and can differ. Then there is no match.
- A wrong match draws another person's face on the user's messages. The error is silent.
- A user directory search can leave out users who share no room with the user, and the own ghost shares none.

---

## Unknowns

Checks for Patrick, about one minute each:

1. Send `list-logins` to the Slack bridge bot. Paste the reply. Expected: one line per workspace, `* `T…-U…` (Team - email) - `CONNECTED``.
2. In Element, open a Slack DM, then `/devtools`, "Explore room state", `m.bridge`. Check that `channel` has `fi.mau.receiver` with the same ID as check 1. Do the same on a Slack channel. Expected there: no `fi.mau.receiver`.
3. Take one ID from check 1, make it lowercase, and open the profile of `@slack_<id>:davlin.io` (in this app: the search field or the user inspector). Expected: the Slack name and image for that workspace. This also proves that the homeserver answers a profile request for a ghost with no shared room.
4. Open the member list of one Slack channel and of the workspace space. Is a ghost with the own name there? (Stale ghost, A1.)
5. Read three values in the bridge config: `appservice.username_template`, `bridge.split_portals`, `provisioning.shared_secret`. Only option (a) needs the last one.
6. Does each Slack workspace have one bridged DM or group DM (the Slackbot DM counts)?
7. For Google Chat and GroupMe: the bridge software and version that the Beeper side runs. If it is bridgev2, look for a personal filtering space and read its `m.bridge` as in check 2.

Not determined by this research:

- The version and the config of the deployed bridge.
- Whether a stale own ghost exists in a room.
- The receiver rule of the GroupMe connector.
- Whether `getProfile` in the pinned SDK caches or makes a request on each call.

---

## Recommended design [rec]

Option (b), with (f) as the same code path for other bridges, and no manual step.

### Resolve the login ID

1. A room maps to its workspace space (B4, in place).
2. For a workspace with no known login ID, take one DM or group DM of that workspace and read its state with the existing reader. The trigger is the first open of a chat in that workspace.
3. In the state, take the `m.bridge` event whose sender is the `bridgebot` of its content. Read `channel.fi.mau.receiver` and `protocol.id`.
4. When the app reads a space's state for image packs, look for the same field there too. That covers a personal filtering space (f) and `split_portals` at no cost.
5. Keep `space ID -> (protocol, login ID)` on disk beside the image pack cache. Read again only when the profile lookup in the next section fails.

### Derive the ghost and read the image

1. Ghost MXID = `@` + prefix + lowercase(login ID) + `:` + the server name of the own MXID.
2. Prefix: take it from a ghost MXID in the same DM (the hero), the text before the lowercase team ID. If none, use `<protocol.id>_`.
3. `client.getProfile(userId:)` gives `avatarUrl`. Keep it per workspace. Read it again once per app session and when it is older than a set interval (start with 1 hour).
4. The lowercase rule and the `TEAMID-USERID` split are Slack connector facts. Keep them in a per-protocol table with one row, `slack`. An unknown protocol gets no service image.

### Draw

Extend `MessageAvatarRule` with a `serviceAvatarUrl` parameter. For an own message:

1. The service image (the ghost's avatar for the room's workspace).
2. The room member avatar, then the account image (today's rule).
3. Initials.

Another user's message does not change.

### Presentation only

- The app reads one state event and one profile. It writes nothing. It makes no membership, identity, or routing decision from the result.
- A wrong or missing value changes one image and nothing else.

### Objections to this design

- It widens an exception that two §11 rows call "the only" request and "bounded". The alternative with no exception is (d). For two workspaces, (d) costs two pastes, once. Is "no manual step" worth a wider exception?
- It depends on two bridge internals: the `fi.mau.receiver` key and the lowercase ghost ID. Both are stable in bridgev2 today, and neither is a documented API.
- A workspace with no bridged DM gets no service image until a DM exists.
- `whoami` (a) is the cleaner data source. It loses because the bridge port is not on the homeserver, the token would go to a second host, and it needs a URL setting.

---

## Story breakdown [rec]

### Story 1: resolve the own ghost per workspace

- `Models`: a parser for bridge info in a state array (`protocol.id`, `network.id`, `channel.fi.mau.receiver`, sender check), and the ghost MXID derivation for `slack`. Pure, unit-tested with fixture JSON.
- `Core`: a store that maps a space to a login ID, reads one DM's state through the existing reader, and keeps the result on disk.
- Done: unit tests cover a DM state, a channel state with no receiver, a space state with a receiver, a wrong sender, and an unknown protocol. No test touches the network. Build, tests, and lint pass. The §11 row is in the same PR.

### Story 2: draw the service image on own messages

- `Core`: `getProfile` for the resolved ghost, kept per workspace, refreshed per session and on the interval.
- `Models`: `MessageAvatarRule` takes `serviceAvatarUrl`. `UI`: the timeline passes it.
- Done: unit tests for the new order. A snapshot test of an own message with a service image. Manual smoke on the dev account if it has a Slack login, else Patrick checks two workspaces. Build, tests, and lint pass.

### Optional story 3: manual login ID

- A field per workspace in Account settings for the login ID from `list-logins`. It wins over the resolved value.
- Do this story only if check 6 fails for a workspace, or if the §11 row for story 1 is refused. In the second case it replaces story 1.
- Done: a pasted ID gives the service image with no state request. Unit tests for the ID check. Build, tests, and lint pass.

---

## Contract §11 rows needed

1. **Amendment:** the own profile image per service enters scope (MATRIX-164), with the fallback order service image, account image, initials.
2. **Decision: widen the state read exception.** The request of the 2026-11-13 row may also read one DM or group DM room per workspace, once per workspace (and again only after a failed profile lookup), for the bridge info event only. Same host, same endpoint, read-only, display data only. The 2026-11-16 row's words "the only Matrix HTTP request" stay true for the request kind. The room set grows.
3. **Decision:** the app derives the own ghost's MXID from the bridge's login ID with a per-protocol rule (Slack: lowercase). This is a bridge convention, not Matrix protocol logic. An unknown protocol gets no service image.

If option (d) replaces (b), only row 1 is needed.

---

## Confidence

- High: A1 to A5. Each is read from the code at the cited lines.
- Medium: that the deployed bridge matches this code. Checks 1 to 3 settle it.
- Low: Google Chat and GroupMe. The framework answers hold only if those bridges are bridgev2 and keep the personal filtering space.
