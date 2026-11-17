# Music link rewrite: research notes

MATRIX-178, step 1. Date: 2026-11-17. This document adds no app code.

Tags: **[seen]** a real response on 2026-11-17, **[doc]** a published source, **[nv]** not verified, **[rec]** a recommendation.

## Summary

- **The Songlink (Odesli) public API is retired.** One real request returned `401 PUBLIC_API_ACCESS_DEPRECATED` [seen]. Linktree's notice says the API retired on 2026-07-31 [doc].
- The story design ("get the Apple Music link from Songlink") cannot be built as written. The owner must make a new decision (Q-1).
- A keyless path that uses only the source service and Apple gave a correct result in one test [seen]: Spotify embed page (title, artist, duration) then iTunes Search API (Apple Music URL).
- Phase 2 does not need the API. `https://song.link/<url>` is the form that Linktree recommends for personal use [doc].
- The owner's choice "the link text is the Apple Music URL" changes the text length after the row has its height. This is against the MATRIX-153 rule unless the rewrite goes through the height fingerprint (B2).

## Findings A: Songlink / Odesli API

### A1. Status today

| Fact | Value | Tag |
|---|---|---|
| Endpoint | `GET https://api.song.link/v1-alpha.1/links` (also `api.odesli.co`) | [doc] 1, 3 |
| Keyless request today | HTTP 401, body `{"statusCode":401,"code":"PUBLIC_API_ACCESS_DEPRECATED"}` | [seen] |
| Retirement | 2026-07-31, whole `v1-alpha.1` namespace. The notice says `410 Gone`. The server sends 401. | [doc] 2 |
| Keys | Linktree stopped the supply of keys. An allowlist form is in the help article, for "apps, tools, or services" with an ongoing need. | [doc] 2, 4 |
| Advice for personal use | "Link to `https://song.link/<your-url>`". No key. | [doc] 2 |
| Landing pages | `song.link` and `album.link` pages continue to work. | [doc] 2, [seen] |

### A2. The API when it worked (history, for an allowlisted key)

Source: the 2019 revision of the official document [doc] 3. The current Notion page needs JavaScript and was not readable [nv].

- Parameters: `url` (encoded), `userCountry` (two letters, default `US`), or `platform` + `type` (`song` or `album`) + `id`. `key` is the API key.
- `songIfSingle` is in a third-party copy of the specification with no description [doc] 4. Its effect is [nv].
- Rate limit: 10 requests each minute with no key, 60 with a key [doc] 3.
- Attribution: "displaying to your users that your feature or product is powered by Songlink". The document says the rule is flexible [doc] 3.
- Terms: `https://song.link/api-terms` governs the API [doc] 3. `odesli.co/terms` sends the reader to a Google Drive file. The text was not read [nv]. No source gives a rule for personal, non-commercial use [nv].
- Errors: 4xx for a bad or stale URL, 5xx for server faults [doc] 3. The exact status and body for a playlist, an artist, an episode, or a song that Apple Music does not have are [nv], because the API gives 401 to all requests.

Response fields that the feature needs [doc] 3:

```json
{
  "entityUniqueId": "ITUNES_SONG::1443109064",
  "userCountry": "US",
  "pageUrl": "https://song.link/us/i/1443109064",
  "entitiesByUniqueId": {
    "ITUNES_SONG::1443109064": { "id": "1443109064", "type": "song", "platforms": ["appleMusic", "itunes"] }
  },
  "linksByPlatform": {
    "appleMusic": {
      "url": "https://music.apple.com/us/album/kitchen/1443108737?i=1443109064&uo=4&app=music&ls=1&at=1000lHKX",
      "nativeAppUriMobile": "music://music.apple.com/us/album/kitchen/1443108737?i=1443109064&uo=4&app=music&ls=1&at=1000lHKX",
      "nativeAppUriDesktop": "itms://music.apple.com/us/album/kitchen/1443108737?i=1443109064&uo=4&app=music&ls=1&at=1000lHKX",
      "entityUniqueId": "ITUNES_SONG::1443109064"
    }
  }
}
```

