#!/bin/zsh
set -euo pipefail

# One repeatable local gate for contributors and CI. Derived files live in a
# temporary directory so validation never changes a checked-out project.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/Scripts/build-common.sh"
TEST_ARCHITECTURE="$(uname -m)"
if [[ "$LUMAVIEW_ARCH" != "universal" && "$LUMAVIEW_ARCH" != "$TEST_ARCHITECTURE" ]]; then
  print -u2 "Native $LUMAVIEW_ARCH validation requires a $LUMAVIEW_ARCH host; current process is $TEST_ARCHITECTURE."
  exit 64
fi
# A translated shell is not evidence of testing on Intel hardware.
if [[ "$(sysctl -in sysctl.proc_translated 2>/dev/null || true)" == "1" ]]; then
  print -u2 "Use a native shell for validation. Rosetta execution is not native Intel verification."
  exit 64
fi
TEST_SELECTION=()
case "${LUMAVIEW_TEST_SCOPE:-all}" in
  all) ;;
  core) TEST_SELECTION=(-only-testing:LumaViewTests) ;;
  *) print -u2 "LUMAVIEW_TEST_SCOPE must be all or core."; exit 64 ;;
esac
STAGE_DIR="$(mktemp -d /tmp/lumaview-validation.XXXXXX)"
DERIVED_DATA="$STAGE_DIR/DerivedData"
# CI keeps its result bundle outside the disposable build directory so a
# failed assertion retains the generated-fixture screenshots and AX hierarchy.
TEST_RESULT_PATH="${LUMAVIEW_TEST_RESULT_PATH:-$STAGE_DIR/Tests.xcresult}"
VALIDATION_BUNDLE_ID='com.lumaview.validation.$(PRODUCT_NAME)'

cleanup() {
  # XCTest registers its temporary app with LaunchServices. Remove that entry
  # before deleting the build so Finder cannot offer a vanished validation app.
  local registration_tool="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  local app
  for app in "$DERIVED_DATA"/Build/Products/{Debug,Release}/*.app(N); do
    "$registration_tool" -u "$app" >/dev/null 2>&1 || true
  done
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"

# Fast offline regression checks for installer output safety.
python3 Scripts/test-packaging.py
python3 Scripts/build-website.py --check

# Run core and UI tests in one locally signed XCTest session. Splitting macOS UI
# automation into a second `xcodebuild` process can leave the accessibility service
# claimed by the first runner, producing a false timeout before UI tests even start.
# UI coverage uses generated local image fixtures and disables update checks.
xcodebuild \
  -project LumaView.xcodeproj \
  -scheme LumaView \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$TEST_RESULT_PATH" \
  -destination "platform=macOS,arch=$TEST_ARCHITECTURE" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 300 \
  "ARCHS=$TEST_ARCHITECTURE" ONLY_ACTIVE_ARCH=YES \
  PRODUCT_BUNDLE_IDENTIFIER="$VALIDATION_BUNDLE_ID" \
  "${TEST_SELECTION[@]}" "${LUMAVIEW_WARNING_SETTINGS[@]}" \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-"

build_release_app "$DERIVED_DATA" \
  PRODUCT_BUNDLE_IDENTIFIER="$VALIDATION_BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=NO

verify_app_architecture "$DERIVED_DATA/Build/Products/Release/LumaView.app"

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
