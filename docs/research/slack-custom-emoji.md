# Slack custom emoji: research notes

Researched 2026-11-12 for MATRIX-151. Static analysis only. No user data was read. No app was started. No app code was changed.

Sources:

- `SLACK` = mautrix-slack at commit `f8b161236ae2` (main, 2026-11-12). The changelog top entry is v26.10.
- `GO` = mautrix-go at commit `b2652e840224` (the version that `SLACK` pins in `go.mod`).
- `FFI` = `docs/ffi/matrix_sdk_ffi.swift`, the vendored interface of the pinned SDK (`matrix-rust-components-swift` 26.04.01). Read with `grep` only.
- `BEEPER` = Beeper Desktop 4.3.308, `app.asar`. Searched in place. Nothing was extracted or run. Offsets are character offsets into the named file.

Tags:

- **[code]**: read directly at the cited location.
- **[inferred]**: a conclusion from the code that the code does not state directly.
- **[rec]**: a recommendation for our client.

---

## Findings A: the bridge

### A1. Slack to Matrix, emoji in a message body [code]

A custom emoji in a Slack rich text block becomes an HTML image tag in `formatted_body`.

`SLACK pkg/msgconv/blocks.go:315-331`:

```go
emoji, isImage := sc.GetEmoji(ctx, e.Name)
if isImage {
    htmlText.WriteString(fmt.Sprintf(`<img data-mx-emoticon src="%[1]s" alt=":%[2]s:" title=":%[2]s:" height="32"/>`, emoji, e.Name))
} else {
    htmlText.WriteString(emoji)
}
```

- `src` is an `mxc://` URI. The bridge uploads the Slack image on first use and keeps the URI in its database (`SLACK pkg/connector/emoji.go:317-361`, `tryGetEmoji`).
- The plain `body` is made from the HTML (`format.HTMLToContent`, `SLACK pkg/msgconv/blocks.go:772`). The HTML-to-text step writes the `alt` value for an image (`GO format/htmlparser.go:329-340`). So `body` holds `:name:`.
- If the bridge does not know the emoji, `GetEmoji` gives the text `:name:` and no image tag (`emoji.go:363-373`).
- Messages that have no rich text blocks go through the mrkdwn path. That path replaces only standard shortcodes with Unicode (`SLACK pkg/msgconv/mrkdwn/parser.go:76`). A custom emoji stays as the text `:name:` there. [inferred]

### A2. Slack to Matrix, reaction key [code]

`SLACK pkg/connector/handleslack.go:414-432`:

```go
emoji, isImage = s.GetEmoji(ctx, reaction)
if isImage {
    slackReactionInfo["mxc"] = emoji
    if !s.Main.Config.CustomEmojiReactions {
        emoji = shortcode
    }
}
extraContent = map[string]any{
    "com.beeper.reaction.shortcode": shortcode,
    "fi.mau.slack.reaction":         slackReactionInfo,
}
```

- With `custom_emoji_reactions: true` (the example config default, `SLACK pkg/connector/example-config.yaml:45-47`), the `m.reaction` key is the `mxc://` URI.
- With `false`, the key is the text `:name:`.
- The event content always has two extra fields: `com.beeper.reaction.shortcode` = `:name:`, and `fi.mau.slack.reaction` = `{name, mxc}`.

### A3. Matrix to Slack [code]

**Reaction.** `SLACK pkg/connector/handlematrix.go:309-335`:

```go
key := msg.Content.RelatesTo.Key
if strings.ContainsRune(key, ':') {
    dbEmoji, err = s.Main.DB.Emoji.GetByMXC(ctx, key)
    ... else if dbEmoji == nil { err = unknownEmojiError(key) }
} else {
    emojiID = emoji.GetShortcode(key)   // Unicode emoji to Slack shortcode
```