- Song or album: `entitiesByUniqueId[entityUniqueId].type`. A platform key is absent from `linksByPlatform` when there is no match.
- The Apple URL has an affiliate token (`at=`) and tracking parameters (`uo`, `ls`). Remove them before display [rec].

### A3. The landing page is not a substitute for the API

Two fetches of `https://song.link/https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT` [seen]:

- 308 then 302 to `https://song.link/s/4cOdK2wGLETKBW3PvgPWqT`, then 200 HTML with a `__NEXT_DATA__` JSON block.
- `pageData.entityData` has `type: "song"`, `title`, `artistName`, `isrc`, `duration`.
- The `appleMusic`, `itunes`, `youtube` and `soundcloud` link entries have **no `url`** in the server HTML, in the two fetches. Deezer, Tidal, Amazon and others have a URL.
- The page does not give the Apple Music URL to a non-browser client. A scrape is also outside what Linktree offers. Do not build on it [rec].

### A4. Platform keys (for "every service Songlink knows")

`spotify, itunes, appleMusic, youtube, youtubeMusic, google, googleStore, pandora, deezer, tidal, amazonStore, amazonMusic, soundcloud, napster, yandex, spinrilla` [doc] 3, plus `audius, anghami, boomplay, audiomack` [seen] and `bandcamp` [doc] 4.

## Findings B: paths that work today

### B1. Direct path: source service, then Apple [seen]

Three requests for one public track (Rick Astley, "Never Gonna Give You Up"):

1. `GET https://open.spotify.com/oembed?url=<track url>`: 200, keyless. It gives `title` only, no artist. Spotify documents this endpoint for track, album, artist, show and episode, not playlist [doc] 5. Title only is too weak for a match.
2. `GET https://open.spotify.com/embed/track/<id>`: 200 HTML. The embedded JSON has `name`, `artists[].name`, `duration` (ms) and `releaseDate`. This page is the iframe target of the oEmbed response. It is not a documented data API [nv for stability].
3. `GET https://itunes.apple.com/search?term=<artist+title>&country=US&media=music&entity=song&limit=3`: 200, keyless. Limit: "approximately 20 calls per minute" [doc] 6. Apple tells large sites to cache [doc] 6.

Fixture, Spotify embed page (trimmed to the fields in the page JSON) [seen]:

```json
{ "name": "Never Gonna Give You Up",
  "artists": [{ "name": "Rick Astley", "uri": "spotify:artist:0gxyHStUsqpMadRV0Di1Qt" }],
  "duration": 213573,
  "releaseDate": { "isoString": "1987-11-12T00:00:00Z" } }
```

Fixture, iTunes Search (trimmed, 3 results) [seen]:

```json
{ "resultCount": 3, "results": [
  { "wrapperType": "track", "kind": "song", "artistName": "Rick Astley",
    "trackName": "Never Gonna Give You Up", "trackId": 1559885421, "collectionId": 1559885420,
    "trackTimeMillis": 213573,
    "trackViewUrl": "https://music.apple.com/us/album/never-gonna-give-you-up/1559885420?i=1559885421&uo=4" },
  { "wrapperType": "track", "kind": "song", "artistName": "Rick Astley",
    "trackName": "Never Gonna Give You Up (Cake Mix)", "trackId": 1612648434, "collectionId": 1612648318,
    "trackTimeMillis": 347427,
    "trackViewUrl": "https://music.apple.com/us/album/never-gonna-give-you-up-cake-mix/1612648318?i=1612648434&uo=4" },
  { "wrapperType": "track", "kind": "song", "artistName": "Rick Astley",
    "trackName": "Never Gonna Give You Up (2022 Remaster)", "trackId": 1624945512, "collectionId": 1624945511,
    "trackTimeMillis": 213560,
    "trackViewUrl": "https://music.apple.com/us/album/never-gonna-give-you-up-2022-remaster/1624945511?i=1624945512&uo=4" } ] }
```

Fixture, Songlink API today [seen]: `{"statusCode":401,"code":"PUBLIC_API_ACCESS_DEPRECATED"}`

