#!/bin/zsh
# Shared build contract for validation and both installer entry points.
# Source from zsh after setting PROJECT_DIR.
LUMAVIEW_ARCH="${LUMAVIEW_ARCH:-universal}"
case "$LUMAVIEW_ARCH" in
  arm64) LUMAVIEW_BUILD_ARCHS=(arm64) ;;
  x86_64) LUMAVIEW_BUILD_ARCHS=(x86_64) ;;
  universal) LUMAVIEW_BUILD_ARCHS=(arm64 x86_64) ;;
  *) print -u2 "LUMAVIEW_ARCH must be arm64, x86_64, or universal; got: $LUMAVIEW_ARCH"; exit 64 ;;
esac

LUMAVIEW_WARNING_SETTINGS=(SWIFT_STRICT_CONCURRENCY=complete)
case "${LUMAVIEW_STRICT_WARNINGS:-0}" in
  0) ;;
  1) LUMAVIEW_WARNING_SETTINGS+=(SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES) ;;
  *) print -u2 "LUMAVIEW_STRICT_WARNINGS must be 0 or 1."; exit 64 ;;
esac

build_release_app() {
  local derived_data="$1"
  shift
  xcodebuild \
    -project "$PROJECT_DIR/LumaView.xcodeproj" \
    -scheme LumaView \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    "ARCHS=${(j: :)LUMAVIEW_BUILD_ARCHS}" ONLY_ACTIVE_ARCH=NO \
    SWIFT_OPTIMIZATION_LEVEL=-Osize SWIFT_COMPILATION_MODE=wholemodule \
    DEAD_CODE_STRIPPING=YES \
    "${LUMAVIEW_WARNING_SETTINGS[@]}" "$@" build
}

verify_app_architecture() {
  local app_path="$1"
  local binary="$app_path/Contents/MacOS/LumaView"
  local actual
  actual="$(lipo -archs "$binary")" || return 1
  local -a slices
  slices=(${=actual})
  slices=("${(@o)slices}")
  if [[ "${(j: :)slices}" != "${(j: :)LUMAVIEW_BUILD_ARCHS}" ]]; then
    print -u2 "Expected $LUMAVIEW_ARCH package, found slices: $actual"
    return 1
  fi
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_path/Contents/Info.plist")" == "12.0" ]] || {
    print -u2 "App must declare macOS 12.0 as its minimum system."
    return 1
  }
  local architecture minimum_os
  for architecture in "${LUMAVIEW_BUILD_ARCHS[@]}"; do
    minimum_os="$(xcrun vtool -arch "$architecture" -show-build "$binary" | awk '/minos/ {print $2}')" || return 1
    [[ "$minimum_os" == "12.0" ]] || {
      print -u2 "$architecture binary requires macOS $minimum_os, expected 12.0."
      return 1
    }
  done
}