- The bridge accepts two key forms: the exact `mxc://` URI that it has in its emoji table, or a Unicode emoji.
- `:name:` fails. It contains a colon, so the bridge looks it up as an MXC URI and finds nothing.
- A bare name fails. It is not a Unicode emoji.
- A failure gives the notice "that emoji isn't available in this Slack workspace" (`handlematrix.go:300-307`).
- The bridge does not read `com.beeper.reaction.shortcode` on the way in. The key alone decides.
- `GetByMXC` has no workspace filter (`SLACK pkg/connector/slackdb/emoji.go:51-53`). An MXC URI from workspace A, sent in a room of workspace B, resolves to A's emoji name. Slack then accepts or rejects that name. [inferred]

**Inline emoji in a message.** `SLACK pkg/msgconv/matrixfmt/blocks.go:270-282`:

```go
case "img":
    src := parser.getAttribute(node, "src")
    dbEmoji, err := parser.db.Emoji.GetByMXC(ctx.Ctx, src)
    ... else if dbEmoji != nil {
        return []slack.RichTextSectionElement{slack.NewRichTextSectionEmojiElement(dbEmoji.EmojiID, 0, ctx.StylePtr())}, nil
    }
    if alt := parser.getAttribute(node, "alt"); alt != "" { /* text element */ }
```

- The client must send `format: org.matrix.custom.html` and an `<img src="mxc://…">` whose `src` is a known emoji URI. The bridge does not check `data-mx-emoticon` on the way in. Only `src` counts.
- An unknown `src` falls back to the `alt` text.
- A message with no HTML goes through `ParseText` (`blocks.go:485-495`). `:name:` becomes a plain text element. The bridge does not turn it into an emoji element.
- The bridge states support: `event.FmtCustomEmoji: event.CapLevelFullySupported` (`SLACK pkg/connector/capabilities.go:114`).

### A4. Where the emoji list is, and what a client can read [code]

**Storage.** A table in the bridge database (`SLACK pkg/connector/slackdb/00-latest-schema.sql`):

```sql
CREATE TABLE emoji (team_id TEXT, emoji_id TEXT, value TEXT, alias TEXT, image_mxc TEXT, PRIMARY KEY (team_id, emoji_id));
```

- The bridge fills it at connect (`go s.SyncEmojis(ctx)`, `SLACK pkg/connector/client.go:396`) and on Slack `emoji_changed` events (`emoji.go:93-129`).
- `image_mxc` is empty until the emoji is first used or a pack is made. The upload is lazy.

**Exposure to Matrix.** The bridge does not publish the list by itself. It publishes it on request, as an MSC2545 image pack. This arrived in v26.05 ("Added support for importing all Slack workspace emojis as a Matrix image pack", `SLACK CHANGELOG.md`).

- The Slack connector implements `bridgev2.StickerImportingNetworkAPI` (`emoji.go:37-91`). `DownloadImagePack` makes a pack of every image emoji: `images[shortcode] = {url: mxc}`, with `pack.usage = ["emoticon"]`, `pack.display_name = "<team> emojis"`, and `pack."fi.mau.bridged_pack" = {network: "slack", url: <team URL>}`. It uploads every emoji that has no MXC URI yet.
- Bot command: `import-image-pack <url>` (`GO bridgev2/commands/imagepack.go:17-27`). The URL must contain the team domain (`emoji.go:45`).
- Provisioning HTTP API (`GO bridgev2/matrix/provisioning.go:149-151`): `GET /v3/image_pack/list`, `GET /v3/image_pack/import?pack_url=` (preview: gives the pack JSON, writes nothing), `POST /v3/image_pack/import?pack_url=` (writes the pack).
- The write (`GO bridgev2/provisionutil/imagepack.go:76-132`): the bridge bot sends state events of type **`m.room.image_pack`** to the workspace's space room. For Slack, the space room is the team portal (`SLACK client.go:401`, with the "small hack" comment at `imagepack.go:82-83`). The state key is the team domain. A pack over 62 KB is split into parts with state keys `<domain>`, `<domain>.001`, and so on. Each part has `fi.mau.combined_pack_key`, `_index`, and `_count`.
- The event type is `m.room.image_pack`, not `im.ponies.room_emotes` (`GO event/type.go:202-203`).
- The pack is a snapshot. `handleEmojiChange` updates the database only. A new Slack emoji is not in the pack until the import runs again. [inferred]
- The bridge writes no account data (`im.ponies.user_emotes`, `im.ponies.emote_rooms`, `m.image_pack.rooms`).

