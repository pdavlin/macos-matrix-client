# Third-Party Notices

This file lists the license terms of the code this project is built on.
It covers the fork base (Mactrix) and its direct dependencies as declared
in the Mactrix Xcode project, checked on 2026-08-19.

## Mactrix

- License: GNU General Public License, Version 3 (GPLv3)
- SPDX id: GPL-3.0-only (the repository LICENSE file is the stock FSF
  GPLv3 text with no "or any later version" grant in any file header or
  README, so treat it as version-3-only, not GPL-3.0-or-later)
- Source: https://github.com/viktorstrate/mactrix (LICENSE file at repo root)
- Private use and modification: GPLv3 places no conditions on private use
  or modification. A fork may be changed freely and run locally with no
  disclosure or licensing obligation, as long as it is not conveyed
  (distributed) to anyone outside the licensee.
- Obligations that apply only at public distribution: a conveyed copy or
  modified version must remain under GPLv3, must come with the complete
  corresponding source code (or a written offer to provide it), must keep
  the GPLv3 license text and existing copyright notices, and must carry a
  notice stating that the file was changed. GPLv3 also carries an
  anti-tivoization term (source must let recipients rebuild and reinstall
  a modified version on devices that ship it) and an express patent grant
  from contributors.
- Red flag for a future public release: Apple's Mac App Store terms
  impose additional restrictions (DRM, resale terms) that the Free
  Software Foundation and most GPLv3 practice treat as incompatible with
  GPLv3 section 6 and section 10. A GPLv3 fork of Mactrix likely cannot
  ship through the Mac App Store; direct, notarized distribution outside
  the App Store is not affected by this conflict.

## matrix-rust-components-swift

- License: Apache License, Version 2.0
- SPDX id: Apache-2.0
- Source: https://github.com/matrix-org/matrix-rust-components-swift
  (LICENSE file at repo root; no NOTICE file is present in the repo)
- Version pinned by Mactrix: Mactrix's Xcode project references this
  package by `branch = main`, not a fixed tag, so there is no single
  pinned version to record yet. The `Package.swift` on `main` as of
  2026-08-19 resolves to release `26.08.11`, and that release is
  Apache-2.0, matching every other checked point in the repo's history.
  No AGPL or dual-licensed period was found for this package; establishing
  an exact-version pin (per the contract's pin discipline rule) is a
  separate, non-licensing task.
- Private use and modification: unrestricted. Apache-2.0 permits use,
  modification, and private distribution with no source-disclosure
  requirement.
- Obligations that apply only at public distribution: any distributed
  copy, modified or not, must include a copy of the Apache-2.0 license,
  must retain existing copyright, patent, trademark, and attribution
  notices from the source, and must mark any files that were changed.
  Apache-2.0 includes an express patent grant and a patent-litigation
  retaliation clause; it does not require the combined work (this GPLv3
  fork) to be released under Apache-2.0 terms.
- Compatibility note: Apache-2.0 code may be incorporated into a GPLv3
  work and distributed under GPLv3 terms. GPLv3 was written to be
  one-directionally compatible with Apache-2.0 for this reason. GPLv2
  does not have this compatibility; it is not relevant here since Mactrix
  is GPLv3.

## matrix-rust-sdk

- License: Apache License, Version 2.0
- SPDX id: Apache-2.0
- Source: https://github.com/matrix-org/matrix-rust-sdk (LICENSE file at
  repo root; no NOTICE file is present in the repo)
- Version history: the repository has used Apache-2.0 since a single
  license change in February 2020 (commit "rust-sdk: Switch the license
  to Apache 2.0"). No later relicensing commit was found. Every checked
  workspace crate (`matrix-sdk`, `matrix-sdk-crypto`,
  `bindings/matrix-sdk-ffi`, `bindings/matrix-sdk-crypto-ffi`) declares
  `license = "Apache-2.0"` in its own `Cargo.toml` as of 2026-08-19. This
  is the crate consumed indirectly through
  matrix-rust-components-swift's prebuilt XCFramework.
- Note on the 2023-2024 Element relicensing: the Apache-2.0/AGPL-3.0
  dual-licensing change made around that period applies to Element's
  server and client products, not to matrix-rust-sdk. Confirmed
  separately: `element-hq/synapse` (the homeserver) and
  `element-hq/element-x-ios` (the end-user client app) both report
  AGPL-3.0 on GitHub. Neither is a dependency of this fork.
  matrix-rust-sdk itself has stayed on Apache-2.0 throughout.
- Private use, modification, and distribution obligations: same as
  matrix-rust-components-swift above, since both carry the same license.

## swift-async-algorithms

- License: Apache License, Version 2.0
- SPDX id: Apache-2.0
- Source: https://github.com/apple/swift-async-algorithms (LICENSE file
  at repo root; no NOTICE file is present in the repo)
- Declared as a direct Mactrix dependency (`XCRemoteSwiftPackageReference`
  in the Xcode project, pinned `upToNextMajorVersion` from `1.1.2`).
- Private use, modification, and distribution obligations: same as
  matrix-rust-components-swift above.

## Summary for the current phase (private, personal use)

No obligation is currently triggered. GPLv3 and Apache-2.0 both leave
private use and modification unconstrained. Nothing in this file requires
action until the app is conveyed to anyone outside the licensee.

## Summary for a future public release

Any public build must: ship under GPLv3 (because it is a modified Mactrix
derivative), include this notices file or equivalent, include the full
GPLv3 and Apache-2.0 license texts, make complete corresponding source
available, mark changed files, and avoid distribution channels whose
terms conflict with GPLv3 (the Mac App Store, per the red flag above).