- The first result has the same artist, the same title and the same duration to the millisecond (213573). A match rule of "artist equal, title equal after normalization, duration within 2 s" selects it and rejects the Cake Mix.
- The match is a heuristic. A remaster, a live take or a cover can pass or fail it. No match must leave the original link (already in the design).
- Albums: `entity=album` gives `collectionViewUrl` [doc] 6. The Spotify embed page for an album was not fetched [nv].
- Other source services each need their own metadata step. This path covers Spotify first and no other service on day one.

### B2. Other paths

| Path | Facts | Tag |
|---|---|---|
| Songlink allowlist | Form in the help article. Result and time are unknown. A one-user client is the "personal use" case that Linktree sends to the landing page. | [doc] 2 |
| MusicLink (`api.musiclink.one/v2/resolve?q=`) | Bearer key. Free: 300 requests each month, personal projects only, attribution necessary. One person operates it. Album input is not documented. | [doc] 7 |
| SongPort | Tracks only. Keys by hand, waitlist. | [doc] 8 |
| MusicKit ISRC lookup | `MusicCatalogResourceRequest<Song>(matching: \.isrc, ...)` exists. It needs the MusicKit App Service on the App ID. A keyless source for the Spotify ISRC was not found. User authorization for catalog requests is [nv]. | [doc] 9 |
| `song.link/<url>` as the link target | Zero requests at render time. One more click in a browser. Against the owner's "link text is the Apple Music URL". | [doc] 2 |

## Findings C: Spotify URL forms

| Form | Classifier result | Tag |
|---|---|---|
| `open.spotify.com/track/<22 base62>` | song | [seen] |
| `open.spotify.com/album/<id>` | album | [doc] 5 |
| `open.spotify.com/intl-<locale>/track/<id>` | song. Remove the prefix. | [nv], no source found |
| `?si=`, `?context=`, `?nd=` and all other query items | Ignore. Build the canonical URL from type and ID. `si` identifies the share. | [nv], forum posts only 10 |
| `spotify:track:<id>`, `spotify:album:<id>` | song, album. The old API took this form. | [doc] 3 |
| `spotify.link/<code>` | Needs a resolve. Forum reports: no 301/302, a JavaScript redirect, and Spotify's oEmbed gives 404 for it. | [nv] 10 |
| `spotify.app.link/<code>` | Branch link. Same problem. | [nv] 10 |
| `/playlist/`, `/artist/`, `/show/`, `/episode/`, `/user/` | Reject. No request. | by design |

- Send only the canonical `https://open.spotify.com/<type>/<id>`. This removes `si`, which identifies the friend's share [rec].
- Leave short links as they are in phase 1 [rec]. A resolve needs an HTML fetch and a parse of script text.

Patterns for other services (from Songlink page data for one track [seen], types [nv]):

| Service | Song pattern | Album and other |
|---|---|---|
| YouTube Music | `music.youtube.com/watch?v=<id>` [doc] 3 | `/playlist?list=OLAK5uy_...` is an album, other lists are playlists [nv] |
| Tidal | `listen.tidal.com/track/<id>`, `tidal.com/browse/track/<id>` [nv] | `/album/<id>`; reject `/playlist/`, `/artist/` |
| Deezer | `www.deezer.com/track/<id>` | `/album/<id>`; reject `/playlist/`, `/artist/`; `deezer.page.link` short links [nv] |
| Amazon Music | `music.amazon.com/albums/<asin>?trackAsin=<asin>` | `/albums/<asin>` with no `trackAsin` is an album |
| SoundCloud | `soundcloud.com/<user>/<slug>` | `/<user>/sets/<slug>` is a set (album or playlist, not distinguishable from the URL) |
| Bandcamp | `<artist>.bandcamp.com/track/<slug>` [nv] | `/album/<slug>` |

## Findings D: Apple Music result

