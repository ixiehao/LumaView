# LumaView

**A fast, minimal native image viewer for macOS.**

Open an image and browse the rest of its folder. LumaView keeps the picture in
focus, with the everyday controls close at hand.

**[Download LumaView 1.3.0 · Universal DMG](https://github.com/ixiehao/LumaView/releases/download/v1.3.0/LumaView-1.3.0-universal.dmg)** · [Website](https://ixiehao.github.io/LumaView/en/) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Changelog](CHANGELOG.md)

macOS 12+ · Intel + Apple Silicon · Universal DMG · ~2.5 MB

## LumaView in use

| Open a file | Browse its folder |
| --- | --- |
| ![LumaView native welcome screen with one Open File action](docs/assets/lumaview-welcome.png) | ![LumaView browsing images with folder position and previous-next controls](docs/assets/lumaview-browse.png) |

## Highlights

- **Browse naturally** — open from Finder, choose a file, or drag it in; use `←` / `→` or the toolbar for the previous and next image in the folder.
- **See the image clearly** — fit, zoom, pan, rotate, and print; the status bar shows the actual zoom level.
- **Inspect only when needed** — one toolbar button reveals file facts and the EXIF data embedded in the current image, without a separate folder-wide metadata scan or library.
- **Open the formats you meet every day** — JPEG, PNG, HEIC, GIF, TIFF, BMP, ICO, WebP, PDF, many macOS-supported RAW files, and `.sketch` previews.
- **Built for the Mac** — native SwiftUI, English, Chinese, French, Russian, Spanish, Japanese, and Korean; Light / Dark / System appearance; Intel and Apple Silicon support.

- **Read PDFs** — turn pages with `↑` / `↓`; keep your page, zoom and rotation while reading.
- **Choose default formats** — set LumaView as the default viewer from Settings.

## Install

1. [Download the Universal DMG](https://github.com/ixiehao/LumaView/releases/download/v1.3.0/LumaView-1.3.0-universal.dmg).
2. Open it and drag **LumaView.app** to **Applications**.
3. Open LumaView from Applications. To open an image directly, Control-click it in Finder and choose **Open With → LumaView**.

### If macOS blocks the first launch

Messages vary by macOS version: the developer may be unverified, or Apple may be unable to check the app for malicious software. If you trust the copy downloaded from this project's GitHub Releases or supplied by the developer for testing:

1. Try opening **LumaView** from Applications once, then dismiss that alert.
2. Follow the settings path below, find the message about **LumaView**, and click **Open Anyway**.
3. Authenticate if prompted, then confirm **Open**. Subsequent launches normally work by double-clicking.

| macOS version | Settings path |
| --- | --- |
| macOS 12 Monterey | Apple menu → **System Preferences → Security & Privacy → General** |
| macOS 13 Ventura or later | Apple menu → **System Settings → Privacy & Security**, then scroll to **Security** |

If **Open Anyway** is missing, try opening LumaView again, then return to settings. A damaged-app or malware warning is different: stop and download a fresh copy from the project or report the issue instead of overriding it.

See [Apple's opening instructions](https://support.apple.com/en-us/102445).

### Make LumaView the default image viewer

In Finder, select an image → press `⌘I` → choose **LumaView** under **Open with** → click **Change All…**.

The DMG is only the installer. Removing it never removes LumaView or your images; to uninstall later, move `LumaView.app` from Applications to Trash.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open file | `⌘ O` |
| Open files in new windows | `⌘ ⇧ O` |
| Previous / next PDF page | `↑` / `↓` |
| Keep file information visible | `⌃ ⌘ I` |
| Previous / next image | `←` / `→` |
| Zoom in / out | `⌘ +` / `⌘ -` |
| Fit image | `⌘ 0` |
| Rotate left / right | `⌘ [` / `⌘ ]` |
| Print current image | `⌘ P` |

## Build from source

Requirements: macOS 13+, Xcode 15+, and an Intel or Apple Silicon Mac.

```sh
open LumaView.xcodeproj
# Select the LumaView scheme, then press ⌘R.
```

Before opening a pull request, run:

```sh
./Scripts/validate-project.sh
```

Release packaging, manual QA, and performance baselines are documented in
[Release guide](docs/RELEASE.md), [QA guide](docs/QA.md), and
[Performance baseline](docs/PERFORMANCE_BASELINE.md).

## Feedback and contribution

Found a problem or have an idea? Use the structured [bug report](https://github.com/ixiehao/LumaView/issues/new?template=bug_report.yml) or [feature request](https://github.com/ixiehao/LumaView/issues/new?template=feature_request.yml) form. See [Contributing](CONTRIBUTING.md) for development expectations, [Privacy](PRIVACY.md) for local-data behavior, and [Security](SECURITY.md) for responsible disclosure.

LumaView is available under the [MIT License](LICENSE). Tabler icon attribution is listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Development documentation

[Documentation index](docs/README.md) · [Development and validation](docs/DEVELOPMENT.md) · [Website maintenance](docs/WEBSITE.md).

The official website source lives in `website/`; `docs/` is reserved for maintainer documentation.
