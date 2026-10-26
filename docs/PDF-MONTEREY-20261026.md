# PDF pages and Monterey compatibility — 2026-10-26

This is an unpublished test build. The existing release version has not been changed.

## Behavior

- Multi-page PDFs show a compact page control in the bottom information bar, using Tabler v3.49.0 `chevron-up` / `chevron-down`. Up / Down turn pages; Page Up / Page Down remain available. Left / Right continue to browse files.
- Page changes reset zoom/rotation, fit the window to the selected page, dismiss old Information, and cancel obsolete render/metadata/print work. Single-page documents have no extra page controls.
- Switching files and returning to a PDF restores its last-read page in that window. Reading positions are bounded to 128 PDFs, cleared with the window, and clamped if a document loses pages.
- Information shows the current page and dimensions in points. The native print command prints the current page.
- Core Graphics renders only the requested page. The existing shared LRU budgets and 5,120-pixel render ceiling remain; no PDF engine dependency was added. Password-locked PDFs, search/selection, annotations and full-document printing are not supported.
- The app now targets macOS 12.0 on Intel and Apple Silicon. Settings use native tabs and grouped controls; information rows and scroll indicators use APIs available on Monterey.

## Verification

- Final Monterey-targeted core suite: **59 passed, 0 failed**, including actual PDF pixels at four intrinsic rotations, nonzero crop origins, page-specific cache/print output, invalid/cancelled/locked files and per-window page state.
- Universal Release compiled successfully. Both Mach-O slices report `minos 12.0`; `LSMinimumSystemVersion` is `12.0`; local code-signature verification passes. All seven language resources are present.
- Release app: 4,416,534 bytes (4.21 MiB). Test ZIP: 1,780,158 bytes. These are artifact sizes, not performance measurements.
- Focused UI session before the Monterey layout changes: ordinary-image navigation and single-page PDF tests passed. The multi-page test verified buttons, Page Up/Down, mixed page geometry, overflow Information, page-change dismissal, file navigation and zoom, then failed because its final Fit button locator used `Fit to window` instead of the actual `Fit image`. The locator is corrected and compiles, but the full case has **not been rerun** after foreground automation was stopped following the user's concern about desktop interaction.
- Manual app-window checks confirmed the Chinese page controls, page proportions, overflow Information and dismissal. A later CUA zoom check encountered a blank canvas while window visibility/focus was uncertain; the subsequent focused XCTest successfully verified rendered content and a higher zoom value. A final foreground visual check remains necessary, especially after the Monterey-compatible layout changes.
- No stress test or screen-recording permission change was performed. Hosted core tests now skip document-window creation. Temporary app registrations were removed from LaunchServices.

## Remaining checks

Run the corrected multi-page UI case in an agreed foreground test session, including Fit and rotation; inspect the final information/settings layout. Test launch and the main workflow on a real macOS 12 Mac. Newer-host compilation and tests do not establish Monterey runtime compatibility. No GitHub release or website compatibility claim has been published.

Local evidence is under `.build/pdf-pages/`: `Monterey-core.xcresult`, `Regression.xcresult`, `monterey-release.log`, and `LumaView-PDF-Monterey-test.zip`. These artifacts are not committed.

ZIP SHA-256: `0df535c08434ec1079ce22ee92028009f740d3ca072a29aa2e0729a85474196c`.

## Arrow-key follow-up

The first test package bound only Page Up / Page Down, so bare Up / Down did not turn pages. Added window-local SwiftUI shortcuts to the page buttons, kept the Browse menu's Page Up / Page Down bindings, and updated tooltips and the UI regression to cover both pairs.

After this change, all 59 core tests passed (`PDF-arrow-core.xcresult`). The updated UI regression compiled but was not executed; no keyboard/mouse automation or screen capture was used. Universal Release compiled and both slices still target macOS 12.0; code-signature and ZIP-integrity checks passed. Actual shortcut interaction and Monterey hardware verification remain pending.

Updated package: `.build/pdf-pages/LumaView-PDF-arrow-keys-test.zip` (1,781,702 bytes). SHA-256: `e8ec4cff02ca2ba1197575b703147cbba7ba94fe6fbc4eee83f6106d5f5db7a9`.

## Reading-position follow-up

Added a bounded, window-local page history. The core suite now passes **63 tests**, including an immediate file round trip from page 37 of a generated 225-page PDF, separate positions for identical filenames in different folders, independent windows, returning intentionally to page one, document truncation and least-recently-used eviction. The existing rapid-navigation test now expects the saved page; the UI regression also expects restoration instead of page-one reset.

Evidence: `PDF-reading-history-core.xcresult` and `pdf-reading-history-release.log`. Universal Release, macOS 12.0 target checks, code-signature verification and ZIP integrity passed. No foreground UI test, mouse/keyboard automation or stress test was run; the compiled UI regression and Monterey runtime verification remain pending.

Updated package: `.build/pdf-pages/LumaView-PDF-reading-memory-test.zip` (1,789,240 bytes). SHA-256: `b6ef5332fc902fa236169cc78e29f504b7847887f3a4b8311f1891275a96d174`.

