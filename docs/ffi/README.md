# Vendored FFI Swift interfaces

## What these files are

This directory holds the generated Swift FFI interfaces from
`matrix-rust-components-swift`, the Swift package that wraps
`matrix-rust-sdk`. The Swift package for this app depends on
`matrix-rust-components-swift` through Swift Package Manager. Xcode
resolves that dependency and stores a local checkout under
`DerivedData`. These files are a copy of the checkout's
`Sources/MatrixRustSDK/` directory, taken byte-exact.

The FFI bindings are large and undertrained in most language models. Per
CLAUDE.md rule 5, no agent may write an SDK call from memory. Read the
files in this directory to get the correct method names, parameter types,
and return types before you write any code that calls the SDK.

## Files

- `matrix_sdk.swift`
- `matrix_sdk_base.swift`
- `matrix_sdk_common.swift`
- `matrix_sdk_crypto.swift`
- `matrix_sdk_ffi.swift`
- `matrix_sdk_ui.swift`

## Pinned SDK version

- Package: `matrix-rust-components-swift`
- Version: `26.04.01`
- Revision: `2916f3f9cc2aea86ba3a820cb6a8389e13e0284a`
- Upstream `matrix-rust-sdk` commit: `388ced09a6b3f5e63521e0c8f7c2eec811ffd37a`
  on `main`

This matches the pin recorded in
`Mactrix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Read-only status

Do not edit files in this directory by hand. They are a copy of generated
code from an external package. If a file here looks wrong or out of date,
run the refresh procedure below. Do not patch a single file to work around
a suspected error; check the real checkout first.

## Refresh procedure

Run this after any bump of the `matrix-rust-components-swift` pin (see
CLAUDE.md rule 6 — pin bumps are their own story):

```
scripts/refresh-ffi-docs.sh
```

The script finds the current package checkout in DerivedData, resolves
package dependencies first if the checkout is missing, wipes the `.swift`
files in this directory, copies the current set from the checkout, and
prints the version and revision from `Package.resolved`.

After running the script, review the diff. Confirm the printed version
and revision match the new pin before you commit.
