# LumaView

**A local, native image browser for Apple Silicon Macs.**

LumaView opens an image and keeps the focus on it: browse forward and back
within its folder, inspect large files, zoom, rotate, print, and reveal the
current item in Finder. It does not create an image library, copy source files,
require an account, or upload images.

[**Latest release: v1.2.1 arm64 DMG**](https://github.com/ixiehao/LumaView/releases/tag/v1.2.1) · macOS 13+ · Apple Silicon only

[Official site](https://ixiehao.github.io/LumaView/) · [简体中文](README.zh-CN.md) · [Contributing](CONTRIBUTING.md) · [Privacy](PRIVACY.md) · [Security](SECURITY.md) · [Release guide](docs/RELEASE.md) · [Changelog](CHANGELOG.md)

## Application screenshots

| Start locally | Browse without a sidebar |
| --- | --- |
| ![Real LumaView welcome screen in Chinese, with one Open File action](docs/assets/lumaview-welcome.png) | ![Real LumaView image browser showing folder position and previous-next controls](docs/assets/lumaview-browse.png) |

These are screenshots from a running LumaView build. They use only original
test artwork and contain no user photo, filename, folder, or desktop content.

## Highlights

- Native SwiftUI interface for macOS 13 or later on **Apple Silicon only**. Intel Macs are not supported.
- Choose one image, open it from Finder, or drag it into the window. LumaView shows that image first, then indexes only its immediate folder so previous/next works without a persistent file list.
- LumaView registers with Finder as an optional Viewer for macOS image types, PDFs, and `.sketch` documents. Choose **LumaView** in Finder’s **Open with** menu, then use **Change All…** when you want it as the default for that file type.
- View JPEG, PNG, HEIC, GIF, TIFF, BMP, ICO, WebP, PDF, many system-supported RAW formats, and `.sketch` documents. Sketch files use their embedded page preview; supported bitmap formats still depend on macOS codecs.
- Zoom, fit, rotate, scroll/pan large images, and print with standard shortcuts. The status bar reports the rendered size as an absolute percentage of the source image.
- Immediate English / 简体中文 / System language and Light / Dark / System appearance controls.
- A native About panel covers version, privacy, license, project, feedback, and a checked release update. The updater checks only public GitHub release metadata and validates that download links belong to the configured project repository.
- Tabler Icons Outline assets are bundled locally and share one 24 × 24 / 2 pt visual language. The LumaView mark is an original project asset.
- Previous/next is optimized as a first-class viewer action: only the two adjacent images are predecoded into compact, memory-only bridge frames, while visible images use two bounded render workers.
- Bounded, memory-only image cache: 24 MiB adjacent-image previews, 120 MiB renders, one utility prefetch worker, two full-image workers, and a 5K decode ceiling.

## Requirements

- Apple Silicon Mac (arm64)
- macOS 13 Ventura or later
- Xcode 15 or later for source builds

## Download

Open [the latest release](https://github.com/ixiehao/LumaView/releases/latest)
and download **`LumaView-1.2.1-arm64.dmg`** together with its matching
`LumaView-1.2.1-arm64.dmg.sha256` checksum. This build is for Apple Silicon
only; it will not run on an Intel Mac.

## Install safely

1. Double-click the downloaded `.dmg`, then drag **LumaView.app** to **Applications**.
2. After the copy finishes, eject or delete the DMG. It is only the installer and does not remove the installed app.
3. This first public preview is ad-hoc signed and is **not Apple-notarized**. If macOS cannot verify the developer, open **Applications**, Control-click **LumaView**, choose **Open**, then choose **Open** once more. Do not disable macOS system-wide security.

To remove LumaView later, quit it and move only `LumaView.app` from
Applications to Trash. Your image files remain where they are.

## Run from source

```sh
open LumaView.xcodeproj
```

Select the **LumaView** scheme and run with `⌘R`. The project deliberately
builds only an `arm64` application.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open file | `⌘ O` |
| Previous / next | `←` / `→` |
| Zoom in / out | `⌘ +` / `⌘ -` |
| Fit image | `⌘ 0` |
| Rotate left / right | `⌘ [` / `⌘ ]` |
| Print current image | `⌘ P` |

## Verify and package

```sh
./Scripts/validate-project.sh
./Scripts/package-dmg.sh
```

The validation script runs the core tests, UI tests (including a real 1 / 4 / 8
window 5K rendering gate), release build, and a synthetic image stress harness.
The real-window gate records first/all-render timing, RSS, document identity,
and independent initial viewport state; Finder-style `←` / `→` navigation is
covered in its own end-to-end test. See [QA](docs/QA.md) for the manual LaunchServices, drag,
print, VoiceOver, and corrupt-file checks that macOS cannot drive reliably in
headless XCTest.
`package-dmg.sh` creates an ad-hoc-signed DMG. The v1.2.1 GitHub release uses
the transparent preview path also used by ShotMap: it attaches the exact DMG
and its SHA-256 file, and states the non-notarized first-run recovery step.
The Developer ID, notarization, stapling, and Gatekeeper path for a future
formal arm64 release remains documented in [docs/RELEASE.md](docs/RELEASE.md).
The current 5K multi-window RSS and latency baseline is recorded in
[docs/PERFORMANCE_BASELINE.md](docs/PERFORMANCE_BASELINE.md).
Public releases require an auditable initial commit and an annotated `vX.Y.Z`
tag pointing to the shipped source; the procedure is in
[docs/RELEASE.md](docs/RELEASE.md). Packaging scripts never create commits,
tags, credentials, or a substitute signature.

## Project boundaries

LumaView is a viewer, not an editor, photo manager, cloud backup service, or
cleanup tool. Keeping those workflows out of the main path is intentional.

Source code is available under the [MIT License](LICENSE). Tabler attribution
is recorded in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