Summary: with no import, a Matrix client can learn an emoji only from an event that used it. After one `import-image-pack`, the full list is room state in the workspace space.

---

## Findings B: this app today

### B1. Message body HTML

- `Mactrix/Views/ChatView/FormattedBodyView.swift:31-41`: a message with an HTML body draws through `parseFormattedBody` in an `AttributedTextView` (an `NSTextField` label).
- `MactrixLibrary/Sources/MessageFormatting/Parser.swift:18-19, 81`: the parser is `ZHTMLParserBuilder.initWithDefault()` (ZMarkupParser 1.12.0). The default tag set includes `IMG_HTMLTagName(handler: nil)`.
- ZMarkupParser turns each `<img>` into a `ZNSTextAttachment` with a placeholder of `width ?? 50` by `height ?? 50` points (`HTMLTagNameToHTMLMarkupVisitor.swift:160-186`). The attachment then gets `src` with `URLSession.shared` (`ZNSTextAttachment.swift:72-108`).
- Result for a Slack emoji **[inferred, not run]**: `URLSession` cannot load `mxc://`. The row shows an empty 50 by 32 point placeholder. The `alt` text `:name:` does not show. The image does not show.
- Side finding **[inferred, not run]**: an `<img src="https://…">` from any sender starts a request to that host with the user's IP address. This is a tracking hazard. It is separate from this feature, and the same change can remove it.
- `Models.JumboEmoji.jumboText` (`MactrixLibrary/Sources/Models/JumboEmoji.swift:51-54`) gives nil when the HTML differs from the body. A message of custom emoji only draws as normal text, not jumbo.

### B2. Reaction chip

- `MactrixLibrary/Sources/UI/Timeline/MessageReactionView.swift:109`: `Text(reaction.key)`.
- An `mxc://` key draws as the literal string `mxc://server/id` in the chip.
- The model has the key and the senders only (`MactrixLibrary/Sources/Models/Reaction.swift:3-8`). The SDK type is the same (`FFI:21480`, `struct Reaction { key, senders }`). `com.beeper.reaction.shortcode` is not available through the FFI.

### B3. Picker and composer

- Reaction picker view: `MactrixLibrary/Sources/UI/Timeline/ReactionPickerView.swift:61-63`. Inputs: `catalog: EmojiCatalog`, `recents: [String]`, `onPick: (String) -> Void`. A cell is `Text(verbatim: value)` (`:239-246`).
- Grid model: `MactrixLibrary/Sources/Models/EmojiPickerContent.swift:48-66`. Sections come from `catalog.categories`, or one search section. `EmojiCatalog.Entry.value` is "the string a reaction sends" (`EmojiCatalog.swift:21-23`).
- Catalog: bundled Unicode list, `UI.EmojiCatalog.bundled` (`ReactionPickerView.swift:10-12`).
- Host: `Mactrix/Views/ChatView/TimelineView/TimelineReactionPicker.swift:131-146` passes `catalog: .bundled` and `client?.recentEmojis.emojis`. It knows the timeline, so it knows the room (`:195`).
- Send: `LiveTimeline.toggleReaction(key:on:recordingUseIn:)` (`MactrixLibrary/Sources/Core/LiveTimeline+Reactions.swift:54-64`) calls the SDK `toggleReaction(itemId:key:)` (`FFI:15608`) with the key as given. It then records the key in the account's recent list (`MatrixClient+RecentEmoji.swift:29-34`, SDK `addRecentEmoji`, `FFI:1448`). That list is account data that Element X also reads.
- Plug points for a second source: a new leading section in `EmojiPickerContent`, an image variant of `Entry` (or of the cell), and a per-room list passed in at `TimelineReactionPickerContent`.
- Composer: there is no emoji entry in the composer. No picker button, no `:shortcode:` completion. Text goes out through `messageEventContentFromMarkdown(md:)` (`Mactrix/Views/ChatView/ChatInputView/ChatInputView.swift:55`, `FFI:50146`). The nearest pattern is the mention popup (`MactrixLibrary/Sources/Models/MentionAutocomplete.swift`, `ComposerMention.swift`).
- Room to workspace: `Core.RoomAccountNames` already maps a room to its parent spaces through the SDK space service (`joinedParentsOfChild(childId:)`, `FFI:13538`). The workspace space is the room that holds the pack.