## Monterey installation package

Built the current source with `Scripts/package-dmg.sh` for the user's macOS 12 installation test. Artifact: `dist/Monterey-test-20261026/LumaView-1.2.9-Monterey-test-universal.dmg` (2,284,400 bytes), with its matching `.sha256` file. SHA-256: `f275384a83bac22d1b7f7c229de408c9c5c90af01d8a6a229cfbb06116ea213d`.

This local QA installer uses the normal `com.lumaview.browser` identifier and retains version 1.2.9 (13); it is distinct from the older published 1.2.9 installer. It includes the current PDF/page-memory work. The DMG checksum, mounted Finder layout and Applications link passed; copying the enclosed app to a temporary folder preserved a valid local signature. The copied app contains all seven languages, `arm64` and `x86_64`, and both binary slices and Info.plist specify macOS 12.0. The package is ad-hoc signed, not notarized, and was not published. Monterey runtime validation remains for the user's target Mac; no desktop interaction was performed during packaging.

## Monterey settings and keyboard follow-up — build 14

The user's real Monterey test found poor Settings layout and non-working Up / Down keys in build 13. The previous SwiftUI button-shortcut implementation is superseded by a narrowly scoped `LumaDocumentWindow.sendEvent` handler. It accepts only its own key-window events, multi-page PDFs and unmodified physical Up / Down or Page Up / Down codes; text controls, sheets and modal windows retain their keyboard behavior. Boundary events are consumed without panning the document. No global/local event monitor or synthesized system keyboard event is used.

Settings now has General and Default Applications tabs, aligned native controls and an explicit common-format checklist (JPEG, PNG, HEIC, HEIF, WebP, GIF, TIFF, BMP, ICO and PDF). Selection is staged until Apply. Only the installed running copy may be assigned; each NSWorkspace request is followed by readback, partial failures remain selected, and system cancellation stops further requests. All new strings are present in seven languages. Application state is checked by canonical URL so an older duplicate with the same bundle identifier is not accepted as the installed default.

Verification on the development host: **68 core tests passed, zero failures** (`Settings-final-core.xcresult`). New tests cover direct AppKit-window key delivery, page boundaries/repeats/modifiers/focus, explicit and scoped association changes, failed/no-op system results, cancellation, external refresh and temporary-copy rejection. Association tests use a fake service and do not change real file associations. Six invisible-window renders cover both settings tabs in English, Chinese and Russian; inspected Chinese panes and the longer Russian checklist fit. The final header-alignment adjustment also passed the focused render test (`Settings-alignment-render.xcresult`). Rendering uses `NSView.cacheDisplay`, not screen capture, and never orders the window onto the desktop.

Installer: `dist/Monterey-settings-b14-20261026/LumaView-1.2.9-Monterey-test-b14-universal.dmg`, **2,412,526 bytes**, SHA-256 `fde51ce76a92081090b9025bce6e5304161a4fe9eeafe5d05286321154d8d668`. The mounted/copy-verified app is `com.lumaview.browser` **1.2.9 (14)**; Info.plist and both `arm64` / `x86_64` slices require macOS 12.0. Finder installer layout, Applications link, seven language resources, local signature and final filename/checksum verification passed. Earlier build-13 installers were not overwritten.

Real Monterey appearance, physical keyboard interaction, native consent dialogs and Finder association behavior still need verification on the target Mac. No broad UI automation, screen capture, stress test or public release was performed for this follow-up.

## Settings design follow-up — build 15

A UI designer reviewed the user's build-14 screenshot: Settings had promoted the text-only TabView into an oversized icon toolbar with empty icon slots. Replace it with a native segmented picker inside the content view. General now uses compact label/control rows, one divider, version and update action on the same row, and a shorter seven-language update description. The default-app page uses aligned 28-point rows, subtle alternating backgrounds and separate selection/apply actions. Content width is 560 points; General is 280 points (320 when an update is available), Default Applications is 510 points.

The focused XCTest passed and produced **12 offscreen full-frame renders** covering both pages, English/Chinese/Russian, light/dark. It includes the titlebar/navigation and asserts there is no generated toolbar. The UI designer reviewed the renders; final inspection confirmed all 10 format rows and bottom controls fit after reducing the table's empty space. This was a layout-only follow-up; default-app behavior and PDF keyboard handling were not changed. No foreground automation or real association change was performed. Actual Monterey appearance still requires target-system verification.

Evidence: `Settings-redesign-final-b15.xcresult`, `settings-redesign-final-render/` and `settings-b15-dmg.log` under `.build/pdf-pages/`. Installer: `dist/Monterey-settings-b15-20261026/LumaView-1.2.9-Monterey-test-b15-universal.dmg`, **2,415,749 bytes**, SHA-256 `3b88028201c1026150e304b082bae652163a4fb2b7960a7385cedec1c4ba6677`. The copied app is 1.2.9 (15), has both architectures targeting macOS 12.0, all seven locales and a valid local signature. Mounted layout, Applications link and checksum checks passed.
