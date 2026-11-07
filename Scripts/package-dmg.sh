#!/bin/zsh
set -euo pipefail

# Ad-hoc QA/public-preview package; distribution requirements are in docs/RELEASE.md.
# Developer ID distribution uses release-notarized-dmg.sh and its notary profile.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/Scripts/build-common.sh"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
OUTPUT_DIR="${OUTPUT_DIR:a}"
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

build_release_app "$DERIVED_DATA" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual

ditto "$DERIVED_DATA/Build/Products/Release/LumaView.app" "$APP_PATH"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$OUTPUT_DIR/LumaView-$VERSION-$LUMAVIEW_ARCH.dmg"
[[ ! -e "$DMG_PATH" && ! -L "$DMG_PATH" && ! -e "$DMG_PATH.sha256" && ! -L "$DMG_PATH.sha256" ]] || {
  print -u2 "Refusing to replace an existing installer or checksum: $DMG_PATH"
  exit 73
}

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
verify_app_architecture "$APP_PATH"

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
verify_app_architecture "$MOUNT_DIR/LumaView.app"
cmp "$APP_PATH/Contents/MacOS/LumaView" "$MOUNT_DIR/LumaView.app/Contents/MacOS/LumaView"
hdiutil detach "$VALIDATION_DEVICE" -quiet
VALIDATION_DEVICE=""
(
  cd "$OUTPUT_DIR"
  setopt NO_CLOBBER
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)
print "Created internal QA package: $DMG_PATH"
