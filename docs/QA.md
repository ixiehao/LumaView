# LumaView release and QA gate

Run this checklist before creating a universal (`arm64` + `x86_64`) release DMG.

- [ ] `./Scripts/validate-project.sh` passes on the host Mac and verifies both universal Release slices. Validation uses an isolated bundle identifier and unregisters temporary builds from LaunchServices on exit; it does not replace the installed app.
- [ ] For a lifecycle or performance release, run the optional real-window 1 / 4 / 8 5K rendering gate with `LUMAVIEW_RUN_STRESS_TEST=1 ./Scripts/validate-project.sh`: first canvas appears within 25 seconds; all canvases appear within `30 + 12 × window count` seconds; every source has exactly one AppKit window, stable document accessibility scope, and an independent initial canvas/viewport state; target RSS stays below 1.2 GiB. These are broad lifecycle safety limits, not a device benchmark; routine functional releases skip this opt-in gate.
- [ ] The automated Finder-style opening test passes: a file opened at launch shows before directory indexing completes, and `←` / `→` moves between its natural-order siblings. The router unit test separately covers buffered pre-launch URLs, duplicate filtering, unsupported URLs, and a new open event while the app is already running.
- [ ] English, Simplified Chinese, and Japanese have been checked in Light and Dark appearance, including every visible toolbar label.
- [ ] Open **LumaView → Settings…** (`⌘,`) and confirm the window is not blank: it must contain the appearance picker, language picker, installed-version text, and **Check for Updates…** button. This is a manual check because macOS exposes the app-level Settings command unreliably to XCTest across host versions.
- [ ] Folder scan, previous/next, zoom, fit, rotation, print, Finder reveal, drag-and-drop, and unsupported-file feedback have been checked manually. For print, use a non-sensitive image, open `⌘P`, verify the standard macOS panel, then cancel or save to a disposable PDF. For drag-and-drop, use a real Finder drag rather than a synthetic provider.
- [ ] Click the **Image Information** toolbar button for a photo with EXIF and for a PNG without EXIF. Confirm the compact inspector shows file facts in both cases, only shows camera rows when they exist, and does not change the displayed image.
- [ ] Rotate a non-square image through 0° / 90° / 180° / 270° using both toolbar and keyboard. Check actual pixel orientation and canvas edges, then rotate in full screen and exit. The automated regression uses four colored quadrants, not only accessible angle labels.
- [ ] Open an image with EXIF orientation, an explicitly selected hidden image, and a Sketch directory package. Confirm display dimensions, selection, and parent-folder navigation remain correct. Sketch process tests cover output limits, timeout, cancellation, launch failure, and nonzero exit.
- [ ] Open an explicitly readable image whose parent directory cannot be listed. Keep the image visible and show the directory error in both the status overlay and accessibility label. A later successful decode must not clear the warning. Restoring directory access and reopening must restore sibling navigation. Core tests exercise missing paths, non-directory paths, and permission denial/recovery.
- [ ] Rapidly browse while an information request is pending, then open the inspector again. It must show only the selected image. Settings/About must not route image commands to a background document; `⌘O` must work after closing the last document window.
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

## Visual test permissions

The rotation pixel test captures only the validation app's window as PNG and
checks four colored quadrants near both side edges. It requires Screen Recording
permission for the test runner. Without that permission, this individual test
reports **skipped**; toolbar, keyboard, and aspect-ratio tests still run. A skip
does not establish visual correctness: inspect all four orientations and canvas
edges in the running app before accepting a release. Do not substitute a test's
angle label for the displayed pixels or enable system permissions automatically.

Native UI tests need the document window to own keyboard focus. Activation alone
can leave another panel or application intercepting input on a multi-display
desktop. Open/print panel controls must be queried inside their panel; a global
`Cancel` query can match the Touch Bar instead. Full-screen tests use the native
window control rather than assuming a fixed system keyboard shortcut.

## LaunchServices coverage boundary

XCTest can launch the app with an explicit file URL, but it cannot reliably
make Finder/LaunchServices deliver a second system-level Open event to an
already-running app on every CI host. `ExternalDocumentOpenRouter` is therefore
unit-tested as the shared routing layer used by `application(_:open:)`,
`application(_:openFiles:)`, and `application(_:openFile:)`. Before release,
perform the manual Finder check: leave LumaView running, double-click a second
supported image in Finder, and confirm it opens in its own non-blank window
without changing the first window's image or creating a welcome window.
