#!/bin/zsh
set -euo pipefail

# One repeatable local gate for contributors and CI. Derived files live in a
# temporary directory so validation never changes a checked-out project.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAGE_DIR="$(mktemp -d /tmp/lumaview-validation.XXXXXX)"
DERIVED_DATA="$STAGE_DIR/DerivedData"
STRESS_BINARY="$STAGE_DIR/lumaview-stress"

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
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  build

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
