# iOS parity audit

MATRIX-238. Audit of 2026-11-24, main at `f26045f`. Read-only: no build, no test run, no app or simulator launch. The audit is the input for the next iOS stories.

Sources:

- The Plane export of MATRIX-82 to MATRIX-237 (156 stories, descriptions and comments).
- `docs/epics/E-APP-05-ios-port.md` (§8 is the fence), `docs/PROJECT_CONTRACT.md` §3 and §11, `docs/STATUS.md` (snapshot of 2026-11-13, older than this audit).
- The code: `MactrixiOS/`, `MactrixNotificationService/`, `MactrixLibrary/Sources/`, `Mactrix/`, `Mactrix.xcodeproj/project.pbxproj`.
- `git log` and `git show --stat` for each story commit. The CI result of main from `gh run list` (read only).

Status words in the tables:

- **on iOS**: the iOS target has the behavior in its code. No row has had a device test. No iOS build has run on a phone.
- **partial**: the iOS target has a part of the Mac behavior. The cell says which part.
- **Mac only**: the Mac has the behavior and iOS does not. No fence text names it. To reach iOS it still needs a §11 row, because the fence is "M1 parity plus push".
- **deferred by the fence**: E-APP-05 §8 names the feature (edits, reactions, redactions, forwarding, markdown, mentions, search, media browser), or the story says that iOS is out of scope by the fence or that "M2 is Mac-only".
- **unknown**: the code does not show the iOS behavior clearly.
- **n/a**: the story changes no app behavior (tooling, tests, research, epics, backlog with no code).

## 1. Summary

The iOS app is the M1 shell that merged on 2026-11-04 (MATRIX-82 to 89, 94, 96, 98, 102, 104, 132), plus a few shared-code pickups. Of the 156 stories, 25 are **on iOS** (15 of them are iOS port stories), 11 are **partial**, 72 are **Mac only**, 15 are **deferred by the fence**, 1 is **unknown**, and 28 are **n/a**. Three are open prerequisites (MATRIX-90, 91, 92), and one is an open iOS defect (MATRIX-231). After the iOS merge, the Mac stories that changed iOS files are MATRIX-122, 153, 156, 163, 211, 220, 230 (a test fixture only), 233 and 236.

The three most important findings:

1. **Threads do not show on iOS.** The shared main timeline hides threaded events (`Core/LiveTimeline.swift:178`, `hideThreadedEvents: true`). iOS draws no thread summary and has no thread screen. Since MATRIX-232 every Mac reply in a Slack room goes into a thread, so those replies are not on the phone. An iOS reply is a plain reply, so the two devices put replies in different places.
2. **Nothing can run on the phone yet.** MATRIX-92 is In Progress with no Team ID in the export. All 12 build configurations still sign with the personal team `2BGS8RA3P5`. Push needs MATRIX-92, then MATRIX-90, and MATRIX-91 or a Debug-push decision.
3. **The iOS chat list and notifications do not follow the Mac.** Archived and snoozed chats show, merged chats show as separate rows, low-priority chats do not show and cannot be reached, and the list holds at most 100 chats with no search. A tap on a notification does not open its chat, and the app icon has no badge.

## 2. Prerequisites to run on a phone

| Story | State in the export | What it gives | Who |
|---|---|---|---|
| MATRIX-92 | In Progress. Enrollment submitted 2026-11-04. No Team ID comment in the export | Paid team and Team ID, identifiers, device registration, APNs key, App Store Connect record, ASC API key secrets, the Debug-push decision | Patrick |
| MATRIX-90 | Todo | Sygnal on davlin-matrix for app id `io.davlin.matrixclient.ios` at `https://davlin-matrix.exe.xyz/_matrix/push/v1/notify` (`Core/AppGroup.swift`, `PushGateway`) | Agent, with Patrick for the APNs key and one SSH session (Touch ID) |
| MATRIX-91 | Todo | TestFlight build from GitHub Actions, internal testing only | Agent, with Patrick for the ASC record and the three secrets |

What blocks a device install:

- MATRIX-92 steps 1 to 4: an approved enrollment, the Team ID, the identifiers (App Group `group.io.davlin.matrixclient`, App ID `io.davlin.matrixclient.ios` with Push Notifications and App Groups, App ID `io.davlin.matrixclient.ios.notifications` with App Groups), Developer Mode on the iPhone, and one Xcode build that registers the device.
- A team-switch story. `DEVELOPMENT_TEAM = 2BGS8RA3P5` is in 12 build configurations of `Mactrix.xcodeproj/project.pbxproj`, not the 10 that MATRIX-92 names. MATRIX-88 says that device entitlements need the paid team.
- **unknown**: whether the free personal team can sign the App Group and keychain group entitlements for a cable install. Nobody tested it.
- An install with no cable (TestFlight) also needs MATRIX-91, which needs MATRIX-92 steps 6 and 7.

What blocks push:

- MATRIX-92 step 5 (the APNs key), then MATRIX-90 (Sygnal) in a session with Patrick present.
- The APNs environment. A build that Xcode installs uses the APNs sandbox. A TestFlight build uses production. Sygnal sends one app id to one environment, and the app registers one app id. So only TestFlight builds get push, unless Patrick decides on a second Debug app id (`io.davlin.matrixclient.ios.dev`) and a sandbox entry in Sygnal (MATRIX-92 open decision). `MactrixiOS/MactrixiOS.entitlements` has `aps-environment = development`.
- So push on the phone needs MATRIX-92 steps 5 to 7, MATRIX-90 and MATRIX-91, or MATRIX-92 step 5, MATRIX-90 and the Debug-push decision.
- When push works, the tap and badge gaps (D5, D10) still apply.

## 3. Parity table per area

Paths in `MactrixLibrary/Sources/` start at the library name (`Core/`, `UI/`, `Models/`, `MessageFormatting/`, `Utils/`).

### 3.1 iOS port and iOS fixes

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-82 | n/a (iOS target, scripts, CI simulator build) | **on iOS** | `dec29bc`. CI run 45499188235 at `f26045f` passed, with its "Build iOS (Simulator)" and "Test iOS (Simulator)" steps |
| MATRIX-83 | Sign-in, restore, verification, recovery | **on iOS** | `a1ff7a0`, `MactrixiOS/Login/`, `MactrixiOS/Verification/` |
| MATRIX-84 | Room list, iPhone stack, iPad split, settings | **on iOS** (its own scope). The story defers inbox rows, labels, room search and the sync line | `3a3108d`, `MactrixiOS/Rooms/RoomNavigationShell.swift` |
| MATRIX-85 | n/a (iOS `UICollectionView` timeline) | **on iOS** | `4e2d20b`, `MactrixiOS/Timeline/` |
| MATRIX-86 | Composer, text send, replies, media view | **on iOS**. Drafts deferred (§11 row (g)) | `2e1edec`, `MactrixiOS/Composer/`, `MactrixiOS/Media/` |
| MATRIX-87 | n/a (iOS timeline gate) | **on iOS** (DEBUG harness). The device pass waits on MATRIX-92 | `34ad336`, `MactrixiOS/Timeline/Gate/` |
| MATRIX-88 | n/a (App Group store, shared keychain group) | **on iOS** in code. Device entitlements need the paid team | `1d0bb92`, `MactrixiOS/MactrixiOS.entitlements` |
| MATRIX-89 | n/a (Notification Service Extension, pusher) | **on iOS** in code. No push can arrive before MATRIX-90 | `a595198`, `MactrixNotificationService/NotificationService.swift` |
| MATRIX-94 | Device name "Round", user agent "Round macOS" | **on iOS**: "Round (iPhone)", "Round (iPad)", "Round iOS" | `9cdf1a0`, `Utils/ClientIdentity.swift` |
| MATRIX-96 | Mac keeps the single-process default | **on iOS**: lock holders "app" and "nse" | `9aea87c` |
| MATRIX-97 | Session delegate on the Mac sign-in client | **on iOS** since MATRIX-96 | `2eca1dc`, `08c3782` |
| MATRIX-98 | n/a (iOS layout and width-change cost) | **on iOS**. Device pass open (MATRIX-92 comment) | `634ff59` |
| MATRIX-102 | n/a (open the live timeline from the list) | **on iOS** | `af442ab`, `MactrixiOS/Rooms/LiveRoomScreen.swift` |
| MATRIX-104 | Accept and Reject for an invite | **on iOS** | `cb8bae1`, `MactrixiOS/Rooms/RoomInvite.swift` |
| MATRIX-132 | n/a (stop the batch after a resync). State: Review | **on iOS**. Device check open | `119bd8e`, `MactrixiOS/Timeline/TimelineCollectionUpdates.swift` |
| MATRIX-231 | n/a (Backlog, iOS twin of MATRIX-230) | Open defect, see D3 | `MactrixiOS/Timeline/TimelineRowContent.swift:301`, `:322` |