### B4. What the pinned SDK can read

Exact signatures in `FFI`:

| Need | Signature | Line |
|---|---|---|
| Global account data, raw JSON | `func accountData(eventType: String) async throws -> String?` | 832 |
| Write account data | `func setAccountData(eventType: String, content: String) async throws` | 1277 |
| Watch account data (typed enum only) | `func observeAccountDataEvent(eventType: AccountDataEventType, listener: AccountDataListener) -> TaskHandle` | 1161 |
| Watch room account data (typed enum only) | `func observeRoomAccountDataEvent(roomId: String, eventType: RoomAccountDataEventType, listener: RoomAccountDataListener) throws -> TaskHandle` | 1170 |
| Media bytes | `func getMediaContent(mediaSource: MediaSource) async throws -> Data` | 978 |
| Media thumbnail | `func getMediaThumbnail(mediaSource: MediaSource, width: UInt64, height: UInt64) async throws -> Data` | 993 |
| MXC to source | `public static func fromUrl(url: String) throws -> MediaSource` | 6631 |
| HTML message | `public func messageEventContentFromHtml(body: String, htmlBody: String) -> RoomMessageEventContentWithoutRelation` | 50130 |
| Write state | `func sendStateEventRaw(eventType: String, stateKey: String, content: String) async throws -> String` | 8257 |
| Generic GET | `func getUrl(url: String) async throws -> Data` | 1047 |

Not in the pinned FFI:

- **No read of room state.** `grep` finds no `rawState`, `getStateEvent`, `stateEvents`, or `RoomStateEvent`. `Models/ChatListNetwork.swift:5-7` already records this limit.
- No `roomAccountData` read.
- No `imagePack`, `emote`, or `customEmoji` API. The only hit is the enum case `StateEventType.roomImagePack` (`FFI:38407`), used for permission checks.
- `getUrl` uses the SDK HTTP client. In upstream main it sends no access token (`bindings/matrix-sdk-ffi/src/client.rs`, `self.inner.http_client().get(url).send()`). It cannot read `/rooms/{id}/state`. [inferred for the pinned build]

Upstream main (`matrix-rust-sdk` `6b572b4c9dce`, 2026-11-12) has `Room.state_events(event_type:) -> Vec<RoomStateEvent>` and a subscription (`bindings/matrix-sdk-ffi/src/room/mod.rs:547`). Its doc comment says a custom type is empty unless the sliding sync `required_state` asks for it.

---

## Findings C: Beeper Desktop

Short file names: `MAIN` = `build/main/index-H5UgkDmG.mjs`, `APP` = `build/renderer/App-uFdjC222.js`, `STORES` = `build/renderer/load-stores-DW28-UYh.js`.

