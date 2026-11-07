# LumaView engineering review — 2026-11-06

## Scope and implementation

Four agents covered decoding/PDF/printing, AppKit/UI state, architecture packaging, and an independent final review. The existing working copy and unpublished print-layout fix were preserved. No public release or source push was performed.

- Capture a file fingerprint before navigation-preview decoding and reuse it when caching the result. External replacement cannot label old pixels with the new version; one redundant file-attribute lookup is removed.
- Cancel superseded drops and reject late results after selection changes or window disappearance. Finder reopening an existing file now refreshes the document through its normal load path.
- Cancel folder, metadata, prefetch and print work explicitly on window close, even when a callback still retains the store/window.
- Normalize extreme rotation inputs before integer conversion.
- Enable complete Swift concurrency checking. Render callbacks transfer an immutable operation identity; menu observers transfer only identity/index values. Shared cache Sendable declarations document their lock or immutable-publication boundary. UI test methods use main-actor isolation.
- Share architecture configuration and output checks across QA, notarized packaging and validation. Produce arm64 and x86_64 DMGs separately; retain universal as an optional mode. Whole-module `-Osize` and dead-code stripping optimize size, with no unmeasured latency claim.
- Bound the validation gate: 180-second per-test allowance (300-second maximum) and a 30-minute CI job limit prevent stalled automation from occupying a runner indefinitely.

## Verification

Host: Apple Silicon, macOS 27.2, Xcode 27.2 / SDK 27.2. Application minimum system remains macOS 12.0.

| Check | Result |
| --- | --- |
| Initial core tests | 81 passed |
| Initial UI tests | 12 passed, 3 failed, 1 skipped |
| Fixed arm64 core tests, strict Swift warnings treated as errors | 83 passed, no failures/skips |
| Fixed x86_64 core tests under Rosetta, strict Swift warnings treated as errors | 83 passed, no failures/skips |
| Installer script regression suite | 11 passed |
| Website generation check | Passed |
| Release architecture / minimum OS / signature / mounted binary comparison | Both QA packages passed |
| Final UI XCTest | 3 passed; full-screen exit stalled and was canceled; remaining cases could not initialize automation on two attempts |
| Window-scoped manual regression on final build | Rotation both directions, full-screen recovery, PDF arrows/Page Up/Down, page restoration after file navigation, metadata overflow/popover dismissal, zoom and fit passed |
| Rotation pixel XCTest | Initial run skipped because this isolated runner lacks Screen Recording authorization; not counted as passed |

The initial UI failures followed XCTest punctuation-key injection under Pinyin (Settings and bracket rotation shortcuts). Settings now opens through its real menu; rotation shortcut assertions remain intact and are rerun under ABC. The test target keeps macOS 12 compatibility; SDK-provided XCTest library minimum-OS linker messages and the unused App Intents metadata tool message are distinct from Swift source warnings.

The final automated passes were metadata dismissal on navigation, relocalizing an existing decode error through Settings, and all seven toolbar languages. The full-screen case reached its 90-degree rotation but failed to observe exit; the runner then stalled. A separate native-window check successfully entered full screen, rotated, exited with Control-Command-F, and displayed the complete rotated fixture at its new aspect ratio. This does not convert the failed XCTest into a pass. Restarting the test service did not resolve subsequent “Timed out while enabling automation mode” initialization failures; no remaining automated cases were counted as executed.

Manual checks used generated fixtures only. Both ABC and restored Simplified Chinese Pinyin delivered rotation and PDF arrow shortcuts. A portrait PDF exposed Information through the toolbar overflow; it showed Page 2 of 3 and 400 × 600 pt, dismissed on paging, and switching to an image and back restored Page 2. Zoom changed from 133% to 167%, and Fit returned to 133%. The isolated QA app was closed afterward; the user's installed application was not replaced.

One local environment limitation remains: enumeration of a fixture directory under Documents blocked in Foundation's directory enumerator / kernel `__open` while the UI and PDF paging remained responsive. The same fixture pair under `/tmp` indexed and navigated correctly. The process sample is retained locally; the precise system permission/filesystem cause was not established. A cancellation token cannot interrupt an already-blocked synchronous OS call, so do not describe protected-folder behavior as fully verified.

## Deliverables

- `dist/qa-20261106/LumaView-1.3.0-arm64.dmg` and SHA-256: Apple Silicon only.
- `dist/qa-20261106/LumaView-1.3.0-x86_64.dmg` and SHA-256: Intel only.

These are internal QA builds, not a new public release. Binary slice verification is exact; installer artwork identifies the selected architecture. Detailed local logs/results live under `.build/review-20261106/` and are not public source.

## Remaining platform gates

Native Intel hardware, real Monterey hardware and physical-printer output were not exercised on this host. Rosetta is supplementary validation. Native CI jobs for arm64 and x86_64 are configured but were not pushed/run in this review. Stress testing was not run.

Apple's [SDK requirements](https://developer.apple.com/xcode/system-requirements/) currently do not list a macOS 28 SDK. Strict concurrency, bounded work and availability-gated AppKit remain the preparation baseline; actual macOS 28 acceptance requires that SDK and system. The SDK 27 host also warns that the legacy `hdiutil attach` spelling is deprecated; it still validates these packages, but the installer tooling needs a version-gated migration check before that interface is removed. Do not raise the app's minimum OS solely to silence build-tool messages.
