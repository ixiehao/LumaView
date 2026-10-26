# Developing LumaView

[Documentation index](README.md) · [Contributing](../CONTRIBUTING.md)

## Repository layout

- `LumaView/` — native application source, image pipeline and localization.
- `LumaView.xcodeproj/` — Xcode project and shared build configuration.
- `Scripts/` — validation, packaging and release scripts; `tools/` — auxiliary QA tools.
- `website/` — public website source; `docs/` — maintainer documentation.

Use macOS and Xcode with the SDK required by the checked-in project. Open `LumaView.xcodeproj` and select the LumaView scheme for interactive development. Check the current deployment target in the project; do not infer it from a local machine's OS.

## Validation

The current source targets macOS 12.0 Monterey on both Intel and Apple Silicon. Information rows and canvas scrolling use Monterey-compatible layout APIs; settings use a native segmented picker and compact aligned rows on all supported versions. Avoid a text-only TabView inside Settings: the scene promotes it to a tall icon toolbar with empty icon slots. The validation script checks both Mach-O slices and `LSMinimumSystemVersion`, in addition to compiling against the deployment target. Compilation on a newer host does not replace a Monterey hardware smoke test. LumaView 1.3.0 targets macOS 12; the older v1.2.9 download requires macOS 13.

Hosted core tests skip document-window creation in Debug builds. They exercise AppKit/model/decoder code without driving mouse or keyboard. UI tests still require the test window to hold macOS focus, even when every query and screenshot is scoped to LumaView; do not run them unexpectedly on a user's active desktop.

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

## PDF pages

Multi-page support is recorded under **Unreleased** in the changelog. File navigation remains Left / Right; PDF page navigation uses the bottom page controls or Up / Down. Page Up / Page Down (Fn-Up / Fn-Down on compact Mac keyboards) remain available through the Browse menu. `LumaDocumentWindow.sendEvent` handles physical page-key codes only for its own key window with a multi-page PDF, outside text/control focus, sheets and modal dialogs. This replaces the unreliable Monterey SwiftUI HUD shortcuts without an application-wide event monitor. Boundary presses are consumed so they do not pan the canvas. Single-page PDFs and images do not show the extra controls. Printing exports only the selected PDF page through the existing native print panel.

Core Graphics reads the page count, crop box and intrinsic rotation on the bounded metadata queue. Page selection belongs to each window and resets fit/rotation. Every selection advances the generation used to reject stale render, inspector and print results. Render and metadata cache keys include the file fingerprint and zero-based page index; global memory budgets are unchanged. Only page zero may reuse the adjacent-file preview.

Each window also remembers the last-read page of up to 128 PDFs by canonical file URL. Returning to a file restores that page at fit zoom; page records are updated synchronously so a quick file switch cannot lose progress. Only URLs and nonzero page indices are stored, with least-recently-used eviction. This memory disappears with the window; it does not persist across relaunches or retain document bitmaps. If a PDF loses pages, metadata validation clamps the saved index to its last remaining page through the normal selection pipeline.

Render the current page into a bounded bitmap (longest edge at most 5,120 pixels). Apply the crop/rotation transform in page points and scale explicitly into the bitmap: `getDrawingTransform` alone does not enlarge a small page. Use points for PDF dimensions/zoom, pixels for raster images. The existing 128 MiB source-file limit applies. Password-locked PDFs report an unavailable preview; password entry, text selection/search, annotations and full-document printing are outside this viewer's current scope.

Core tests cover distinct page pixels, crop origins, all four intrinsic rotations, cache invalidation, page boundaries, cancellation, malformed/locked files, current-page metadata/print output and independent window state. UI tests cover page buttons/shortcuts, mixed page dimensions, overflow Information, inspector dismissal, zoom, file navigation and single-page behavior. A core bitmap test does not require screen-recording permission.

## Settings and default applications

Use the macOS 12 `NSWorkspace` content-type APIs to read and set the default application. Stage checkboxes first; only the explicit Apply action writes associations. Handle individual UTTypes, never the generic `public.image` parent. Select Images excludes PDF. Existing LumaView defaults are checked and read-only; Finder's Get Info remains the place to choose another app.

Only allow the running app in `/Applications` or the user's Applications directory to become a default. Compare canonical application URLs rather than bundle IDs: mounted installers and older copies can share the same identifier. Await each request, read back the result, report partial failures and stop after a system consent cancellation. Refresh on returning to Settings without writing anything. Tests inject a fake handler; real LaunchServices/default-app changes require a controlled account and must not silently alter the developer's setup.

The settings render test uses invisible AppKit windows and `NSView.cacheDisplay`, so it neither records the screen nor takes keyboard focus. It captures the entire local frame view, including the titlebar and segmented navigation, in English, Chinese and Russian, in both light and dark appearance. It asserts that no icon toolbar is created. It does not establish native Monterey appearance or user-consent behavior.

## Packaging

Follow [RELEASE.md](RELEASE.md); it distinguishes preview builds from Developer ID–signed, notarized distribution. Do not treat a successful local build as a release authorization.
