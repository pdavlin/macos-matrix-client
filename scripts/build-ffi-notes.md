# From-source build path: matrix-rust-components-swift XCFramework

Documentation only. This is the insurance path for R-3 (macOS may lack a
usable slice at some future pinned version). Do not run these steps unless
the prebuilt XCFramework from the pinned Swift package stops shipping a
working `macos-arm64` slice.

Current pin (set in S-02): `matrix-rust-components-swift` version `26.04.01`,
which corresponds to `matrix-rust-sdk` commit
`388ced09a6b3f5e63521e0c8f7c2eec811ffd37a` on `main`.

## What builds what

`matrix-rust-components-swift` does not contain Rust source. Each tagged
release is produced by checking out `matrix-rust-sdk` at a specific commit
and running its Swift-bindings build task, then copying the generated
XCFramework and Swift sources into the components repo. The build logic and
tooling live in `matrix-rust-sdk`, at `bindings/apple/`.

Reference: `matrix-rust-components-swift` at tag `26.04.01`, file
`Tools/Release/Sources/Release.swift` (the maintainers' own release script)
runs, inside a checkout of `matrix-rust-sdk`:

```
unset SDKROOT && cargo xtask swift build-framework --release
```

## Repo and commit to clone

Clone `matrix-rust-sdk` and check out the exact commit recorded in the
pinned components-swift tag's bump commit message:

```
git clone https://github.com/matrix-org/matrix-rust-sdk
cd matrix-rust-sdk
git checkout 388ced09a6b3f5e63521e0c8f7c2eec811ffd37a
```

Do not build from `main` of `matrix-rust-sdk` — that floats. Building from
the exact commit is what makes this an equivalent, not a substitute, for the
pinned artifact.

## Prerequisites

From `matrix-rust-sdk/bindings/apple/README.md`:

- Rust toolchain via rustup. `Cargo.toml` declares `rust-version = "1.93"`;
  no `rust-toolchain.toml` pin exists in the repo, so CI installs plain
  `stable` (`dtolnay/rust-toolchain@stable`). Match that: install current
  stable, not nightly, for the macOS-only build (nightly is only required
  for Tier 3 targets such as watchOS, which this project does not need).
- Apple Rust targets, macOS only:
  ```
  rustup target add aarch64-apple-darwin x86_64-apple-darwin
  ```
- `xcodebuild` command-line tool (ships with Xcode).
- `lipo` (ships with Xcode command-line tools).
- `protoc` — the SDK's CI installs `protoc@3.20.3` before running codegen
  (`.github/workflows/bindings_ci.yml`, step "Install protoc"). Install a
  matching 3.20.x `protoc` on the build machine.
- `uniffi-bindgen` is NOT a separate install. `matrix-rust-sdk`'s
  `Cargo.toml` pins `uniffi`/`uniffi_bindgen` to a git revision
  (`mozilla/uniffi-rs` rev `e5f4821410bea19e71984ea5e06a7bc8b11ed9e5`,
  version `0.31.0`) and `xtask` invokes the bindgen library in-process via
  `uniffi_bindgen::bindings::generate`. Plain `cargo` dependency resolution
  fetches the correct pinned version automatically; nothing to configure by
  hand.

## Build command (macOS only, aarch64-apple-darwin)

From `matrix-rust-sdk/xtask/src/swift.rs`, `BuildFramework` accepts
`--target` (repeatable) to restrict the build instead of building every
supported platform (iOS, iOS simulator, watchOS, macOS):

```
cd matrix-rust-sdk
unset SDKROOT
cargo xtask swift build-framework \
  --release \
  --target aarch64-apple-darwin \
  --target x86_64-apple-darwin
```

`unset SDKROOT` matches the maintainers' own release script — an inherited
`SDKROOT` from an active Xcode build environment can prevent the task from
building anything other than the macOS host target.

Output lands at `matrix-rust-sdk/bindings/apple/generated/`:

- `MatrixSDKFFI.xcframework` — the artifact to inspect for a `macos-arm64`
  (or `macos-arm64_x86_64`) `LibraryIdentifier`, same check as S-02 step 4.
- `swift/` — generated Swift sources, which the release process rsyncs into
  `matrix-rust-components-swift/Sources/MatrixRustSDK/`.

## Verifying the output

Same checks as the prebuilt artifact:

```
ls bindings/apple/generated/MatrixSDKFFI.xcframework
cat bindings/apple/generated/MatrixSDKFFI.xcframework/Info.plist
lipo -info bindings/apple/generated/MatrixSDKFFI.xcframework/macos-*/libmatrix_sdk_ffi.a
```

Confirm a `macos-` `LibraryIdentifier` exists in `Info.plist` and that
`lipo -info` reports `arm64` in its architecture list.

## Wiring a from-source build into the Xcode project

If this path is ever exercised for real, do not point the Xcode project at
`matrix-rust-components-swift`'s Package.swift for the FFI target. Instead:

1. Copy `MatrixSDKFFI.xcframework` and the generated `swift/` sources into a
   local package (mirroring `matrix-rust-components-swift`'s own
   `Package.swift` structure) or add the xcframework as a local binary
   target directly in `Mactrix.xcodeproj`.
2. Record the substitution and the commit built from as a dated entry in
   `docs/PROJECT_CONTRACT.md` §11 — this changes the pin discipline
   established in S-02 and needs the same visibility.