### 3.2 Timeline and rendering

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-113 | Whole-message selection, transcript copy | **deferred by the fence**. iOS copies one message from the context menu | `2553bf6`, `TimelineRowContent.swift:292` |
| MATRIX-130 | SIGBUS fix in the Mac timeline snapshot update | **Mac only**. The iOS twin is MATRIX-132 | `8611606` |
| MATRIX-135 | Capsule reaction chips, press scale, hover reveal, motion tokens | **partial**: the chips are the shared `UI.MessageReactionView`. No hover on iOS | `f186f71` |
| MATRIX-136 | Jump flash, "New" divider, day pill, sticky day pill | **partial**: the "New" divider and the day pill are the shared `UI.VirtualItemView`. The sticky pill and the jump flash are in the Mac container | `7f10be0`, `UI/Timeline/TimelineDividers.swift` |
| MATRIX-137 | Jumbo emoji, 1 to 9 emoji at 40 pt | **Mac only**. The story defers the iOS timeline | `a75da27`, `Mactrix/Views/ChatView/FormattedBodyView.swift:57` |
| MATRIX-145 | One floating hover bar | **Mac only**. The story drops iPad pointer hover | `d18c902` |
| MATRIX-157 | Day dividers by calendar day, updated at midnight | **on iOS** | `d8381ea`, `UI/Timeline/TimelineDividers.swift:24` (`CurrentDay.shared`) |
| MATRIX-182 | Equal row update skips the body parse, and an emoticon render cache | **partial**: the cache in the shared `FormattedBodyText` applies. The parse skip is in the Mac `ChatMessageView` | `e13e65f` |
| MATRIX-190 | Pointing hand over body links | **Mac only** (pointer) | `ed60169` |
| MATRIX-192 | A block quote body shows all lines | **unknown**: the parser indent and color are shared. The measure fix is in the AppKit `AttributedTextView`. The story says the iOS path is not tested | `e8659f5` |
| MATRIX-193 | Rolling unread and reaction counts | **partial**: reaction counts roll (shared `MessageReactionView`). The unread count is in the Mac chat list | `4696b43` |
| MATRIX-196 | Scroll edge effect under the toolbar | **Mac only** | `a2d4f34` |
| MATRIX-197 | Scroll anchor through a live window resize | **Mac only**. iOS has its own width-change path (MATRIX-98) | `23a38e2` |
| MATRIX-198 | Timeline scrolls under the glass composer | **Mac only** | `2de83e8` |
| MATRIX-199 | Quick Look from the timeline | **Mac only**. iOS has its own full-screen viewer (MATRIX-86) | `c4549e5`, `MactrixiOS/Media/MediaViewer.swift` |
| MATRIX-202 | Code text in Berkeley Mono when installed | **on iOS**, with the Menlo fallback. Not verified | `7c6cebe` |
| MATRIX-204 | Body text keeps its color in dark mode after a click | **on iOS**: the UIKit branch sets `UIColor.label` | `077ec64`, `MessageFormatting/AttributedTextView.swift` |
| MATRIX-205 | Pointing hand over the thread pill and chips | **Mac only** (pointer) | `5a9c58d` |
| MATRIX-220 | A measured row runs none of its actions | **on iOS** | `3cf90ea`, `MactrixiOS/Timeline/TimelineCollectionController.swift` |
| MATRIX-230 | A reply row takes the height of its loaded quote, with a 10 pt gap | **partial**: the fingerprint change is shared. The re-measure and the gap are Mac only (MATRIX-231) | `2b07e8f`, `Mactrix/Views/ChatView/TimelineView/TimelineReplyQuoteHeights.swift` |

### 3.3 Composer and send

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-105 | Mentions autocomplete with chips | **deferred by the fence** | `4987ca5` |
| MATRIX-106 | Media send: picker, paste, drag and drop | **deferred by the fence** | `3209280` |
| MATRIX-107 | Upload progress in the row | **deferred by the fence** | `7ae2c66` |
| MATRIX-109 | Edit authoring | **deferred by the fence**. iOS shows the edited mark | `e2062a6`, `TimelineRowContent.swift:374` |
| MATRIX-110 | Redaction | **deferred by the fence**. iOS shows "Message redacted" | `c183467`, `TimelineRowContent.swift:382` |
| MATRIX-112 | Forward text and media | **deferred by the fence** | `4d63177` |
| MATRIX-188 | Opening a chat puts the focus in the composer | **Mac only** | `2288e4d` |
| MATRIX-195 | Composer buttons in one morphing glass container | **Mac only**. iOS has its own `ComposerBar` | `e8515c4` |
| MATRIX-234 | Composer emoji button opens the app picker | **Mac only**. iOS uses the system keyboard emoji | `9047484` |

### 3.4 Message actions

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-108 | One action model for the context menu, hover row and Edit menu | **partial**: iOS has its own context menu with Reply and Copy only | `0bc2161`, `TimelineRowContent.swift:286` |

### 3.5 Threads and replies

The shared main timeline hides threaded events (`Core/LiveTimeline.swift:178`). iOS has no thread summary: `MessageThreadSummary` is used only at `Mactrix/Views/ChatView/ChatMessageView.swift:305`. Contract §3 defers threads "beyond rendering a thread exists affordance", so a summary chip is in scope, and a thread screen needs a §11 row.

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-169 | A reply to a thread goes into the thread, and panel fixes | **Mac only** | `2ed305f` |
| MATRIX-173 | Notice for a thread reply that was not sent | **Mac only**. The story says that iOS does not show it | `3d66867` |
| MATRIX-183 | Thread panel hierarchy | **Mac only** | `d48094d` |
| MATRIX-200 | Threads pane lists the room's threads | **Mac only** | `259ddd1` |
| MATRIX-216 | First reply in a new thread goes into the thread | **Mac only** | `9db6d95` |
| MATRIX-229 | Thread panel loads the whole thread | **Mac only** | `0b4bd69` |
| MATRIX-232 | In a Slack room every reply goes into a thread | **deferred by the fence** (story text). iOS sends `sendReply` on the live timeline | `4d2a4cc`, `MactrixiOS/Composer/LiveComposerTarget.swift:35` |

