#!/bin/zsh
set -euo pipefail

# Build a Finder-native DMG with saved icon positions and a verified background.
# Usage: create-dmg-layout.sh <app path> <output dmg> <volume name>
[[ $# -eq 3 ]] || { print -u2 "Usage: $0 <app path> <output dmg> <volume name>"; exit 64; }

APP_PATH="$1"
DMG_PATH="$2"
VOLUME_NAME="$3"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="$PROJECT_DIR/build/dmg-tools"
BACKGROUND_PATH="$(mktemp /tmp/lumaview-installer-artwork.XXXXXX).png"

cleanup() {
  rm -f "$BACKGROUND_PATH"
}
trap cleanup EXIT

[[ -d "$APP_PATH" ]] || { print -u2 "App bundle not found: $APP_PATH"; exit 66; }

PACKAGING_PYTHON=""
for candidate in "${PACKAGING_PYTHON:-python3}" /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  if "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
    PACKAGING_PYTHON="$candidate"
    break
  fi
done
[[ -n "$PACKAGING_PYTHON" ]] || {
  print -u2 "DMG packaging needs Python 3.10 or newer. Set PACKAGING_PYTHON to its executable."
  exit 69
}

if [[ -x "$TOOLS_DIR/bin/python3" ]] && ! "$TOOLS_DIR/bin/python3" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
  rm -rf "$TOOLS_DIR"
fi
if [[ ! -x "$TOOLS_DIR/bin/python3" ]]; then
  "$PACKAGING_PYTHON" -m venv "$TOOLS_DIR"
fi
"$TOOLS_DIR/bin/python3" -m pip install --disable-pip-version-check -q -r "$PROJECT_DIR/Scripts/dmg-requirements.txt"

swift "$PROJECT_DIR/Scripts/create-dmg-background.swift" "$BACKGROUND_PATH"
rm -f "$DMG_PATH"
"$TOOLS_DIR/bin/dmgbuild" \
  -s "$PROJECT_DIR/Scripts/dmg-settings.py" \
  -D app="$APP_PATH" \
  -D background="$BACKGROUND_PATH" \
  "$VOLUME_NAME" "$DMG_PATH"
hdiutil verify "$DMG_PATH"
