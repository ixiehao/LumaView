#!/bin/zsh
set -euo pipefail

# Public distribution path. Secrets remain in Keychain; never put certificates, API keys,
# profiles, or Apple passwords in this project or its CI logs.
: "${DEVELOPER_ID_APPLICATION:?Set the exact Developer ID Application signing identity.}"
: "${NOTARYTOOL_PROFILE:?Set the Keychain profile name configured for xcrun notarytool.}"

# Refuse to build an apparently public artifact when the local machine cannot
# complete its signing chain. This is deliberately before Xcode, DMG creation,
# and notarization submission: an ad-hoc or unsigned fallback must never be
# mistaken for a Developer ID release.
if ! security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq -- "\"${DEVELOPER_ID_APPLICATION}\""; then
  print -u2 "Developer ID identity is unavailable: ${DEVELOPER_ID_APPLICATION}"
  print -u2 "Install the matching certificate and private key in this login Keychain before releasing."
  exit 2
fi

if ! xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" --output-format json >/dev/null 2>&1; then
  print -u2 "notarytool Keychain profile is unavailable or cannot authenticate: ${NOTARYTOOL_PROFILE}"
  print -u2 "Create or repair the profile with xcrun notarytool store-credentials before releasing."
  exit 2
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
STAGE_DIR="$(mktemp -d /tmp/lumaview-release.XXXXXX)"
DERIVED_DATA="$STAGE_DIR/DerivedData"
APP_PATH="$STAGE_DIR/LumaView.app"
MOUNT_DIR="$(mktemp -d /tmp/lumaview-release-check.XXXXXX)"
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
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  build

ditto "$DERIVED_DATA/Build/Products/Release/LumaView.app" "$APP_PATH"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$OUTPUT_DIR/LumaView-$VERSION-universal-notarized.dmg"

# Sign the final, immutable app bundle with hardened runtime and a secure timestamp.
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/LumaView")"
[[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " == *" x86_64 "* ]] || {
  print -u2 "Release must contain both arm64 and x86_64 slices."
  exit 1
}

"$PROJECT_DIR/Scripts/create-dmg-layout.sh" "$APP_PATH" "$DMG_PATH" "LumaView $VERSION"

# Submit the exact final DMG; do not rebuild between this step and stapling.
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple -v "$DMG_PATH"
xcrun stapler validate -v "$DMG_PATH"
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"

ATTACH_OUTPUT="$(hdiutil attach -readonly -noverify -noautoopen -mountpoint "$MOUNT_DIR" "$DMG_PATH")"
VALIDATION_DEVICE="$(print -r -- "$ATTACH_OUTPUT" | awk '/Apple_APFS|Apple_HFS/ {print $1; exit}')"
[[ -n "$VALIDATION_DEVICE" && -d "$MOUNT_DIR/LumaView.app" && -L "$MOUNT_DIR/Applications" ]] || { print -u2 "Unable to mount final DMG."; exit 1; }
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || { print -u2 "Final DMG Applications link is invalid."; exit 1; }
"$PROJECT_DIR/build/dmg-tools/bin/python3" "$PROJECT_DIR/Scripts/verify-dmg-layout.py" "$MOUNT_DIR" "LumaView.app"
codesign --verify --deep --strict --verbose=2 "$MOUNT_DIR/LumaView.app"
MOUNTED_ARCHITECTURES="$(lipo -archs "$MOUNT_DIR/LumaView.app/Contents/MacOS/LumaView")"
[[ "$MOUNTED_ARCHITECTURES" == "$ARCHITECTURES" ]] || { print -u2 "Mounted DMG architecture differs from build."; exit 1; }
[[ " $MOUNTED_ARCHITECTURES " == *" arm64 "* && " $MOUNTED_ARCHITECTURES " == *" x86_64 "* ]] || {
  print -u2 "Mounted DMG must contain both arm64 and x86_64 slices."
  exit 1
}
spctl --assess --type execute --verbose=4 "$MOUNT_DIR/LumaView.app"
hdiutil detach "$VALIDATION_DEVICE" -quiet
VALIDATION_DEVICE=""
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
print "Created notarized public release: $DMG_PATH"
