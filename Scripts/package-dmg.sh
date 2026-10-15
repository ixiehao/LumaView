#!/bin/zsh
set -euo pipefail

# Internal QA package only. It deliberately uses an ad-hoc signature; public releases
# must run release-notarized-dmg.sh with a Developer ID identity and notary profile.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
STAGE_DIR="$(mktemp -d /tmp/lumaview-dmg.XXXXXX)"
DERIVED_DATA="$STAGE_DIR/DerivedData"
APP_PATH="$STAGE_DIR/LumaView.app"
MOUNT_DIR="$(mktemp -d /tmp/lumaview-installer-check.XXXXXX)"
VALIDATION_DEVICE=""

cleanup() {
  [[ -n "$VALIDATION_DEVICE" ]] && hdiutil detach "$VALIDATION_DEVICE" -quiet || true
  rmdir "$MOUNT_DIR" 2>/dev/null || true
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
cd "$PROJECT_DIR"

xcodebuild \
  -project LumaView.xcodeproj \
  -scheme LumaView \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  build

ditto "$DERIVED_DATA/Build/Products/Release/LumaView.app" "$APP_PATH"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$OUTPUT_DIR/LumaView-$VERSION-arm64.dmg"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/LumaView")"
[[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " != *" x86_64 "* ]] || {
  print -u2 "LumaView is Apple-silicon only; the QA package must contain arm64 and no x86_64 slice."
  exit 1
}

"$PROJECT_DIR/Scripts/create-dmg-layout.sh" "$APP_PATH" "$DMG_PATH" "LumaView $VERSION"
ATTACH_OUTPUT="$(hdiutil attach -readonly -noverify -noautoopen -mountpoint "$MOUNT_DIR" "$DMG_PATH")"
VALIDATION_DEVICE="$(print -r -- "$ATTACH_OUTPUT" | awk '/Apple_APFS|Apple_HFS/ {print $1; exit}')"
[[ -n "$VALIDATION_DEVICE" && -d "$MOUNT_DIR/LumaView.app" && -L "$MOUNT_DIR/Applications" ]] || {
  print -u2 "Unable to mount and verify the QA DMG."
  exit 1
}
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || {
  print -u2 "QA DMG Applications link is invalid."
  exit 1
}
"$PROJECT_DIR/build/dmg-tools/bin/python3" "$PROJECT_DIR/Scripts/verify-dmg-layout.py" "$MOUNT_DIR" "LumaView.app"
codesign --verify --deep --strict --verbose=2 "$MOUNT_DIR/LumaView.app"
MOUNTED_ARCHITECTURES="$(lipo -archs "$MOUNT_DIR/LumaView.app/Contents/MacOS/LumaView")"
[[ "$MOUNTED_ARCHITECTURES" == "$ARCHITECTURES" ]] || { print -u2 "Mounted DMG architecture differs from build."; exit 1; }
hdiutil detach "$VALIDATION_DEVICE" -quiet
VALIDATION_DEVICE=""
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
print "Created internal QA package: $DMG_PATH"
