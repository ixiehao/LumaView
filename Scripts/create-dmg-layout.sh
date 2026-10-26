#!/bin/zsh
set -euo pipefail

# Build a Finder-native DMG with saved icon positions and a verified background.
# Usage: create-dmg-layout.sh <app path> <output dmg> <volume name>
[[ $# -eq 3 ]] || { print -u2 "Usage: $0 <app path> <output dmg> <volume name>"; exit 64; }

APP_PATH="${1:a}"
DMG_PATH="${2:a}"
VOLUME_NAME="$3"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="$PROJECT_DIR/build/dmg-tools"

[[ -d "$APP_PATH" ]] || { print -u2 "App bundle not found: $APP_PATH"; exit 66; }
[[ ! -e "$DMG_PATH" && ! -L "$DMG_PATH" && ! -e "$DMG_PATH.sha256" && ! -L "$DMG_PATH.sha256" ]] || {
  print -u2 "Refusing to replace an existing installer or checksum: $DMG_PATH"
  exit 73
}
mkdir -p "${DMG_PATH:h}"
STAGE_DIR="$(mktemp -d "${DMG_PATH:h}/.lumaview-dmg-layout.XXXXXX")"
BACKGROUND_PATH="$STAGE_DIR/background.png"
STAGED_DMG="$STAGE_DIR/installer.dmg"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

if [[ -n "${PACKAGING_PYTHON:-}" ]]; then
  PYTHON_CANDIDATES=("$PACKAGING_PYTHON")
else
  PYTHON_CANDIDATES=(python3 /opt/homebrew/bin/python3 /usr/local/bin/python3)
fi
PACKAGING_PYTHON=""
for candidate in "${PYTHON_CANDIDATES[@]}"; do
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
"$TOOLS_DIR/bin/dmgbuild" \
  -s "$PROJECT_DIR/Scripts/dmg-settings.py" \
  -D app="$APP_PATH" \
  -D background="$BACKGROUND_PATH" \
  "$VOLUME_NAME" "$STAGED_DMG"
hdiutil verify "$STAGED_DMG"
# Publish only a verified image, without overwriting a file created meanwhile.
# Staging beside the destination keeps this atomic link on the same filesystem.
"$TOOLS_DIR/bin/python3" -c 'import os, sys; os.link(sys.argv[1], sys.argv[2])' "$STAGED_DMG" "$DMG_PATH"