### 3.6 Reactions and emoji

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-111 | Reaction picker with SDK recent emoji | **deferred by the fence**. iOS draws the chips, and a tap does nothing (D4) | `7b3b8ee`, `TimelineRowContent.swift:194` |
| MATRIX-138 | Picker popover fix | **Mac only** | `8d72ed3` |
| MATRIX-151 | Custom emoji research spike | **n/a** | `addcbdd` |
| MATRIX-153 | Slack custom emoji in bodies | **on iOS** | `74c0182`, `TimelineRowContent.swift:354` |
| MATRIX-154 | An `mxc://` reaction key draws as an image | **on iOS** (display only, not verified) | `9fa2a11`, `UI/Timeline/ReactionKeyLabel.swift` |
| MATRIX-155 | Workspace image pack in the picker | **deferred by the fence** (reactions) | `d250129` |
| MATRIX-156 | Insert a workspace emoji in the composer | **Mac only**. The story defers the iOS composer. iOS Copy gives `:name:` | `b971809`, `TimelineRowContent.swift:254` |
| MATRIX-159 | Body emoticons found without `data-mx-emoticon` | **on iOS** (shared parser) | `f553816`, `MessageFormatting/ImageTagRewriter.swift` |
| MATRIX-161 | Refresh and learn custom emoji while the app runs | **Mac only**. The story: "iOS does not report emoticons" | `465bb7f` |
| MATRIX-162 | Jumbo custom emoji | **Mac only**. The story defers iOS | `cd49c30` |
| MATRIX-166 | A chip tooltip lists who reacted | **Mac only** (`UI/Timeline/ReactionChipToolTip.swift` has a macOS guard) | `588fb1e` |

### 3.7 Chat list and filters

The iOS row is the old `UI.RoomRow`: the name, a 22 pt avatar, an unread badge and a mute mark (`MactrixiOS/Rooms/RoomListView.swift:57`). It has no preview line and no time. The list has the old Favorites, Direct Messages and Rooms sections (`MactrixiOS/Rooms/RoomListItem.swift`, `RoomListSections`).

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-121 | Joined spaces show no Join link | **Mac only**. iOS hides spaces | `65d0994` |
| MATRIX-123 | Dense rows with previews | **Mac only** | `22f14cc` |
| MATRIX-129 | Group bubble avatars, colored initials | **Mac only** | `5589257` |
| MATRIX-133 | Bubbles from the member list | **Mac only** | `4465448` |
| MATRIX-150 | Pinned grid on the list layout | **Mac only**. iOS has a Favorites section | `af9bfa3` |
| MATRIX-180 | Low priority chats add nothing to a rail badge | **Mac only**. iOS does not show low-priority chats at all (D8) | `ee3de7e`, `Core/ChatList+SDK.swift:204` |
| MATRIX-185 | Pinned grid names centered | **Mac only** | `0160eb9` |
| MATRIX-194 | Bridge network badge on avatars | **Mac only** | `efb98b4` |
| MATRIX-225 | Settle spring, unread badge pop, entrance motion | **Mac only** | `dc63cf6` |
| MATRIX-226 | Active filter chip in the sidebar header | **Mac only** | `ca87bf1` |

### 3.8 Inbox flow

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-206 | Archive chats | **Mac only**. iOS shows archived chats in its list (D7) | `5a7c515`, `Mactrix/Views/Sidebar/SidebarView.swift:60` (`ChatListMerging.visible`) |
| MATRIX-207 | Snooze and Remind me later | **Mac only**. iOS shows snoozed chats. Snooze ends and reminders fire on macOS only | `a4c44bb`, `Core/MatrixClient+Listeners.swift:209` |
| MATRIX-222 | Next chat after Archive, Snooze or Mark Read, and Archive All Read | **Mac only** | `9844463` |
| MATRIX-223 | Next Unread Chat key | **Mac only** | `081fcf6` |
| MATRIX-235 | ⌘E archives the selected chat | **Mac only** | `937af4b` |

### 3.9 Drafts and typing

iOS draws the typing row (`UI.TypingIndicatorRow`) and sends typing notices (`LiveComposerTarget.noteTyping`), from MATRIX-85 and 86.

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-224 | Draft prefix and typing state on rows, and the Unanswered and Drafts filters | **Mac only**. iOS has no drafts. The shared `startSync()` still loads the drafts of every room on iOS (D13) | `6f8dcec`, `Core/MatrixClient+Sync.swift:139` |

### 3.10 Spaces and labels

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-167 | Spaces on the sidebar rail as filters | **Mac only**. iOS hides spaces | `38a0fd7` |
| MATRIX-170 | Space launch cache | **Mac only**. The Core work runs on iOS too (D13) | `2099855` |
| MATRIX-171 | Space data after an offline launch, and the own image after a new Slack login. State: Review | **Mac only** | `11faa5e` |
| MATRIX-186 | A late space graph keeps the launch cache | **Mac only** | `c11b7ab` |
| MATRIX-217 | ⌘1 to ⌘9 rail items, ⌘[ and ⌘] chats | **Mac only** | `17182b1` |
| MATRIX-227 | Rail name peek | **Mac only** | `fc43252` |

