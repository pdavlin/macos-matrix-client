#!/bin/bash
# Refresh docs/ffi/ from the current matrix-rust-components-swift package
# checkout. See docs/ffi/README.md for what these files are and why they
# are vendored.
#
# Usage: scripts/refresh-ffi-docs.sh
# Works from any current working directory.

set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
FFI_DOCS_DIR="$REPO_ROOT/docs/ffi"
XCODE_PROJECT="$REPO_ROOT/Mactrix.xcodeproj"
PACKAGE_NAME="matrix-rust-components-swift"
DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"

find_checkout() {
  find "$DERIVED_DATA_DIR" -maxdepth 5 -type d \
    -path "*/SourcePackages/checkouts/$PACKAGE_NAME" \
    -print -quit 2>/dev/null
}

CHECKOUT_DIR="$(find_checkout || true)"

if [ -z "$CHECKOUT_DIR" ]; then
  echo "Package checkout not found. Resolving package dependencies..." >&2
  xcodebuild -resolvePackageDependencies -project "$XCODE_PROJECT" -scheme Mactrix
  CHECKOUT_DIR="$(find_checkout || true)"
fi

if [ -z "$CHECKOUT_DIR" ]; then
  echo "error: could not locate $PACKAGE_NAME checkout under $DERIVED_DATA_DIR after resolving dependencies" >&2
  exit 1
fi

SOURCE_DIR="$CHECKOUT_DIR/Sources/MatrixRustSDK"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "error: $SOURCE_DIR does not exist" >&2
  exit 1
fi

echo "Refreshing $FFI_DOCS_DIR from $SOURCE_DIR"

mkdir -p "$FFI_DOCS_DIR"
find "$FFI_DOCS_DIR" -maxdepth 1 -name '*.swift' -type f -delete

for f in "$SOURCE_DIR"/*.swift; do
  cp "$f" "$FFI_DOCS_DIR/"
done

echo "Copied $(find "$FFI_DOCS_DIR" -maxdepth 1 -name '*.swift' -type f | wc -l | tr -d ' ') .swift files."

RESOLVED_FILE="$REPO_ROOT/Mactrix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [ -f "$RESOLVED_FILE" ]; then
  echo "Pin recorded in Package.resolved:"
  /usr/bin/python3 -c "
import json, sys
with open('$RESOLVED_FILE') as fh:
    data = json.load(fh)
for pin in data.get('pins', []):
    if pin.get('identity') == '$PACKAGE_NAME':
        state = pin.get('state', {})
        print('  version:  ' + str(state.get('version')))
        print('  revision: ' + str(state.get('revision')))
        sys.exit(0)
print('  warning: $PACKAGE_NAME not found in Package.resolved', file=sys.stderr)
"
else
  echo "warning: $RESOLVED_FILE not found; cannot print pinned version" >&2
fi
