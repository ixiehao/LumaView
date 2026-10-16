# LumaView release and QA gate

Run this checklist before creating a universal (`arm64` + `x86_64`) release DMG.

- [ ] `./Scripts/validate-project.sh` passes on an Apple Silicon Mac and verifies both universal Release slices.
- [ ] For a lifecycle or performance release, run the optional real-window 1 / 4 / 8 5K rendering gate with `LUMAVIEW_RUN_STRESS_TEST=1 ./Scripts/validate-project.sh`: first canvas appears within 25 seconds; all canvases appear within `30 + 12 × window count` seconds; every source has exactly one AppKit window, stable document accessibility scope, and an independent initial canvas/viewport state; target RSS stays below 1.2 GiB. These are broad lifecycle safety limits, not a device benchmark; routine functional releases skip this opt-in gate.
- [ ] The automated Finder-style opening test passes: a file opened at launch shows before directory indexing completes, and `←` / `→` moves between its natural-order siblings. The router unit test separately covers buffered pre-launch URLs, duplicate filtering, unsupported URLs, and a new open event while the app is already running.
- [ ] English, Simplified Chinese, and Japanese have been checked in Light and Dark appearance, including every visible toolbar label.
- [ ] Open **LumaView → Settings…** (`⌘,`) and confirm the window is not blank: it must contain the appearance picker, language picker, installed-version text, and **Check for Updates…** button. This is a manual check because macOS exposes the app-level Settings command unreliably to XCTest across host versions.
- [ ] Folder scan, previous/next, zoom, fit, rotation, print, Finder reveal, drag-and-drop, and unsupported-file feedback have been checked manually. For print, use a non-sensitive image, open `⌘P`, verify the standard macOS panel, then cancel or save to a disposable PDF. For drag-and-drop, use a real Finder drag rather than a synthetic provider.
- [ ] Click the **Image Information** toolbar button for a photo with EXIF and for a PNG without EXIF. Confirm the compact inspector shows file facts in both cases, only shows camera rows when they exist, and does not change the displayed image.
- [ ] For the 1 / 4 / 8 window case, click Next then Previous (or Rotate Right then Rotate Left) in each visible window and confirm its neighbour windows keep their image and viewport unchanged. XCTest covers the focused one-window actions and store isolation, but macOS does not reliably target a background window toolbar after z-order changes.
- [ ] With VoiceOver enabled, verify the hidden visual titlebar still announces the current document window title, the canvas announces its image name / zoom / rotation, and every toolbar button has a localized label.
- [ ] Check a valid supported format and an intentionally corrupt file with an accepted extension; the latter must show a preview error rather than a blank welcome window.
- [ ] A large image and a non-private `.sketch` document preview correctly.
- [ ] `LICENSE`, `THIRD-PARTY-NOTICES.md`, `PRIVACY.md`, `SECURITY.md`, and `CHANGELOG.md` describe the shipped build accurately.
- [ ] Marketing version, build number, annotated Git tag, release notes, DMG filename, and SHA-256 agree.
- [ ] The internal QA DMG installs on a clean Apple Silicon account and its contained executable reports both architectures with `lipo -archs`.
- [ ] On an Intel Mac, open a supported image and verify previous/next, zoom, rotation, print, quit, and reopen. Cross-compilation and `lipo` validation do not replace this hardware smoke check.
- [ ] Before public distribution: Developer ID signature, notarization, stapling, Gatekeeper assessment, and a clean-machine install all pass.

A release package missing either `arm64` or `x86_64` is a release failure.

## LaunchServices coverage boundary

XCTest can launch the app with an explicit file URL, but it cannot reliably
make Finder/LaunchServices deliver a second system-level Open event to an
already-running app on every CI host. `ExternalDocumentOpenRouter` is therefore
unit-tested as the shared routing layer used by `application(_:open:)`,
`application(_:openFiles:)`, and `application(_:openFile:)`. Before release,
perform the manual Finder check: leave LumaView running, double-click a second
supported image in Finder, and confirm it opens in its own non-blank window
without changing the first window's image or creating a welcome window.