- **Render [code].** The HTML sanitizer keeps `<img>` with `width`, `height`, `alt`, `title`, `data-mx-emoticon`, and a `src` that passes an MXC check (`MAIN` @394329). The composer node reads `img[data-mx-emoticon]` and writes `<img data-mx-emoticon data-type="customEmoji" src alt=":name:" title=":name:" height="16">` (`APP` @1080267, @1080645). Plain-text previews use the `alt` text (`build/main/Keychain-BFeVOOK0.mjs` @255423).
- **Reaction in [code].** `MAIN` @497315: if the key is an MXC URI, the reaction model is `{reactionKey: shortcode ?? key, imgURL: key}`. The shortcode is `content["com.beeper.reaction.shortcode"]` with the colons removed.
- **Reaction out [code].** `MAIN` @622899: `"m.relates_to": {key: <mxc>, rel_type: "m.annotation", event_id}` plus `"com.beeper.reaction.shortcode": ":name:"` when the emoji is custom.
- **Picker source [code].** `APP` @1978793, `customEmojisForReactions`: the list is `accountStore.customEmojis` (a map of name to URL for each connected account, from a platform call `getCustomEmojis`, `STORES` @70490 and @67849) plus the user's own `m.image_pack` account data when the room feature `custom_emoji_reactions` is set. The message composer uses the same two lists, gated by the room's `formatting.custom_emoji` feature.
- **Packs [code].** Beeper stores `m.room.image_pack` and `im.ponies.room_emotes` state (`MAIN` @392689). For a room it reads the packs of the room and of its parent spaces, nearest first (`MAIN` @607495, SQL `packsForRoomAndParents`), plus the rooms named in `m.image_pack.rooms` account data (`MAIN` @679602). It joins the `fi.mau.combined_pack_*` parts (`APP` @2655074). The renderer code that was read uses these packs for the sticker picker. It calls the bridge's `listImagePacks` and `importImagePack` from a "New sticker pack" dialog (`APP` @3351948).
- **Not followed.** Where the Matrix-side `getCustomEmojis` map comes from for a bridged Slack account. The search stopped here by the task's effort limit.

---

## Unknowns

Each line is one concrete check.

1. **Bridge version.** Does the deployed mautrix-slack have `import-image-pack`? Check: send `help` to the Slack bridge bot and look for the command. It needs v26.05 or later.
2. **Bridge config.** Is `custom_emoji_reactions` true? Check: one `m.reaction` event's JSON from a Slack room where a person reacted with a custom emoji. The key is either `mxc://…` or `:name:`.
3. **Pack shape on this account.** After one import: the JSON of `GET /_matrix/client/v3/rooms/{workspace space}/state`. Confirm the type `m.room.image_pack`, the state keys, and the part count.
4. **Pack size.** How many emoji does each workspace have? The import uploads every one. A workspace with thousands of emoji means thousands of uploads on the first run, unless the bridge uses direct media.
5. **Media route.** Does `getMediaContent` load a bridge emoji MXC URI on davlin.io? Direct media changes the server part of the URI. Check on the dev account with one URI from a message.
6. **Today's body render.** Confirm B1 with a unit or snapshot test: the HTML from A1 through `parseFormattedBody`.
7. **Markdown pass-through.** Does `messageEventContentFromMarkdown(md:)` keep an inline `<img data-mx-emoticon …>` in `formatted_body`? Check: send one on the dev account and read the event source in Element Web.
8. **Plain `:name:` text from Matrix.** Does Slack draw it as an emoji? The bridge sends it as a text element. Check: one message in a Slack test channel.
9. **SDK bump value.** Does a newer `matrix-rust-components-swift` release have `Room.stateEvents`, and does its sync ask for `m.room.image_pack`? Check: the release's generated Swift file and the SDK's `required_state` list.
10. **Dev account.** The dev account has no Slack workspace, as far as this research knows. Stories 3 and 4 need a Slack test workspace on the dev account, or a hand-made `m.room.image_pack` event in a dev space plus a manual check by Patrick.

---

## Recommended design [rec]

### Data source