- Storefront: the path segment after the host (`music.apple.com/us/...`). The old API took it from `userCountry` and could fall back to a match from a different country [doc] 3. iTunes Search takes `country=US` and gave `/us/` URLs [seen].
- Song form: `/album/<slug>/<collectionId>?i=<trackId>`. Album form: no `i` item.
- Remove `uo=4` (and `at`, `ls`, `app` from Songlink data) for a clean display URL [rec].
- An `https://music.apple.com/...` URL is a universal link. Reports say it opens the Music app from system apps on iOS; `music://` matters for in-app browsers [nv] 11. The old API gave `music://` for mobile and `itms://` for desktop [doc] 3. One forum thread reports an error screen for a `music://music.apple.com/...` catalog link [nv] 11.
- macOS behaviour for an `https` link from `NSWorkspace.open` is [nv]. Test by hand on the Mac: `https` form first, then `music://` with the same host and path [rec]. Keep the `https` URL as the visible text and the copy value in all cases.

## Findings E: this app today

Body render path:

- `Mactrix/Views/ChatView/FormattedBodyView.swift`, `FormattedBodyView.body`: selects jumbo text, `FormattedBodyText` (HTML body), or `Text(rawBody)` (plain body).
- `MactrixLibrary/Sources/MessageFormatting/FormattedBodyText.swift`, `FormattedBodyText.attributedBody(arrivals:)` and its `.task(id: html)`.
- `MactrixLibrary/Sources/MessageFormatting/Parser.swift`, `parseFormattedBody(_:baseFontSize:imageLoader:)` and `renderHTML(_:baseFontSize:)` (ZMarkupParser makes the link attributes from `<a href>`).
- `MactrixLibrary/Sources/MessageFormatting/ImageTagRewriter.swift`, `ImageTagRewriter.rewrite(_:)`: the precedent for an HTML rewrite before the renderer.
- `MactrixLibrary/Sources/MessageFormatting/EmoticonAttachment.swift`, `EmoticonResolver.resolve(...)`: the precedent for an inline fixed-size glyph after the renderer.
- A grep finds no `NSDataDetector` and no other link detection. **A plain body draws through `Text(rawBody)`, so a bare URL in a plain body is not a link today** (runtime check [nv]). Many bridged messages have no HTML body.

Late content rule (MATRIX-153):

- `FormattedBodyText` doc comment: the body draws at once from the cache, each arrival draws again in place, and "the squares do not change size, so the height is the same before and after".
- `MactrixLibrary/Sources/Models/TimelineRowHeightFingerprint.swift`, `MessageBodyGeometry` (`text`, `formattedText`): all height inputs go here, decided once for each mapped item. `MactrixLibrary/Sources/Core/TimelineRowHeightFingerprint+SDK.swift` fills it.
- The rule: late content must not change the row height. A height input must be in the fingerprint so that a change always measures the row again.

Attach point [rec]:

1. A pure classifier and rewrite in `Models` (URL in, `song` / `album` / `reject` and canonical URL out; body strings in, rewritten strings out). Unit tests use the fixtures above.
2. The mapper applies the cached result **before** it builds `MessageBodyGeometry`, so `text` / `formattedText` hold the displayed strings. A cache arrival maps the row again, and the fingerprint change measures the row again, as an edit does. Do not swap the text in `FormattedBodyText` with an `arrivals`-style counter: an Apple Music URL is longer than a Spotify URL and can add a line.
3. The glyph is a fixed-size attachment next to `EmoticonResolver.resolve` in `parseFormattedBody`. The underline is a link attribute there.
4. A plain body with a rewrite must go through the HTML path (make `<a href>` from the escaped body), because `Text(rawBody)` has no links.
5. Copy, reply, quote and edit read the event content, not the displayed strings. Verify each of these call sites in the build story.

## Proposed contract §11 row (text only)

