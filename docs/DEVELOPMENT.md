# Developing LumaView

[Documentation index](README.md) · [Contributing](../CONTRIBUTING.md)

## Repository layout

- `LumaView/` — native application source, image pipeline and localization.
- `LumaView.xcodeproj/` — Xcode project and shared build configuration.
- `Scripts/` — validation, packaging and release scripts; `tools/` — auxiliary QA tools.
- `website/` — public website source; `docs/` — maintainer documentation.

Use macOS and Xcode with the SDK required by the checked-in project. Open `LumaView.xcodeproj` and select the LumaView scheme for interactive development. Check the current deployment target in the project; do not infer it from a local machine's OS.

## Validation

From the repository root:

```sh
./Scripts/validate-project.sh
```

This runs core/UI tests in one XCTest session, then builds a release application and verifies both arm64 and x86_64 slices. UI tests require an interactive macOS session. For the optional generated-image stress gate:

```sh
LUMAVIEW_RUN_STRESS_TEST=1 ./Scripts/validate-project.sh
```

Failed GitHub CI runs retain an `LumaView-test-results` artifact for seven days. Open its `.xcresult` in Xcode to inspect assertions, accessibility snapshots and generated-fixture screenshots. To retain a local result bundle, set `LUMAVIEW_TEST_RESULT_PATH` to a new absolute `.xcresult` path outside the temporary build directory; Xcode requires that destination not to exist yet.

Run checks proportional to the change. Website-only and documentation-only changes use [website checks](WEBSITE.md) and link review; they do not require rebuilding an installer.

## Manual verification

Follow [QA](QA.md) for browsing, unsupported files, large images, navigation and language changes. Decode/navigation changes need real authorized image samples in addition to synthetic tests. Keep rotation, navigation and asynchronous image results tied to current state; cancellation must not allow an old result to replace a newer selection.

## Localization

The app supports English (`en`), Simplified Chinese (`zh-Hans`), French (`fr`), Russian (`ru`), Spanish (`es`), Japanese (`ja`) and Korean (`ko`). `AppLanguage.allCases` is the shared menu/settings order, with English first and Automatic last. Automatic remains the default preference; it follows the system language preference order and falls back to English.

Each language needs a real `.lproj/Localizable.strings` resource registered in the Xcode variant group and `knownRegions`. Keep key sets and format placeholders identical, use native language names in the selector, and verify actual toolbar/menu labels in the built app. Core tests also check region matching and repeated menu language changes.

SwiftUI owns command creation, including the full-screen command for AppKit viewer windows. Native menu-title localization follows menu-change notifications; coalesce updates, skip unchanged titles and ignore self-generated notifications. Do not insert persistent commands during localization: SwiftUI can remove them on its next rebuild.

## Packaging

Follow [RELEASE.md](RELEASE.md); it distinguishes preview builds from Developer ID–signed, notarized distribution. Do not treat a successful local build as a release authorization.