- **Primary: the bridge's image pack in the workspace space.** Patrick runs `import-image-pack https://<team>.slack.com` in the bridge bot room, one time for each workspace, and again when the list is stale. The app adds no bridge UI. The contract puts bridge management outside the app.
- **Read path, option 1 (recommended): one authenticated `GET /_matrix/client/v3/rooms/{spaceId}/state` with `URLSession`**, filtered to type `m.room.image_pack` (and `im.ponies.room_emotes`). The space ID comes from the SDK space service. The token comes from `client.session()`. The app joins the split parts by `fi.mau.combined_pack_key`.
- **Read path, option 2: an SDK bump story** to a release with `Room.stateEvents`. This keeps every read inside the SDK. It helps only if unknown 9 has a good answer.
- **Fallback with no pack: none in v1.** The picker shows no custom section. Rendering does not need the pack.
- **Rejected:** the bridge provisioning API from the app (bridge management, out of scope), a copy of the pack in account data (a second sync mechanism), a call to Slack (non-Matrix protocol), and a list made only from emoji seen in the timeline (incomplete, and it makes a second cache with its own rules).

Challenge to weigh: option 1 is the first Matrix HTTP call that the app makes outside the SDK. It is one read of unencrypted state, and the server resolves the state. It is not sync, crypto, or timeline logic. It is still a step past hard rule 1 as written, so it needs a §11 row before any code.

### Model

- `Models.CustomEmoji { shortcode, mxcURL }` and `Models.CustomEmojiPack { spaceId, displayName, emoji }`. Value types, with a parser for the pack JSON, unit-tested from a fixture.
- `Core.CustomEmojiDirectory` on `MatrixClient`: packs by space ID, plus a reverse map from MXC URL to shortcode for chip tooltips.
- Scope a pack to the rooms of its space. Do not offer workspace A's emoji in workspace B, or in a room with no Slack space. The bridge rejects an unknown key, and a plain Matrix room would get an `mxc://` reaction that other clients show as text.

### Render

- **Body:** before the HTML parse, handle `<img>` in our code path. An image with `data-mx-emoticon` and an `mxc://` source becomes an inline attachment at line height, loaded through the SDK media API. Every other `<img>` becomes its `alt` text. No `<img>` goes to `URLSession`. While the image loads, show the `alt` text. The attachment is not taller than the line, so the row height does not change when the image arrives.
- **Chip:** if the key starts with `mxc://`, draw a fixed-size image in place of `Text(reaction.key)`. The tooltip uses the shortcode from the reverse map, or "custom emoji". The chip's frame must stay the same before and after the image loads.
- **Animated emoji:** draw the first frame in v1.

### Send

- **Reaction:** the picker gives the emoji's `mxc://` URL as the key. `toggleReaction(itemId:key:)` sends it. The bridge maps it to the Slack name (A3). No extra event field is needed. The pinned FFI cannot add `com.beeper.reaction.shortcode`, and the bridge does not read it.
- **Recents:** do not pass an `mxc://` key to `addRecentEmoji`. That list is shared account data, and the quick-reaction row would offer the key in rooms where it fails. Keep custom emoji out of recents in v1.
- **Message:** the composer inserts a `:name:` token from a completion popup (the mention popup pattern). At send, the token becomes `<img data-mx-emoticon src="mxc://…" alt=":name:" title=":name:" height="32">` in the HTML body. Two ways to make the event: markdown pass-through (unknown 7), or `messageEventContentFromHtml(body:htmlBody:)` with `:name:` in the plain body. Decide after the unknown 7 check.

### Cache

- **Image bytes:** the SDK media store (through `getMediaThumbnail` or `getMediaContent`). No new store.
- **Decoded images:** the existing `MatrixClient.imageCache` (`MatrixClient+ImageCache.swift`), keyed by MXC URL and pixel size.
- **Pack JSON:** in memory for the session, plus one JSON file for each space in the app's caches folder, so the picker has a list before the network read ends. Refresh at launch and when the picker opens if the copy is older than a set age. The pack holds no secret.

### Presentation only, and what hard rule 1 forbids

