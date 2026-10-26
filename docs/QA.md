# LumaView release and QA gate

Run this checklist before creating a universal (`arm64` + `x86_64`) release DMG.

- [ ] For the Monterey compatibility build, verify `LSMinimumSystemVersion` and both Mach-O `minos` fields are `12.0`. On a real macOS 12 Mac, check launch, opening images/PDFs, page/file navigation, Information, settings, zoom/rotation and printing. Newer-host tests cannot establish old-OS runtime compatibility.

- [ ] `./Scripts/validate-project.sh` passes on the host Mac and verifies both universal Release slices. Validation uses an isolated bundle identifier and unregisters temporary builds from LaunchServices on exit; it does not replace the installed app.
- [ ] For a lifecycle or performance release, run the optional real-window 1 / 4 / 8 5K rendering gate with `LUMAVIEW_RUN_STRESS_TEST=1 ./Scripts/validate-project.sh`: first canvas appears within 25 seconds; all canvases appear within `30 + 12 × window count` seconds; every source has exactly one AppKit window, stable document accessibility scope, and an independent initial canvas/viewport state; target RSS stays below 1.2 GiB. These are broad lifecycle safety limits, not a device benchmark; routine functional releases skip this opt-in gate.
- [ ] The automated Finder-style opening test passes: a file opened at launch shows before directory indexing completes, and `←` / `→` moves between its natural-order siblings. The router unit test separately covers buffered pre-launch URLs, duplicate filtering, unsupported URLs, and a new open event while the app is already running.
- [ ] English, Simplified Chinese, French, Russian, Spanish, Japanese, and Korean have been checked in Light and Dark appearance, including menus, settings and toolbar labels. English is first in both language selectors; the stored language survives restart.
- [ ] With an existing error visible, switch languages and verify both the canvas and bottom status/VoiceOver text update. Also check empty-folder and print feedback; changing language must not require repeating the failed operation.
- [ ] Minimize an image window, then restore it from the Window menu. The suspended canvas must not report a decode failure, and the same image must return at its previous angle and zoom.
- [ ] Open **LumaView → Settings…** (`⌘,`) and confirm the window is not blank: it must contain the appearance picker, language picker, installed-version text, and **Check for Updates…** button. This is a manual check because macOS exposes the app-level Settings command unreliably to XCTest across host versions.
- [ ] On Monterey, switch between General and Default Applications; check light/dark appearance, long translations, window sizing and every format row. From a controlled test account, install the app into Applications, select only JPEG and PNG, apply and confirm Finder uses that installed copy. Verify unselected formats remain unchanged, system cancellation stops the batch, partial failures stay selected and external changes refresh. Do not run association-changing tests on the user's normal account without authorization; restore the controlled account's original choices afterwards. A mounted installer must show the installation hint and disable Apply.
- [ ] On Monterey, focus a multi-page PDF and use bare Up / Down and Fn-Up / Fn-Down, including holding a key and reaching each boundary. No image pan should occur; Left / Right must still switch files. Settings, text fields and modal sheets must retain their normal keyboard behavior and must not turn pages in a background document.
- [ ] Folder scan, previous/next, zoom, fit, rotation, print, Finder reveal, drag-and-drop, and unsupported-file feedback have been checked manually. For print, use a non-sensitive image, open `⌘P`, verify the standard macOS panel, then cancel or save to a disposable PDF. For drag-and-drop, use a real Finder drag rather than a synthetic provider.
- [ ] Click the **Image Information** toolbar button for a photo with EXIF and for a PNG without EXIF. Confirm the compact inspector shows file facts in both cases, only shows camera rows when they exist, and does not change the displayed image.
- [ ] Open a multi-page PDF with landscape and portrait pages. Use the bottom Tabler page controls, Up / Down and Page Up / Page Down; confirm first/last boundaries, page count, actual page pixels, zoom readout and page-shaped windows. Left / Right must still navigate files. Open Information from the narrow-window overflow menu, then turn a page: the old inspector must close and reopening must show the new page number and dimensions in points. Check current-page print output and PDF rotation/fit. Single-page PDFs must not show extra page controls.
- [ ] Read a later PDF page, switch to the next file, then return: the same page must reopen at fit zoom. Repeat with two PDFs, including identical filenames in different folders and two independent windows. If pages are removed externally, returning must clamp to the last remaining page rather than showing an invalid page.
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

Build the runner before granting Screen Recording permission, then use
`test-without-building` for the authorized binary. Rebuilding an ad-hoc-signed
runner can change its identity while System Settings still shows the old entry
as enabled. If preflight remains false, verify the current runner path and ask
the user to authorize refreshing that entry; do not edit the privacy database.

Window screenshots carry the display's ICC profile. Convert the entire bitmap
to sRGB before sampling channels, and use distinct, moderately saturated test
colors to avoid gamut clipping. Keep the pixel and aspect-ratio tolerances fixed.
The rotation test attaches only its cropped canvas images to the result bundle.

Use the ABC input source when running XCTest's literal `[` / `]` key events.
On the validated host, the same test binary failed to deliver Command-[ with
Simplified Chinese Pinyin selected and passed with ABC; the actual app shortcuts
worked with Pinyin during the separate native UI check. This is a test-input
limitation, not evidence that the app requires English input. Get permission
before changing the user's input source, and restore it after the run.

Native UI tests need the document window to own keyboard focus. Activation alone
can leave another panel or application intercepting input on a multi-display
desktop. Open/print panel controls must be queried inside their panel; a global
`Cancel` query can match the Touch Bar instead. Full-screen tests enter through
the native window control and exit through Control-Command-F. On the current
multi-display host, this synthesized exit and a native menu traversal both
failed while manual Control-Command-F worked. Keep that automation failure
explicit; manual verification does not turn a failed XCTest into a pass.
Measure the union of the AX window and its toolbar, since macOS can expose them
as separate frames. A display with a camera cutout can reserve its safe area
in full screen; use `NSScreen.safeAreaInsets` as well as the full screen bounds,
not an arbitrary height tolerance or the Dock-excluding `visibleFrame`.
Verify the rotated image's aspect ratio after exiting.

## LaunchServices coverage boundary

XCTest can launch the app with an explicit file URL, but it cannot reliably
make Finder/LaunchServices deliver a second system-level Open event to an
already-running app on every CI host. `ExternalDocumentOpenRouter` is therefore
unit-tested as the shared routing layer used by `application(_:open:)`,
`application(_:openFiles:)`, and `application(_:openFile:)`. Before release,
perform the manual Finder check: leave LumaView running, double-click a second
supported image in Finder, and confirm it opens in its own non-blank window
without changing the first window's image or creating a welcome window.