### 3.11 Merged chats

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-139 | Merged chats epic | **Mac only** | `8466f76` |
| MATRIX-140 | Storage and model in account data | **Mac only**. The model loads on iOS, and no iOS view reads it | `73b2738`, `Core/MatrixClient+Sync.swift:87` |
| MATRIX-141 | Merged rows, merge and unmerge UI | **Mac only**. iOS shows each member room as its own row | `3df5775` |
| MATRIX-142 | Merged timeline | **Mac only** | `bdfba44` |
| MATRIX-143 | Composer target and action routing | **Mac only** | `b3c7022` |
| MATRIX-144 | Notification remap, one badge count | **Mac only**. The extension does not remap | `b101e5b` |
| MATRIX-147 | Member labels by network and workspace | **Mac only** | `c374a48` |
| MATRIX-148 | Workspace icon as the avatar badge | **Mac only** | `70f5888` |
| MATRIX-149 | Edit menu and inspector for merged chats | **Mac only** | `de4de46` |
| MATRIX-189 | Favorite a merged chat | **Mac only** | `2afc210` |

### 3.12 Notifications and push

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-119 | Dock badge with the unread chat count | **Mac only**. `DockBadgeController.start` is a no-op on iOS. No app icon badge (D10) | `c610c58`, `Core/DockBadgeController.swift` |
| MATRIX-146 | Communication notifications (Backlog) | **n/a** | export |
| MATRIX-184 | Low priority chats add nothing to the Dock badge | **Mac only** | `c8316dc` |
| MATRIX-215 | Permission asked once, and banners while the app is active | **partial**: the permission request runs on iOS. `willPresent` is macOS only (D6) | `6e65ec7`, `Core/Notifications.swift:103` |
| MATRIX-221 | Reply, Mark as Read, Remind in 1 Hour on a banner | **Mac only**. The story defers iOS and the extension | `774334d`, `Core/Notifications.swift:61` |

### 3.13 Send Later

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-210 | Send Later spike | **n/a** | `3bd9df7` |
| MATRIX-212 | Send Later (MSC4140) | **Mac only**. The story: "iOS parity is a later story". The registry cleanup timer runs on iOS (D13) | `ae0cef4`, `Core/ScheduledMessagesModel.swift:265` |

### 3.14 Bookmarks and edit history

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-208 | Bookmark messages, Bookmarks list | **Mac only**. The story: "no iOS UI". iOS does not set `timelineRowIsBookmarked`, so no bookmark mark | `03bf92a` |
| MATRIX-209 | Edit history of a message | **deferred by the fence** (edits) | `cf1079e` |

### 3.15 Broadcast

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-168 | Broadcast to the chats of the rail filter | **Mac only** | `7792238` |
| MATRIX-172 | Broadcast reaches every chat of the filter | **Mac only** | `805de2d` |
| MATRIX-177 | Broadcast an image (Backlog) | **n/a** | export |

### 3.16 Own profile

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-163 | Own profile image on own messages, set in Account settings | **partial**: the image draws on iOS. No settings control. The story: visible rows may not redraw at once | `7278d42`, `MactrixiOS/Timeline/TimelineScreen.swift:77` |
| MATRIX-164 | Research notes | **n/a** | `feb6253` |
| MATRIX-165 | Own Slack profile image per workspace | **Mac only**. iOS does not set `ownServiceAvatarUrl` | `af7af92`, `UI/Timeline/MessageEventView.swift:195` |

### 3.17 Links

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-178 | Music links open on song.link, with a glyph | **partial**: the target and the glyph apply on iOS, with the link tint and an underline. iOS has no switch for it | `02c780b`, `MessageFormatting/MusicLinkMarker.swift:64` |
| MATRIX-179 | Music links phase 2 (Backlog) | **n/a** | export |
| MATRIX-187 | Music link in the body text color, gradient bar | **Mac only**. iOS keeps the underline | `94b9b0b` |
| MATRIX-191 | Spotify link shows artist and title | **Mac only**. The story: "iOS shows the URL" | `a5a50f8` |
| MATRIX-201 | X and Bluesky post peek | **Mac only** (`UI/PostPeek/` has macOS guards) | `5699934` |
| MATRIX-203 | Matrix links open in the app | **Mac only** (`Mactrix/Views/ChatView/BodyLinkRouter.swift`). What a matrix.to tap does on iOS is **unknown** | `ad4271c` |
| MATRIX-219 | SDK calls for URL previews and room state | **Mac only** (they feed Mac features) | `f8e5511` |

### 3.18 Mac platform

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-114 | ⌘K quick switcher | **deferred by the fence** (search). iOS has no room search (D9) | `d2322d1` |
| MATRIX-115 | Go menu keys | **Mac only** | `dec071e` |
| MATRIX-116 | Single-room window, restoration | **Mac only** | `81c2184` |
| MATRIX-175 | Window state survives a quit | **Mac only** | `98fa992` |
| MATRIX-214 | `LinkCursorTextField` exception fix | **Mac only** (AppKit) | `890ce4d` |

### 3.19 Settings

The iOS settings show the account, Sign Out, and a push placeholder (`MactrixiOS/Settings/SettingsView.swift`).

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-100 | Enter behavior setting, Composer tab | **deferred by the fence**. On iOS, Return adds a newline and the button sends | `a8f8bea`, `MactrixiOS/Composer/ComposerBar.swift` |
| MATRIX-117 | Settings > Notifications tab | **deferred by the fence** (M2) | `203c855` |

