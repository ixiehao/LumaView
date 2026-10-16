#!/bin/zsh
set -euo pipefail

# One repeatable local gate for contributors and CI. Derived files live in a
# temporary directory so validation never changes a checked-out project.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAGE_DIR="$(mktemp -d /tmp/lumaview-validation.XXXXXX)"
DERIVED_DATA="$STAGE_DIR/DerivedData"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"

# Run core and UI tests in one locally signed XCTest session. Splitting macOS UI
# automation into a second `xcodebuild` process can leave the accessibility service
# claimed by the first runner, producing a false timeout before UI tests even start.
# UI coverage uses generated local image fixtures and disables update checks.
xcodebuild \
  -project LumaView.xcodeproj \
  -scheme LumaView \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS,arch=arm64' \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-"

xcodebuild \
  -project LumaView.xcodeproj \
  -scheme LumaView \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  build

RELEASE_BINARY="$DERIVED_DATA/Build/Products/Release/LumaView.app/Contents/MacOS/LumaView"
RELEASE_ARCHITECTURES="$(lipo -archs "$RELEASE_BINARY")"
[[ " $RELEASE_ARCHITECTURES " == *" arm64 "* && " $RELEASE_ARCHITECTURES " == *" x86_64 "* ]] || {
  print -u2 "Release build must contain both arm64 and x86_64 slices; found: $RELEASE_ARCHITECTURES"
  exit 1
}

if [[ "${LUMAVIEW_RUN_STRESS_TEST:-0}" == "1" ]]; then
  STRESS_BINARY="$STAGE_DIR/lumaview-stress"
  swiftc -O -parse-as-library \
    LumaView/Localization.swift \
    LumaView/ImageBrowserStore.swift \
    LumaView/ImagePipeline.swift \
    tools/StressHarness.swift \
    -o "$STRESS_BINARY" \
    -framework AppKit \
    -framework SwiftUI \
    -framework ImageIO \
    -framework UniformTypeIdentifiers

  /usr/bin/time -l "$STRESS_BINARY"
else
  print "Skipping optional 5K stress gate (set LUMAVIEW_RUN_STRESS_TEST=1 to run it)."
fi