> | 2026-11-17 | **Amendment: music link rewrite, a new outbound request class (MATRIX-178).** Patrick asked for it in session. When a message on screen has a link to a song or an album on a music service that is not Apple Music, the client finds the Apple Music link and shows it in place of the original, as a display-only change; the Matrix event does not change, and copy, reply, quote and edit use the original text. **New request class:** part of a URL that another person posted goes to hosts that are not the homeserver. Sent: the canonical catalog URL or ID (type and ID only) to the source service's public endpoint, and the artist and title text to Apple's iTunes Search API with `country=US`. Not sent: query parameters of the posted URL (`si` and all others), the room, the sender, the event ID, the Matrix user ID, the message text, an account identifier, or a cookie. Requests go from the client's IP address with a generic User-Agent, only for rows on screen, through one queue below 20 requests each minute, and each result (also a negative result) stays in a local cache with an expiry. Playlist, artist, show, episode and user links cause no request. No match or an error leaves the original link with no marker. **Off switch:** one setting stops all requests of this class and all rewrites; the default is [Q-6]. The Songlink (Odesli) API of the first design retired on 2026-07-31; research: `docs/research/music-link-rewrite.md`. |

Change the host list in the row if the owner selects a different path in Q-1.

## Risks and open questions

| ID | Question or risk | Recommended default |
|---|---|---|
| Q-1 | The Songlink API is retired. Which resolver? | Direct path B1 for Spotify only. In parallel, send the allowlist form; it costs one form. Do not use MusicLink: a bearer key in a client, 300 requests each month, one operator. |
| Q-2 | "Every service Songlink knows" is not possible with no aggregator. | Phase 1 is Spotify only. Add a service only when a friend posts its links. |
| Q-3 | The Spotify embed page is not a documented API and can change. | Accept. Parse with care, treat a parse failure as no match, and put one fixture test on the parser. Negative cache 24 h, positive cache 90 days. |
| Q-4 | A heuristic match can select the wrong take (remaster, live, cover). | Require the same artist, the same normalized title, and duration within 2 s. With no such result, leave the original link. Show the original URL in a tooltip and in the context menu. |
| Q-5 | The longer Apple URL can change the row height after first draw. | Rewrite through the height fingerprint (E, item 2). Alternative for the owner: keep the original text, change only the target and add the glyph. This needs no new measure. |
| Q-6 | Default of the off switch. The feature sends data about a friend's post to Spotify and Apple. | On, because the owner asked for the feature and the source host is the host of the link. Record it in the §11 row. |
| Q-7 | `spotify.link` and `spotify.app.link` short links. | Leave as they are in phase 1. Count how frequently they occur before more work. |
| Q-8 | Plain bodies have no links today. | Decide in the build story if all plain-body URLs become links, or only rewritten music links. Default: only rewritten links, to keep the story small. |
| Q-9 | Phase 2 pageUrl with no API. | Build `https://song.link/<Apple Music URL>` in the client, no request. Check by hand that the page resolves for one song and one album before the story starts [nv]. |
| Q-10 | `https` or `music://` to open the Music app on macOS. | `https` as text and copy value. Decide the open form after a hand test (D). |

## Real requests made (6 in total, public catalog URLs only)

1 to `api.song.link` (401). 2 to `song.link` (landing page). 1 to Spotify oEmbed. 1 to the Spotify embed page. 1 to iTunes Search. No more requests went to the Songlink API after the 401, because each one gives the same body.

## Sources

1. https://jentic.com/apis/odesli.co/odesli.md (third-party copy of the specification; saw HTTP 200 on 2026-08-12)
2. https://linktr.ee/help/en/articles/15201827-sunsetting-the-songlink-odesli-public-api (updated 2026-10-14)
3. https://github.com/songlink/docs/blob/48b8b69b9f43e672d989e47413f966fb27c435c5/api-v1-alpha.1.md (official, 2019 revision)
4. https://linktree.notion.site/API-d0ebe08a5e304a55928405eb682f6741 (current official page, read only through search snippets) and https://packagist.org/packages/omnisong/odesli (401 seen 2026-10-03)
5. https://developer.spotify.com/documentation/embeds/reference/oembed
6. https://performance-partners.apple.com/search-api
7. https://musiclink.one/
8. https://songport.link/blog/odesli-api-alternative (401 seen 2026-09-22)
9. https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api and https://developer.apple.com/forums/thread/686500
10. https://community.spotify.com/t5/Spotify-for-Developers/How-to-see-through-shortened-https-spotify-link-links/td-p/5521244
11. https://linklyhq.com/support/apple-music-open-links-in-app and https://developer.apple.com/forums/thread/712569