### 3.20 Sync, SDK and status

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-122 | SDK store pools capped, open-file limit raised | **on iOS** (the app). The extension does not raise the limit, and the need is not known | `789f342`, `MactrixiOS/MactrixiOSApp.swift:13` |
| MATRIX-211 | SDK 26.04.01 to 26.11.11 | **on iOS**: the iOS changes compile and CI runs the iOS tests green at `f26045f`. No device run | `4bbf0d1` |
| MATRIX-237 | Sync line shows the state of the running sync, and Restart sync | **partial**: the Core restart path runs on iOS. iOS shows no sync line and has no restart control (D11) | `f26045f`, `Core/MatrixClient+Sync.swift:17` |

### 3.21 Icon and name

| Story | Mac behavior | iOS status | Evidence |
|---|---|---|---|
| MATRIX-233 | Liquid Glass icon from Icon Composer | **on iOS** | `e72260a`, `MactrixiOS/AppIcon.icon/` |
| MATRIX-236 | The app is Round: `Round.app`, display name, process name | **partial**: display names "Round" and "Round Notifications". The iOS product is still `Mactrix.app` (D12) | `fddb7ef`, `Mactrix.xcodeproj/project.pbxproj:959` |

### 3.22 Tooling, tests, epics and exit checks

| Stories | iOS status |
|---|---|
| MATRIX-93, 95, 101, 103, 118, 120, 126, 127, 128, 131, 134, 152, 158, 160, 176, 213, 218 (CI, SwiftFormat, snapshot flakes, refactors, housekeeping, test host) | **n/a** |
| MATRIX-99 (E-M2-01 epic) | **deferred by the fence** |
| MATRIX-124, 125, 174, 181 (Mac exit checks and timeline gate runs) | **n/a** |
| MATRIX-228 (`NSTableView` reentrant operation, Backlog) | **n/a** |

## 4. Known iOS defects and risks

D1. **Threads do not show.** `Core/LiveTimeline.swift:178` opens the main timeline with `hideThreadedEvents: true` (since `4ced4d8`, before the iOS port). iOS has no thread summary chip and no thread screen. A thread root shows with no mark, and its replies are not on the phone. This hides Slack thread traffic, and since MATRIX-232 it hides every reply that the Mac sends in a Slack room.

D2. **Replies go to different places (MATRIX-232).** iOS sends `Timeline.sendReply` on the live timeline (`MactrixiOS/Composer/LiveComposerTarget.swift:35` to `40`), a plain `m.in_reply_to`. The Mac uses `ThreadedReplyRule` and the shared `LiveTimeline.send(_:replyingTo:openThreadRoot:)` (`Core/LiveTimeline+ReplyRoute.swift`). In a Slack room, an iPhone reply shows inline in the Matrix clients and in a thread in Slack. A Mac reply shows in a thread everywhere and not on the phone. Do not change only the iOS send route: a threaded reply from the phone then goes out of view on the phone (D1).

D3. **MATRIX-231: reply rows keep the placeholder height.** The iOS row draws the quote from `loadedReplyDetails` (`TimelineRowContent.swift:301`). The height fingerprint reads only the SDK item (`Core/TimelineRowHeightFingerprint+SDK.swift:33`), and iOS has no `replyDetailsDidLoad` observer. The gap is still 20 pt: a 10 pt padding (`:322`) inside a stack with 10 pt spacing (`:271`).

D4. **Reaction chips are dead controls.** The shared `MessageEventBodyView` calls `actions.toggleReaction` on a chip tap (`UI/Timeline/MessageEventView.swift:320`). iOS implements it as a no-op (`TimelineRowContent.swift:194`). The chip reacts to the touch and nothing occurs.

D5. **A notification tap does not open its chat.** `MatrixNotifications` sets `selectedRoomId` on a tap (`Core/Notifications.swift:93`). No iOS code reads it. The delegate is set when the client is made (`Core/Notifications.swift:60`), after the session restore, so a tap that launches the app can arrive before the delegate (MATRIX-221 notes the same for the Mac). The extension puts only the room ID in `userInfo`, not the event ID, so a tap cannot jump to the message.

D6. **No foreground banners, and a risk of two banners.** `willPresent` is macOS only (`Core/Notifications.swift:103`), so iOS shows no notification while the app is in front. The in-process sync path posts local notifications on iOS too. Risk, not verified: in the short time between background and suspension, a local notification and the push for the same event can both show.

D7. **The chat list ignores the Mac inbox state.** The Mac builds its list with `ChatListMerging.visible` (`Mactrix/Views/Sidebar/SidebarView.swift:60`). iOS does not. So archived and snoozed chats stay in the iOS list, and the member rooms of a merged chat show as separate rows.

D8. **Low-priority chats cannot be reached on iOS.** The room list filter stays `.inbox`, which is `.nonLowPriority` (`Core/ChatList+SDK.swift:204`). iOS never calls `setChatListFilter` and has no Low Priority view.