| Presentation only | Needs a §11 decision | Forbidden |
|---|---|---|
| Draw an emoticon image in a body | The raw `GET …/state` read (option 1) | A sync or state cache of our own for packs |
| Draw an `mxc://` reaction key as an image | | A call to the bridge provisioning API or to Slack |
| A picker section from a parsed pack | | Pack create, edit, or import from the app (deferred "management") |
| Send an `mxc://` key through `toggleReaction` | | An SDK bump inside a feature story (hard rule 6) |
| Send an `<img>` in an HTML body through the SDK | | |

---

## Story breakdown [rec]

### Story 1: draw custom emoji in message bodies

- Handle `<img>` before the parse: emoticon with `mxc://` to an inline image, all other images to `alt` text.
- Load through the SDK media API and the decoded-image cache.
- Done when: a unit test covers the HTML from A1 (image case, unknown-source case, non-emoticon image case). A snapshot shows an inline emoji at line height and the `alt` fallback. No `<img>` starts a `URLSession` request (test). The row height is the same before and after the image loads. Build, tests, and lint pass. Manual smoke on the dev account with a hand-sent emoticon message.

### Story 2: draw custom emoji reaction chips

- Image chip for an `mxc://` key, with a fixed frame. Tooltip from the shortcode map when a pack is loaded.
- Done when: snapshots cover a Unicode chip next to an image chip, own and other, loaded and not loaded. The strip geometry tests pass with an image key. A click on the chip toggles the reaction with the same key. Build, tests, and lint pass.

### Story 3: read the workspace pack and offer it in the reaction picker

- Blocked by the §11 decision on the read path, and by unknowns 1 and 3.
- Pack parser and `CustomEmojiDirectory`. A "<Workspace> emoji" section and search by shortcode in `EmojiPickerContent`. Image cells. A pick sends the MXC key. Custom keys stay out of recents.
- Done when: parser tests cover one pack, a split pack, an empty pack, and bad JSON. Picker tests cover section order, search, and arrow keys across an image section. A room outside the workspace shows no custom section. A pick in a Slack room puts the emoji on the message in Slack (manual check by Patrick, see unknown 10). Build, tests, and lint pass.

### Story 4: custom emoji in the composer

- Blocked by story 3 and by unknown 7.
- `:` completion popup with the room's pack. Send as an emoticon `<img>` in the HTML body. Edits keep the emoji.
- Done when: completion filter tests pass. The sent event has the `<img>` in `formatted_body` and `:name:` in `body` (checked in the event source). Slack shows the emoji (manual check by Patrick). A room with no pack shows no popup. Build, tests, and lint pass.

### Optional story 5: SDK bump for a first-party state read

- Its own story by hard rule 6, with a changelog review. Do it only if unknown 9 shows that the read works. It then replaces the option 1 HTTP call.

---

## Contract §11 amendments needed

1. **Schedule.** §4 lists "Custom emoji/sticker rendering (MSC2545-style packs incoming)" under M4. Stories 1 and 2 are that item. A §11 row must pull it forward, and state the trade under §10.
2. **New scope.** §3 defers "Custom sticker/emoji management". A pick and send of a bridge-made pack's emoji is not management, and no contract line covers it. A §11 row must add "use of bridge image packs in the reaction picker and the composer" and keep pack create, edit, and import deferred.
3. **Architecture decision.** The read path for `m.room.image_pack`: option 1 (one raw client-server GET outside the SDK) or option 2 (wait for an SDK bump). This touches hard rules 1, 5, and 6, so it needs a dated row before story 3.
4. **Operations note.** The pack exists only after `import-image-pack` runs on the bridge. That is a server-side step by Patrick. It stays outside the app (§3, bridge management is out of scope).

## Confidence and gaps

- A1 to A4: high. All from code at a named commit. The deployed bridge can differ (unknowns 1 and 2).
- B1: medium. The image result comes from a read of ZMarkupParser, not from a run.
- B2 to B4: high.
- C: medium. Minified code, read at a few offsets. The Matrix-side source of Beeper's per-account emoji map was not found.
