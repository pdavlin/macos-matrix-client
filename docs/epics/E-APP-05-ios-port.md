# E-APP-05 — iOS/iPadOS Port (PRD)

| | |
|---|---|
| **Epic** | E-APP-05 (Plane MATRIX-31) |
| **Contract basis** | §11 amendment 2026-10-27: iOS/iPadOS as a secondary target, fenced to M1 parity plus push. No trade named (Patrick's decision); the iOS phases run before M2. |
| **Stories** | MATRIX-80 … MATRIX-92 |
| **Status** | Approved 2026-10-27 — Patrick: "build everything as described". 2026-11-09: P1 to P4 code merged (MATRIX-80 to 89, 94, 96, 98, 102, 104, 132). Blocked on MATRIX-92 (developer account), then 90 (Sygnal) and 91 (TestFlight). No device test has run |

## 1. Goal

Replace Beeper Mobile on Patrick's phone with this app. The phone gets the M1
read path, text send, replies, media view, and background notifications. Every
M2/M3 feature stays Mac-first and reaches iOS only by a later §11 row.

Stopgap until TestFlight builds arrive: Element X against davlin.io.

## 2. Decided foundations (do not relitigate)

- **Fence:** M1 parity plus push. Nothing else on iOS without a §11 row.
- **Shared code:** one `MactrixLibrary` for both platforms. Platform-specific
  code lives only in the scroll container, the composer text view, and the
  app shells.
- **iOS timeline (2026-10-27 §11):** `UICollectionView` with
  `UIHostingConfiguration` cells inside `UIViewRepresentable`. It reuses the
  MATRIX-15 methodology: pre-measured heights, measured-delta prepend
  compensation, height fingerprints (MATRIX-63).
- **Glass rule:** navigation layer only, iOS included. The timeline is opaque.
- **Push:** own Sygnal on davlin-matrix with an APNs key for the iOS bundle id.
  A Notification Service Extension decrypts with the SDK.

## 3. Current state (measured 2026-10-27)

| Area | Finding |
|---|---|
| SDK | `matrix-rust-components-swift` 26.04.01 ships `ios-arm64` and `ios-arm64_x86_64-simulator` slices |
| `MactrixLibrary` | `.macOS("26.0")` only. AppKit in 2 of 3 `MessageFormatting` files, 8 of 30 `UI` files, 1 `Utils` file |
| Row layer | `TimelineRow`, `TimelineRowMeasurement`, `ScrollAnchorMath` are portable (AppKit only in comments) |
| App models | 21 files, about 2,700 lines in the Mac app target (`MatrixClient`, `LiveTimeline`, listeners, session) |
| AppKit-heavy app files | `ChatTextView` (composer), `TimelineTableView` (container) |
| Keychain | `kSecAttrAccessibleWhenUnlocked`: an NSE cannot read it while locked |
| Notifications | In-process sync loop: no delivery while iOS suspends the app |

## 4. Verified FFI (pinned 26.04.01, `docs/ffi/matrix_sdk_ffi.swift`)

| Symbol | Line |
|---|---|
| `Client.notificationClient(processSetup:) async throws -> NotificationClient` | 1152 |
| `NotificationProcessSetup.multipleProcesses` | 32752 |
| `NotificationClientProtocol.getNotification(roomId:eventId:) async throws -> NotificationStatus` | 6719 |
| `Client.setPusher(identifiers:kind:appDisplayName:deviceDisplayName:profileTag:lang:) async throws` | 1305 |
| `PusherKind` / `PushFormat` / `HttpPusherData` | 34214 / 34154 / 18906 |
| `ClientBuilder.sessionPaths(dataPath:cachePath:) -> ClientBuilder` | 3576 |

## 5. Stories

| Phase | Story | Plane | Depends on |
|---|---|---|---|
| P0 | Apple Developer Program, ids, keys, Element X stopgap (Patrick) | MATRIX-92 | none |
| P1 | MactrixLibrary compiles for iOS | MATRIX-80 | none |
| P1 | Extract app models into a `Core` library | MATRIX-81 | 80 |
| P2 | iOS app target, scripts, CI simulator build | MATRIX-82 | 81 |
| P2 | Login, session restore, verification, recovery | MATRIX-83 | 82 |
| P2 | Room list, navigation, settings | MATRIX-84 | 82 |
| P3 | `UICollectionView` timeline container | MATRIX-85 | 82 |
| P3 | Composer, text send, replies, media view | MATRIX-86 | 85 |
| P3 | Timeline regression gate on iOS | MATRIX-87 | 85 |
| P4 | App Group store, shared keychain group | MATRIX-88 | 83 |
| P4 | Notification Service Extension, pusher | MATRIX-89 | 88, 90 |
| P4 | Sygnal on davlin-matrix (Patrick: APNs key) | MATRIX-90 | 92 |
| P5 | TestFlight lane (Patrick: ASC key) | MATRIX-91 | 82, 92 |

## 6. Sequencing

1. MATRIX-80 then 81, strictly in order. Both change shared code, and every
   later story builds on them.
2. MATRIX-82 next. After it lands, 83, 84, and 85 can run in parallel: each
   adds files in its own folder of the synchronized iOS group.
3. 86 and 87 after 85. 88 after 83. 89 after 88 and 90.
4. 90 and 91 wait on Patrick's keys (92).

## 7. Exit criteria (binary)

- A TestFlight build on Patrick's phone logs in to davlin.io and decrypts.
- A full day of bridged traffic read and answered on the phone without Beeper.
- A locked phone shows a decrypted notification for a bridged DM.
- The Mac app passes its full test suite with unchanged snapshots after P1.

## 8. Out of scope

The fence of 2026-10-27 is M1 parity plus push. The contract §11 row of
2026-11-25 (Patrick's MATRIX-258 decisions on the parity audit,
`docs/research/ios-parity-audit.md`) moves these into scope:

- Threads: the thread chip and the thread screen (MATRIX-245), and the Slack
  reply rule of MATRIX-232 (MATRIX-246).
- Search over all chats and a Low Priority view, as M1 chat list parity
  (MATRIX-247). This is a search for chats, not the M3 message search.
- The inbox state: archived and snoozed chats leave the list, and a merged
  chat is one row that opens its newest member room, with no merged timeline
  (MATRIX-248).
- Reaction chips that work, with a quick-reaction row in the context menu
  (MATRIX-249, option A).
- An app icon badge that counts chats, as the Mac Dock badge does
  (MATRIX-244).
- Display parity (MATRIX-254), edit and delete of own messages (MATRIX-252),
  and matrix links that open in the app (MATRIX-257).

Still out of scope:

- The rest of M2/M3: forwarding, markdown, mentions, the M3 message search,
  the media browser.
- Deferred: photos and files (MATRIX-251), composer drafts (MATRIX-253).
- Snooze ends and reminders: only the Mac posts them for now (MATRIX-256).
- Share extension, widgets, Android.

## 9. Risks

| Risk | Mitigation |
|---|---|
| P1 refactor breaks the Mac app | No behavior change allowed; snapshot and unit tests gate the PR |
| Parallel P2/P3 branches conflict in the project file | Synchronized folder groups; one folder per story |
| NSE memory limit (about 24 MB) with the SDK | Event-id-only push format; profile on device before shipping |
| Cross-process store access | `multipleProcesses` setup; never run two full sync services |
| Two UIs for every later feature | The fence: iOS changes only by §11 row |