D9. **At most 100 chats, and no search.** The room list page is 100 (`Core/MatrixClient+Sync.swift:58`), and no code loads a next page. The Mac reaches the other chats with ⌘K (page 1000). iOS has no search.

D10. **No app icon badge.** M1 has a Dock badge. On iOS `DockBadgeController` does nothing, and the extension sets no badge. **unknown**: whether a Sygnal `event_id_only` push carries a badge count.

D11. **Sync has no lifecycle on iOS.** `SessionLifecycle` starts sync one time (`MactrixiOS/Login/SessionLifecycle.swift:78`). No code stops sync before a suspension or restarts it on foreground. iOS has no sync line and no retry, but the `SessionLifecycle` comment says "the UI can show and retry". Risk, not verified: iOS can end a suspended app that holds a file lock in an App Group container (exception code `0xdead10cc`), and the SDK store is in the App Group container (MATRIX-88).

D12. **MATRIX-236 leftovers.** The iOS target has `PRODUCT_NAME = Mactrix` in Debug and Release (`project.pbxproj:959`). The App Store Connect app name must be unique across the store. MATRIX-92 step 6 expects "Mactrix" to be taken. "Round" can be taken too. Patrick must pick the name before he makes the record.

D13. **The shared `startSync()` runs Mac-only work on iOS.** It starts the space service and its launch cache, labels, merged chats, bookmarks, the scheduled-message registry, the inbox model, and a draft read of every room (`Core/MatrixClient+Sync.swift:58` to `139`). Each opened timeline calls `fetchMembers()` one time (MATRIX-163). The registry cleanup can write `io.davlin.matrixclient.scheduled` from the phone (`Core/ScheduledMessagesModel.swift:265`). The removal is by time and an echo gate guards it, so a write race is a low risk. The cost on a phone is not measured.

D14. **Mac notification rules do not reach push.** Label mute (MATRIX-77), Settings > Notifications (MATRIX-117) and snooze apply in the Mac app only. The phone push follows the server push rules only. So a chat that the Mac mutes by label or snoozes still rings the phone.

D15. **Shared-code changes since the iOS merge.** No Core change breaks the iOS build: CI builds and tests iOS green at `f26045f`. Behavior exposure:
- MATRIX-230 changed the shared height fingerprint, and the iOS row draws from another source (D3).
- MATRIX-237 made `startSync()` restart a started service. iOS calls it one time, so iOS is compatible.
- MATRIX-211 bumped the SDK. The extension, pusher and lock calls compile, but no device ran them.
- MATRIX-192 fixed the body measure in the AppKit `AttributedTextView` only. The UIKit `UITextView` path is not tested.
- MATRIX-232 added `ThreadedReplyRule`, and iOS does not use it (D2).

D16. **iOS tests run in CI only.** The push gate in `CLAUDE.md` runs `scripts/build.sh` (it builds iOS), `swift test` on the macOS host, and lint. The iOS unit tests run only in the CI step "Test iOS (Simulator)", with signing off. So no run uses the App Group or the keychain group before a device install.

D17. **Stale docs.** The E-APP-05 status line is from 2026-11-09, and its §4 FFI table gives line numbers for SDK 26.04.01 (the pin is 26.11.11). `docs/STATUS.md` is a snapshot of 2026-11-13. MATRIX-92 names 10 `DEVELOPMENT_TEAM` places, and the project has 12.

D18. **Settings text.** "Push notifications are not available yet." and "The app shows new messages only while it is open." (`MactrixiOS/Settings/SettingsView.swift:71`, `:76`) must change when push works.

## 5. Proposed stories

The order is what Patrick needs first on his phone. "Fence" says whether the story needs a §11 row that amends the E-APP-05 §8 fence.

