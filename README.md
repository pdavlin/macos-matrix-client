<img width="128" height="128" src="./docs/mactrix-icon.webp">

# Matrix client for macOS (Mactrix fork)

A single-user, Mac-native [Matrix](https://matrix.org) client for one account
on one self-hosted homeserver (davlin.io) with mautrix bridges. The goal is to
uninstall Beeper and Element Desktop.

This is a hard fork of [Mactrix](https://github.com/viktorstrate/mactrix).
It is a SwiftUI and AppKit shell over the
[matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk) FFI bindings
(`matrix-rust-components-swift`, pinned at 26.04.01). The SDK owns sync,
encryption, verification, and timeline state.

## Status

- M0 (foundation), M1 (read path), and M2 (send path and Mac integration)
  are built and merged. The M2 exit checks are open.
- M3 (local search and archive) has not started.
- An iOS/iPadOS port shares the `Core` library. It waits on an Apple
  Developer account for device builds.

[`docs/STATUS.md`](docs/STATUS.md) lists the full feature set and the open
work by issue. [`docs/PROJECT_CONTRACT.md`](docs/PROJECT_CONTRACT.md) holds
scope, the roadmap, and the decision log.

## Feature set (macOS)

- Sign-in (password, SSO), keychain session restore, emoji verification,
  recovery.
- Dense chat list with pinned favourites, labels, filters, bridge network
  badges, and group bubble avatars.
- AppKit-backed timeline: sender grouping, day separators, reactions, read
  receipts, back-pagination, inline media, Quick Look.
- Composer: replies, edits, redaction, reaction picker, mentions, media send
  with upload progress, forwarding, drafts, configurable Enter key.
- Mac platform: real menus, ⌘K quick switcher, ⌘1 to ⌘9, room windows with
  restoration, Settings, local notifications, Dock badge.

## Build

Requirements: macOS 26 or later (development uses macOS 27 and Xcode 27).

```bash
scripts/build.sh   # macOS app, then the iOS app for the simulator
scripts/test.sh    # unit and snapshot tests
scripts/lint.sh    # SwiftFormat --lint and SwiftLint
```

Each script finds `DEVELOPER_DIR` itself (Xcode-beta.app, else Xcode.app)
unless you set it.

## License

GPL-3.0-only, inherited from Mactrix. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the dependency
licenses and the distribution terms.