1. **iOS: switch to the paid team and make the first device build.** Area: prerequisites. Set `DEVELOPMENT_TEAM` to the new Team ID in the 12 configurations. Check the App Group, App IDs and keychain group. Make one cable build on the iPhone. Refresh the E-APP-05 status line and §4 FFI table for 26.11.11 (D17). Needs Patrick: the Team ID (MATRIX-92 step 2), the iPhone, one Mac keychain "Always Allow". Fence: no.
2. **iOS: product name and App Store Connect name.** Area: icon and name. Set the iOS `PRODUCT_NAME` to Round, or record why it stays (D12). Pick a unique App Store Connect name before the record exists (MATRIX-92 step 6). Needs Patrick: the name decision. Fence: no.
3. **iOS: device smoke of the port.** Area: iOS port. Run the device checks parked on MATRIX-92: sign-in, restore, verification, recovery, list, timeline, send, reply, media, invites, iPad split and rotation, the MATRIX-87 gate on the device, MATRIX-98 and MATRIX-132. Lock the phone and come back after 10 minutes to check D11. Needs Patrick: the device, the dev account. Fence: no.
4. **iOS: sync lifecycle and sync line.** Area: sync and status. Stop sync before a suspension inside a background task, and restart it with `startSync()` (the MATRIX-237 restart path) on foreground. Show the shared `SyncStatusLine` with a retry in the list. Check for `0xdead10cc` on the device (D11). Needs Patrick: a device check. Fence: no (M1).
5. **iOS: notification tap and foreground rule.** Area: notifications and push. A tap on a push or a local notification opens its chat in the iOS navigation, also on a cold launch. Add the event ID to the extension's `userInfo`. Add an iOS `willPresent` that uses `NotificationPresentation.shows` with the open chat. Stop the double banner of D6 and change the text of D18. Depends on MATRIX-90. Needs Patrick: a device check. Fence: no (push is in the fence).
6. **iOS: app icon badge.** Area: notifications and push. Show the unread chat count on the app icon, as the Mac Dock badge counts chats (MATRIX-119). Read the pinned Sygnal sources for the `event_id_only` badge first (D10). Decide between a server count in the push and an app count set from the extension. Needs Patrick: a decision on chats or messages, and a device check. Fence: no (M1 badge parity).
7. **iOS: thread chip and thread screen.** Area: threads and replies. Draw the shared `MessageThreadSummary` on thread roots (contract §3 allows a "thread exists" affordance). A tap opens a thread screen on `LiveTimeline(room:focusThread:)` in the same collection container, with a composer that sends through `LiveTimeline.send(_:replyingTo:openThreadRoot:)`. Needs Patrick: a decision. Fence: the chip no, the thread screen yes (threads are deferred in §3).
8. **iOS: Slack reply rule (MATRIX-232 parity).** Area: threads and replies. `LiveComposerTarget` sends through the shared reply route, so a reply in a Slack room goes into the thread as on the Mac. The reply then shows in the thread screen of story 7. Depends on story 7. Needs Patrick: no. Fence: yes, the same row as story 7.
9. **MATRIX-231 (exists): reply rows re-measure when a quote loads, and a 10 pt gap.** Area: timeline. Copy the Mac `TimelineReplyQuoteHeights` rule to the iOS controller, and remove the 10 pt padding (D3). Needs Patrick: an iOS smoke. Fence: no.
10. **iOS: reach every chat.** Area: chat list. Add a search field over all joined rooms from a full directory (the Core `QuickSwitcherRoomDirectory`, page 1000), because the list holds 100 (D9). Add a Low Priority section or filter (D8). Needs Patrick: a decision. Fence: yes if search counts as the M2 ⌘K feature, no if it counts as M1 room list parity.
11. **iOS: follow the Mac inbox state.** Area: inbox flow and merged chats. Build the iOS list from `ChatListMerging.visible`, so archived and snoozed chats leave the main list into their own sections. Show a merged chat as one row that opens its newest member room, with no merged timeline. Needs Patrick: a decision on scope. Fence: yes (M2.5 and Beeper-parity features).
12. **iOS: reaction chips that work, or inert chips.** Area: reactions. Option A: connect `toggleReaction` to the shared `LiveTimeline+Reactions` and add a quick-reaction row to the context menu (fence: yes, §8 lists reactions). Option B: make the chips inert on iOS (fence: no). Needs Patrick: pick A or B (D4).
13. **iOS: limit the shared sync start to what iOS uses.** Area: sync and status. Measure the launch cost on the device. Keep on iOS only the parts of `startSync()` that an iOS view reads, or that story 11 needs (D13). Needs Patrick: no (one device measure can come with story 3). Fence: no.
14. **iOS: send photos and files.** Area: composer and send. A photo picker, the camera, and files, through the shared `LiveTimeline+MediaSend`, with upload progress. Needs Patrick: a decision. Fence: yes (M2-A2, A3).
15. **iOS: edit and delete own messages.** Area: composer and send. Edit and Delete in the context menu, through the shared `LiveTimeline+Edit` and `LiveTimeline+Redaction`. Needs Patrick: a decision. Fence: yes (§8 lists edits and redactions).
16. **iOS: composer drafts.** Area: drafts and typing. Save and restore a draft per room through the Mac `saveComposerDraft` path, deferred in MATRIX-86 (g). Needs Patrick: a decision. Fence: yes (drafts are not in the fence list of 2026-10-27).
17. **iOS: display parity batch.** Area: timeline and rendering. Jumbo emoji (MATRIX-137, 162), Spotify titles (MATRIX-191), own Slack image per workspace (MATRIX-165), the bookmark mark (MATRIX-208). All are display rules that are shared or small. Snapshots for each. Needs Patrick: an iOS smoke. Fence: yes (post-M1 display rules).
18. **iOS: notification actions.** Area: notifications and push. Reply and Mark as Read on a banner (MATRIX-221 parity), with the category set in the app and the extension. Needs Patrick: a device check. Fence: yes.
19. **iOS: snooze ends and reminders on the phone.** Area: inbox flow. Decide which device posts a snooze end or a reminder, so that the Mac and the phone do not both post (`Core/MatrixClient+Listeners.swift:209` posts on macOS only). Needs Patrick: a decision. Fence: yes.
20. **iOS: matrix links open in the app.** Area: links. A matrix.to or `matrix:` link in a body opens the room or the event in the iOS navigation, as `BodyLinkRouter` does on the Mac (MATRIX-203). Find what a tap does today first. Needs Patrick: no. Fence: Patrick decides (the Mac inherited `matrix:` links from Mactrix).
