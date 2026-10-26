import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import LumaView

final class LumaViewCoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LumaViewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        ImageMemoryCache.shared.clearAll()
        ImageMetadataCache.shared.clear()
    }

    @MainActor
    func testNativeFullScreenMenuKeepsItsTargetAndShortcutWhenRelocalized() throws {
        let menu = NSMenu()
        for name in ["App", "File", "Edit", "View"] {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: name)
            menu.addItem(item)
        }
        let viewMenu = try XCTUnwrap(menu.items.last?.submenu)
        let action = #selector(NSWindow.toggleFullScreen(_:))
        let installed = NSMenuItem(title: "Enter Full Screen", action: action, keyEquivalent: "f")
        installed.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(installed)
        MainMenuLocalization.apply(L10n(language: .english), to: menu)
        XCTAssertNil(installed.target, "The native responder chain must choose the current window")
        XCTAssertEqual(installed.keyEquivalent, "f")
        XCTAssertEqual(installed.keyEquivalentModifierMask, [.control, .command])

        MainMenuLocalization.apply(L10n(language: .japanese), to: menu)
        XCTAssertEqual(viewMenu.items.filter { $0.action == action }.count, 1)
        XCTAssertTrue(viewMenu.items.contains { $0 === installed })
        let l = L10n(language: .japanese)
        XCTAssertTrue([l.text("system.item.enterFullScreen"), l.text("system.item.exitFullScreen")].contains(installed.title))
    }

    func testFolderScanFiltersAndUsesNaturalOrdering() throws {
        try makeFile("photo-10.jpg")
        try makeFile("photo-2.png")
        try makeFile("photo-1.heic")
        try makeFile("notes.txt")

        let files = try ImageBrowserStore.scanFolder(directory).get()

        XCTAssertEqual(files.map(\.name), ["photo-1.heic", "photo-2.png", "photo-10.jpg"])
        XCTAssertFalse(ImageFile.canOpen(directory.appendingPathComponent("missing.jpg")))
    }

    @MainActor
    func testPDFArrowKeysReachTheOwningNativeWindowWithoutSwiftUIShortcuts() async throws {
        let pdf = directory.appendingPathComponent("keyboard.pdf")
        try makePDF(at: pdf)
        let store = ImageBrowserStore()
        store.open(file: pdf)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        let window = PDFKeyboardTestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.browser = store
        defer { window.close() }
        XCTAssertFalse(window.isVisible, "The test must not take over the desktop")

        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false, number: Int? = nil) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: number ?? window.windowNumber, context: nil,
                characters: code == 126 || code == 116 ? "\u{F700}" : "\u{F701}",
                charactersIgnoringModifiers: code == 126 || code == 116 ? "\u{F700}" : "\u{F701}",
                isARepeat: repeatKey, keyCode: code))
        }

        window.sendEvent(try key(125))
        XCTAssertEqual(store.pdfPageIndex, 1)
        window.sendEvent(try key(125, flags: [.numericPad, .function], repeatKey: true))
        XCTAssertEqual(store.pdfPageIndex, 2)
        XCTAssertTrue(window.handlePDFNavigation(try key(125)))
        XCTAssertEqual(store.pdfPageIndex, 2, "Do not scroll or move to another file at the final page")
        window.sendEvent(try key(116, flags: .function))
        XCTAssertEqual(store.pdfPageIndex, 1)
        window.sendEvent(try key(126))
        XCTAssertEqual(store.pdfPageIndex, 0)
        XCTAssertTrue(window.handlePDFNavigation(try key(126)))
        window.sendEvent(try key(121, flags: .function))
        XCTAssertEqual(store.pdfPageIndex, 1)
        for modifier: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            XCTAssertFalse(window.handlePDFNavigation(try key(125, flags: modifier)))
        }
        XCTAssertFalse(window.handlePDFNavigation(try key(124)), "Right arrow must remain file navigation")
        XCTAssertFalse(window.handlePDFNavigation(try key(125, number: window.windowNumber + 100)))
        window.receivesTestKeys = false
        XCTAssertFalse(window.handlePDFNavigation(try key(125)), "Background documents must not handle keys")
        window.receivesTestKeys = true
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        window.contentView = editor
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertFalse(window.handlePDFNavigation(try key(125)), "Leave text editing to its responder")
        XCTAssertEqual(store.pdfPageIndex, 1)
    }

    @MainActor
    func testDefaultApplicationChangesAreExplicitScopedAndVerified() async throws {
        let handler = TestDefaultApplicationHandler()
        let model = DefaultApplicationsModel(applicationURL: URL(fileURLWithPath: "/Applications/LumaView.app"), handler: handler)
        let jpeg = DefaultImageFormat.common[0], png = DefaultImageFormat.common[1]
        model.refresh()
        XCTAssertTrue(handler.requests.isEmpty)
        await model.apply()
        XCTAssertTrue(handler.requests.isEmpty)
        model.select(jpeg, enabled: true)
        model.select(png, enabled: true)
        model.select(png, enabled: false)
        await model.apply()
        XCTAssertEqual(handler.requests, [jpeg.id])
        XCTAssertTrue(model.isDefault(jpeg))
        XCTAssertFalse(model.isDefault(png))
        XCTAssertEqual(model.result?.appliedCount, 1)
        XCTAssertTrue(model.selected.isEmpty)
        model.selectAllImages()
        XCTAssertFalse(model.selected.contains(UTType.pdf.identifier), "Selecting images must not claim PDFs")
        XCTAssertFalse(model.selected.contains(jpeg.id), "Do not reapply unchanged defaults")
        model.clearSelection()
        XCTAssertTrue(model.selected.isEmpty)
    }

    @MainActor
    func testDefaultApplicationReportsFailureAndStopsWhenConsentIsCancelled() async throws {
        let formats = DefaultImageFormat.common
        let handler = TestDefaultApplicationHandler()
        let model = DefaultApplicationsModel(applicationURL: URL(fileURLWithPath: "/Applications/LumaView.app"), handler: handler)
        handler.errors[formats[0].id] = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        // A callback without an actual default change must not report success.
        handler.ignored.insert(formats[1].id)
        for format in formats.prefix(3) { model.select(format, enabled: true) }
        await model.apply()
        XCTAssertEqual(model.result?.appliedCount, 1)
        XCTAssertEqual(model.result?.failedFormats, [formats[0].name, formats[1].name])
        XCTAssertEqual(model.selected, Set([formats[0].id, formats[1].id]))
        handler.requests.removeAll()
        handler.errors[formats[0].id] = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        await model.apply()
        XCTAssertEqual(handler.requests, [formats[0].id], "Do not keep prompting after the user cancels")
        XCTAssertEqual(model.result?.cancelled, true)
        XCTAssertFalse(model.isApplying)
    }

    @MainActor
    func testDefaultApplicationRejectsTemporaryCopiesAndRefreshesExternalChanges() async throws {
        let handler = TestDefaultApplicationHandler()
        let format = DefaultImageFormat.common[0]
        for path in ["/Volumes/LumaView/LumaView.app", "/tmp/LumaView.app", "/Applications-copy/LumaView.app"] {
            let model = DefaultApplicationsModel(applicationURL: URL(fileURLWithPath: path), handler: handler)
            model.select(format, enabled: true)
            await model.apply()
            XCTAssertFalse(model.isInstalled)
            XCTAssertTrue(handler.requests.isEmpty)
        }
        let url = URL(fileURLWithPath: "/Applications/LumaView.app")
        let model = DefaultApplicationsModel(applicationURL: url, handler: handler)
        model.select(format, enabled: true)
        handler.applications[format.id] = url
        model.refresh()
        XCTAssertTrue(model.isDefault(format))
        XCTAssertTrue(model.selected.isEmpty)
        handler.applications[format.id] = URL(fileURLWithPath: "/System/Applications/Preview.app")
        model.refresh()
        XCTAssertFalse(model.isDefault(format))
        XCTAssertEqual(model.applicationName(for: format), (FileManager.default.displayName(atPath: "/System/Applications/Preview.app") as NSString).deletingPathExtension)
        XCTAssertTrue(DefaultApplicationsModel.isInstalledApplication(
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LumaView.app")))
    }

    @MainActor
    func testSettingsPanesRenderOffscreenInShortAndLongLocalizations() async throws {
        let suite = "LumaViewSettingsRender-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let handler = TestDefaultApplicationHandler()
        for format in DefaultImageFormat.common {
            handler.applications[format.id] = URL(fileURLWithPath: "/System/Applications/Preview.app")
        }
        for language in [AppLanguage.english, .chinese, .russian] {
            preferences.set(language.rawValue, forKey: "luma.language")
            for appearance in [AppAppearance.light, .dark] {
                preferences.set(appearance.rawValue, forKey: "luma.appearance")
                for tab in 0...1 {
                    let model = DefaultApplicationsModel(applicationURL: URL(fileURLWithPath: "/Applications/LumaView.app"), handler: handler)
                    model.refresh()
                    model.select(DefaultImageFormat.common[0], enabled: true)
                    model.select(DefaultImageFormat.common[1], enabled: true)
                    let size = CGSize(width: 560, height: tab == 0 ? 280 : 510)
                    let root = LumaSettingsView(updateChecker: UpdateChecker(defaults: preferences), defaultApplications: model, initialTab: tab)
                        .defaultAppStorage(preferences)
                    let host = NSHostingView(rootView: root)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
                    window.title = L10n(language: language).text("settings.title")
                    window.contentView = host
                    window.setContentSize(size)
                    // Capture the whole local window view, including its titlebar.
                    // This is an offscreen render; it never records the desktop.
                    try await Task.sleep(nanoseconds: 120_000_000)
                    host.layoutSubtreeIfNeeded()
                    XCTAssertFalse(window.isVisible)
                    XCTAssertNil(window.toolbar, "Text navigation must not create an empty icon toolbar")
                    let frameView = try XCTUnwrap(host.superview)
                    let bitmap = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
                    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = "settings-\(tab)-\(language.rawValue)-\(appearance.rawValue)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    window.close()
                }
            }
        }
        XCTAssertTrue(handler.requests.isEmpty, "Rendering settings must not change system defaults")
    }

    func testMissingFolderReportsFailureInsteadOfAnEmptyIndex() async throws {
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(try ImageBrowserStore.scanFolder(missing).get())
        XCTAssertThrowsError(try ImageBrowserStore.scanFolder(missing, isCancelled: { true }).get()) {
            XCTAssertTrue($0 is CancellationError)
        }

        let store = await MainActor.run { ImageBrowserStore() }
        await MainActor.run { store.open(folder: missing, selecting: nil) }
        try await waitForScan(store)
        await MainActor.run {
            XCTAssertTrue(store.files.isEmpty)
            XCTAssertNil(store.selectedURL)
            XCTAssertNotNil(store.folderScanErrorMessage)
            XCTAssertEqual(store.displayStatusMessage(L10n(language: .english)), store.folderScanErrorMessage)
            XCTAssertEqual(store.statusAccessibilityLabel(L10n(language: .english)), store.folderScanErrorMessage)
        }
    }

    func testFolderScanRejectsARegularFile() throws {
        let file = directory.appendingPathComponent("image.png")
        try makePNG(at: file, width: 96, height: 64)
        XCTAssertThrowsError(try ImageBrowserStore.scanFolder(file).get()) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(POSIXErrorCode.ENOTDIR.rawValue))
        }
    }

    func testUnreadableFolderReportsFailureInsteadOfAnEmptyIndex() throws {
        try makePNG(at: directory.appendingPathComponent("image.png"), width: 96, height: 64)
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        guard !FileManager.default.isReadableFile(atPath: directory.path) else {
            throw XCTSkip("The test process can bypass directory read permissions")
        }
        XCTAssertThrowsError(try ImageBrowserStore.scanFolder(directory).get())
    }

    func testUnreadableParentKeepsDirectImageAndWarningAfterDecode() async throws {
        let file = directory.appendingPathComponent("first.png")
        try makePNG(at: file, width: 96, height: 64)
        try makePNG(at: directory.appendingPathComponent("second.png"), width: 96, height: 64)
        // Search permission lets the explicitly chosen image remain readable,
        // while listing its siblings requires directory read permission.
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        guard !FileManager.default.isReadableFile(atPath: directory.path) else {
            throw XCTSkip("The test process can bypass directory read permissions")
        }
        XCTAssertNotNil(ImageDecoder.navigationPreview(for: file))
        let store = await MainActor.run { ImageBrowserStore() }
        await MainActor.run { store.open(file: file) }
        try await waitForScan(store)

        try await MainActor.run {
            let warning = try XCTUnwrap(store.folderScanErrorMessage)
            XCTAssertEqual(store.selectedURL, file.standardizedFileURL.resolvingSymlinksInPath())
            XCTAssertEqual(store.files.count, 1)
            XCTAssertFalse(store.isScanning)
            store.reportImageLoadResult(isAvailable: true)
            XCTAssertEqual(store.displayStatusMessage(L10n(language: .english)), warning)
            XCTAssertTrue(store.statusAccessibilityLabel(L10n(language: .english)).contains(warning))
            XCTAssertTrue(store.statusAccessibilityLabel(L10n(language: .english)).contains(file.lastPathComponent))

            store.status = .preparingPrint
            store.reportImageLoadResult(isAvailable: false)
            store.reportImageLoadResult(isAvailable: true)
            XCTAssertEqual(store.displayStatusMessage(L10n(language: .english)), L10n(language: .english).text("status.preparingPrint"))
            store.status = nil
            XCTAssertEqual(store.displayStatusMessage(L10n(language: .english)), warning)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        await MainActor.run { store.open(file: file) }
        try await waitForScan(store)
        await MainActor.run {
            XCTAssertEqual(store.files.count, 2)
            XCTAssertNil(store.folderScanErrorMessage)
            XCTAssertNil(store.displayStatusMessage(L10n(language: .english)))
        }
    }

    @MainActor
    func testExternalDocumentRouterBuffersLaunchEventsAndDeliversLaterFinderEvents() throws {
        let first = directory.appendingPathComponent("first.png")
        let second = directory.appendingPathComponent("second.png")
        try makePNG(at: first, width: 1, height: 1)
        try makePNG(at: second, width: 1, height: 1)
        let unsupported = directory.appendingPathComponent("unsupported.txt")
        try Data("not an image".utf8).write(to: unsupported)

        final class DeliveryRecorder {
            var batches: [[URL]] = []
        }
        let recorder = DeliveryRecorder()
        let router = ExternalDocumentOpenRouter { recorder.batches.append($0) }

        // `application(_:open:)` may arrive before didFinishLaunching.  The
        // same canonical document sent twice must still create just one window.
        XCTAssertTrue(router.receive([first, unsupported, first]))
        XCTAssertFalse(router.receive([unsupported]))
        XCTAssertTrue(router.finishLaunching(alsoOpening: [second]).count == 2)
        XCTAssertEqual(recorder.batches.count, 1)
        XCTAssertEqual(recorder.batches[0], [
            first.standardizedFileURL.resolvingSymlinksInPath(),
            second.standardizedFileURL.resolvingSymlinksInPath()
        ])

        // Once running, Finder's classic `openFile` / `openFiles` callbacks
        // route directly to the registry; they must not recreate a welcome
        // window or wait for another launch phase.
        XCTAssertTrue(router.receive([first]))
        XCTAssertEqual(recorder.batches.count, 2)
        XCTAssertEqual(recorder.batches[1], [first.standardizedFileURL.resolvingSymlinksInPath()])
        XCTAssertTrue(router.hasAcceptedDocument)
        XCTAssertTrue(router.hasFinishedLaunching)
    }

    func testRenderRequestAndQueuesHaveExplicitLimits() {
        XCTAssertEqual(ImageRenderRequest(url: nil, maxPixelSize: 1).maxPixelSize, 1_024)
        XCTAssertEqual(ImageRenderRequest(url: nil, maxPixelSize: 99_999).maxPixelSize, 5_120)
        XCTAssertEqual(ImageDecodeQueue.metadata.maxConcurrentOperationCount, 2)
        XCTAssertEqual(ImageDecodeQueue.navigationPrefetches.maxConcurrentOperationCount, 1)
        XCTAssertEqual(ImageDecodeQueue.renders.maxConcurrentOperationCount, 2)
        XCTAssertEqual(ImageDecodeQueue.prints.maxConcurrentOperationCount, 1)
        XCTAssertEqual(ImageDecoder.maximumFallbackSourceBytes, 128 * 1024 * 1024)
        XCTAssertEqual(ImageDecoder.maximumFallbackSourcePixels, 48_000_000)
    }

    func testRotationToolbarUsesDistinctOutlineAssets() {
        XCTAssertEqual(LumaIconKind.rotateLeft.tablerAssetName, "TablerRotateCounterclockwise")
        XCTAssertEqual(LumaIconKind.rotateRight.tablerAssetName, "TablerRotateClockwise")
        XCTAssertNotEqual(LumaIconKind.rotateLeft.tablerAssetName, LumaIconKind.rotateRight.tablerAssetName)
        XCTAssertEqual(LumaIconKind.information.tablerAssetName, "TablerInfoCircle")
    }

    func testNewDocumentWindowUsesImageAspectRatioWithinVisibleBounds() throws {
        let maximum = CGSize(width: 1_200, height: 760)
        let landscape = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 6_000, height: 4_000),
            maximumContentSize: maximum
        ))
        let portrait = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 3_000, height: 6_000),
            maximumContentSize: maximum
        ))
        let small = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 320, height: 160),
            maximumContentSize: maximum
        ))

        XCTAssertEqual(landscape.width / landscape.height, 1.5, accuracy: 0.002)
        XCTAssertLessThanOrEqual(landscape.width, maximum.width)
        XCTAssertLessThanOrEqual(landscape.height, maximum.height)
        XCTAssertEqual(portrait.width / portrait.height, 0.5, accuracy: 0.002)
        XCTAssertLessThanOrEqual(portrait.width, maximum.width)
        XCTAssertLessThanOrEqual(portrait.height, maximum.height)

        // Previous/Next uses this same sizing policy.  Changing from a
        // landscape to a portrait must therefore reflow the document canvas
        // rather than leaving the portrait letterboxed in the former window.
        let browsedLandscape = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 1_600, height: 900),
            maximumContentSize: maximum
        ))
        let browsedPortrait = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 900, height: 1_600),
            maximumContentSize: maximum
        ))
        XCTAssertEqual(browsedLandscape.width / browsedLandscape.height, 16.0 / 9.0, accuracy: 0.002)
        XCTAssertEqual(browsedPortrait.width / browsedPortrait.height, 9.0 / 16.0, accuracy: 0.002)
        XCTAssertLessThan(browsedPortrait.width, browsedLandscape.width)
        XCTAssertGreaterThan(browsedPortrait.height, browsedLandscape.height)
        XCTAssertEqual(small.width, 512, accuracy: 0.1)
        XCTAssertEqual(small.height, 256, accuracy: 0.1)

        let raisedWithoutDistortion = try XCTUnwrap(ImageWindowSizing.aspectPreservingContentSize(
            preferred: small,
            minimum: CGSize(width: 560, height: 335),
            maximum: maximum
        ))
        XCTAssertEqual(raisedWithoutDistortion.width / raisedWithoutDistortion.height, 2, accuracy: 0.002)
        XCTAssertGreaterThanOrEqual(raisedWithoutDistortion.height, 335)

        // A tall document that cannot meet a landscape minimum stays within the
        // available screen and retains its image aspect ratio.
        let extremePortrait = try XCTUnwrap(ImageWindowSizing.aspectPreservingContentSize(
            preferred: CGSize(width: 380, height: 760),
            minimum: CGSize(width: 560, height: 335),
            maximum: maximum
        ))
        XCTAssertEqual(extremePortrait.width / extremePortrait.height, 0.5, accuracy: 0.002)
        XCTAssertLessThanOrEqual(extremePortrait.height, maximum.height)

        let visibleFrame = NSRect(x: 100, y: 80, width: 1_440, height: 900)
        let centered = ImageWindowSizing.centeredFrame(
            for: CGSize(width: 1_200, height: 760),
            in: visibleFrame
        )
        XCTAssertEqual(centered.midX, visibleFrame.midX, accuracy: 0.01)
        XCTAssertEqual(centered.midY, visibleFrame.midY, accuracy: 0.01)
        XCTAssertTrue(visibleFrame.contains(centered))

        let clamped = ImageWindowSizing.centeredFrame(
            for: CGSize(width: 2_000, height: 1_200),
            in: visibleFrame
        )
        XCTAssertEqual(clamped, visibleFrame)

        // Browsing and quarter-turns resize around the current document
        // position rather than recentering it on every image change.
        let preservedPosition = ImageWindowSizing.frame(
            with: CGSize(width: 900, height: 700),
            centeredAt: CGPoint(x: 1_000, y: 450),
            constrainedTo: visibleFrame
        )
        XCTAssertEqual(preservedPosition.midX, 1_000, accuracy: 0.01)
        XCTAssertEqual(preservedPosition.midY, 450, accuracy: 0.01)
        XCTAssertTrue(visibleFrame.contains(preservedPosition))

        let positionNearEdge = ImageWindowSizing.frame(
            with: CGSize(width: 900, height: 700),
            centeredAt: CGPoint(x: 110, y: 90),
            constrainedTo: visibleFrame
        )
        XCTAssertTrue(visibleFrame.contains(positionNearEdge))
        XCTAssertEqual(positionNearEdge.minX, visibleFrame.minX, accuracy: 0.01)
        XCTAssertEqual(positionNearEdge.minY, visibleFrame.minY, accuracy: 0.01)
    }

    func testQuarterTurnsAndViewerGeometryShareExactDisplayBounds() throws {
        let landscape = CGSize(width: 1_600, height: 900)

        let quarterTurn = try XCTUnwrap(ViewerGeometry.displayedSize(for: landscape, rotation: .clockwise))
        XCTAssertEqual(quarterTurn.width, 900, accuracy: 0.001)
        XCTAssertEqual(quarterTurn.height, 1_600, accuracy: 0.001)

        let reverseQuarterTurn = try XCTUnwrap(ViewerGeometry.displayedSize(for: landscape, rotation: .counterClockwise))
        XCTAssertEqual(reverseQuarterTurn.width, 900, accuracy: 0.001)
        XCTAssertEqual(reverseQuarterTurn.height, 1_600, accuracy: 0.001)

        let halfTurn = try XCTUnwrap(ViewerGeometry.displayedSize(for: landscape, rotation: .upsideDown))
        XCTAssertEqual(halfTurn.width, 1_600, accuracy: 0.001)
        XCTAssertEqual(halfTurn.height, 900, accuracy: 0.001)

        var turn = QuarterTurn.zero
        for _ in 0..<4 { turn = turn.rotated(by: 90) }
        XCTAssertEqual(turn, .zero)
        XCTAssertEqual(QuarterTurn.zero.rotated(by: -90), .counterClockwise)
        XCTAssertEqual(QuarterTurn.upsideDown.degrees, 180)
        XCTAssertEqual(QuarterTurn.zero.rotated(by: 45), .zero)

        // Use the same displayed bounds to form the viewport a document window
        // will request. At fit zoom, the canvas then equals the rotated image
        // exactly—there is no secondary trigonometric or aspect-ratio path
        // that can introduce white rails at 90° or 270°.
        for source in [
            landscape,
            CGSize(width: 900, height: 1_600),
            CGSize(width: 1_200, height: 1_200)
        ] {
            for rotation in QuarterTurn.allCases {
                let displayed = try XCTUnwrap(ViewerGeometry.displayedSize(for: source, rotation: rotation))
                let layout = try XCTUnwrap(ViewerGeometry.canvasLayout(
                    imageSize: source,
                    viewportSize: displayed,
                    rotation: rotation,
                    zoom: 1
                ))
                XCTAssertEqual(layout.displayedImageSize.width, displayed.width, accuracy: 0.001)
                XCTAssertEqual(layout.displayedImageSize.height, displayed.height, accuracy: 0.001)
                XCTAssertEqual(layout.canvasSize, displayed)

                let magnified = try XCTUnwrap(ViewerGeometry.canvasLayout(
                    imageSize: source,
                    viewportSize: displayed,
                    rotation: rotation,
                    zoom: 2
                ))
                XCTAssertEqual(magnified.canvasSize.width, displayed.width * 2, accuracy: 0.001)
                XCTAssertEqual(magnified.canvasSize.height, displayed.height * 2, accuracy: 0.001)
            }
        }
    }

    @MainActor
    func testQuarterTurnPublisherDeliversTheAppliedCanvasOrientation() {
        let store = ImageBrowserStore()
        let source = CGSize(width: 1_600, height: 900)
        var renderedTurns: [QuarterTurn] = []
        var renderedCanvasSizes: [CGSize] = []
        var presentationRevisions: [UInt64] = []
        let observation = store.$quarterTurn
            .dropFirst()
            .sink { turn in
                renderedTurns.append(turn)
                guard let displayedSize = ViewerGeometry.displayedSize(for: source, rotation: turn),
                      let layout = ViewerGeometry.canvasLayout(
                          imageSize: source,
                          viewportSize: displayedSize,
                          rotation: turn,
                          zoom: 1
                      ) else { return }
                renderedCanvasSizes.append(layout.canvasSize)
            }
        let revisionObservation = store.$canvasPresentationRevision
            .dropFirst()
            .sink { presentationRevisions.append($0) }

        for _ in 0..<4 { store.rotate(by: 90) }

        // The window receives the quarter-turn publisher immediately. The
        // canvas receives this post-assignment revision only after the store
        // contains the same turn, so it cannot render a previous odd state.
        XCTAssertEqual(
            renderedTurns,
            [.clockwise, .upsideDown, .counterClockwise, .zero]
        )
        XCTAssertEqual(store.quarterTurn, .zero)
        XCTAssertEqual(presentationRevisions, [1, 2, 3, 4])
        XCTAssertEqual(
            renderedCanvasSizes,
            [
                CGSize(width: 900, height: 1_600),
                CGSize(width: 1_600, height: 900),
                CGSize(width: 900, height: 1_600),
                CGSize(width: 1_600, height: 900)
            ],
            "0° → 90° → 180° → 270° → 0° must update the canvas bounds on every turn"
        )
        withExtendedLifetime(observation) {}
        withExtendedLifetime(revisionObservation) {}
    }

    func testViewerGeometryRejectsInvalidImageAndViewportDimensions() {
        let valid = CGSize(width: 800, height: 600)
        let invalidSizes = [
            CGSize.zero,
            CGSize(width: -1, height: 100),
            CGSize(width: 100, height: -1),
            CGSize(width: CGFloat.infinity, height: 100),
            CGSize(width: 100, height: CGFloat.nan)
        ]

        for invalid in invalidSizes {
            XCTAssertNil(ViewerGeometry.displayedSize(for: invalid, rotation: .zero))
            XCTAssertNil(ViewerGeometry.canvasLayout(
                imageSize: invalid,
                viewportSize: valid,
                rotation: .clockwise,
                zoom: 1
            ))
            XCTAssertNil(ViewerGeometry.canvasLayout(
                imageSize: valid,
                viewportSize: invalid,
                rotation: .clockwise,
                zoom: 1
            ))
        }
    }

    func testNavigationPreviewCacheInvalidatesWhenFileChanges() throws {
        let url = directory.appendingPathComponent("replaceable.jpg")
        try Data([0x01]).write(to: url)
        let image = NSImage(size: CGSize(width: 12, height: 12))

        ImageMemoryCache.shared.storeNavigationPreview(image, for: url, pixelSize: 1_024)
        XCTAssertNotNil(ImageMemoryCache.shared.navigationPreview(for: url))

        try Data(repeating: 0x02, count: 64).write(to: url)
        XCTAssertNil(ImageMemoryCache.shared.navigationPreview(for: url))
    }

    func testNavigationPreviewCacheUsesLeastRecentlyUsedEviction() throws {
        let urls = (1...5).map { directory.appendingPathComponent("preview-\($0).jpg") }
        let image = NSImage(size: CGSize(width: 12, height: 12))
        for url in urls {
            try Data([0x01]).write(to: url)
        }

        for url in urls.prefix(4) {
            ImageMemoryCache.shared.storeNavigationPreview(image, for: url, pixelSize: 1_024)
        }
        XCTAssertNotNil(ImageMemoryCache.shared.navigationPreview(for: urls[0]))
        ImageMemoryCache.shared.storeNavigationPreview(image, for: urls[4], pixelSize: 1_024)

        XCTAssertNotNil(ImageMemoryCache.shared.navigationPreview(for: urls[0]))
        XCTAssertNil(ImageMemoryCache.shared.navigationPreview(for: urls[1]))
    }

    func testNavigationPathIndexRemainsBounded() throws {
        let image = NSImage(size: CGSize(width: 12, height: 12))
        for index in 0..<24 {
            let url = directory.appendingPathComponent("path-index-\(index).jpg")
            try Data([0x01]).write(to: url)
            ImageMemoryCache.shared.storeNavigationPreview(image, for: url, pixelSize: 1_024)
        }
        XCTAssertLessThanOrEqual(ImageMemoryCache.shared.navigationIndexCount, 16)
    }

    func testMetadataCacheRemainsBoundedAcrossManyFiles() throws {
        let seed = directory.appendingPathComponent("metadata-seed.png")
        try makePNG(at: seed, width: 1, height: 1)
        for index in 0..<1_040 {
            let url = directory.appendingPathComponent("metadata-\(index).png")
            try FileManager.default.linkItem(at: seed, to: url)
            XCTAssertEqual(ImageMetadataCache.shared.pixelSize(for: url), CGSize(width: 1, height: 1))
        }
        XCTAssertLessThanOrEqual(ImageMetadataCache.shared.entryCount, 1_024)
    }

    func testAdaptiveDecodeProducesNavigationPreview() throws {
        let url = directory.appendingPathComponent("sample.png")
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 96,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 96, height: 64)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)

        let navigationPreview = ImageDecoder.navigationPreview(for: url, maxPixelSize: 48)
        let rendered = ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024))
        let sourceSize = ImageDecoder.pixelSize(for: url)

        XCTAssertNotNil(navigationPreview)
        XCTAssertNotNil(rendered)
        XCTAssertEqual(sourceSize, CGSize(width: 96, height: 64))
        XCTAssertLessThanOrEqual(navigationPreview?.representations.first?.pixelsWide ?? .max, 96)
    }

    func testPDFPageBoundsDriveWindowGeometryAndBoundedPreview() throws {
        let url = directory.appendingPathComponent("landscape.pdf")
        var page = CGRect(x: 0, y: 0, width: 720, height: 300)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &page, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(page)
        context.endPDFPage()
        context.closePDF()

        // Vector representations have no inherent pixels. Their page bounds
        // must still provide an aspect ratio before the first window layout.
        let dimensions = try XCTUnwrap(ImageDecoder.pixelSize(for: url))
        XCTAssertEqual(dimensions, page.size)
        let preview = try XCTUnwrap(ImageDecoder.navigationPreview(for: url, maxPixelSize: 360))
        let previewSize = try XCTUnwrap(ViewerGeometry.decodedSize(for: preview))
        XCTAssertLessThanOrEqual(max(previewSize.width, previewSize.height), 360)
        XCTAssertEqual(previewSize.width / previewSize.height, 2.4, accuracy: 0.01)
        XCTAssertEqual(ViewerGeometry.displayedSize(for: dimensions, rotation: .clockwise),
                       CGSize(width: 300, height: 720))
    }

    func testPDFPagesRenderDistinctPixelsAndUsePageAwareCache() throws {
        let url = directory.appendingPathComponent("pages.pdf")
        try makePDF(at: url)
        let first = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))
        let secondRequest = ImageRenderRequest(url: url, maxPixelSize: 1_024, pageIndex: 1)
        let second = try XCTUnwrap(ImageDecoder.renderedImage(for: secondRequest))
        let last = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024, pageIndex: 2)))
        XCTAssertFalse(first === second)
        XCTAssertTrue(second === ImageDecoder.renderedImage(for: secondRequest))
        XCTAssertTrue(second === ImageDecoder.renderedImage(for: ImageRenderRequest(
            url: url, maxPixelSize: 1_024, selectionGeneration: 42, pageIndex: 1
        )), "Window identity must not duplicate the shared page cache")
        for (image, color, ratio) in [(first, NSColor.red, 1.5), (second, NSColor.green, 1 / 1.5), (last, NSColor.blue, 1.5)] {
            let size = try XCTUnwrap(ViewerGeometry.decodedSize(for: image))
            XCTAssertEqual(size.width / size.height, ratio, accuracy: 0.002)
            XCTAssertLessThanOrEqual(max(size.width, size.height), 1_024)
            try assertPDFColor(image, expected: color)
        }
        XCTAssertEqual(ImageDecoder.documentMetadata(for: url, pageIndex: 1)?.pageCount, 3)
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url, pageIndex: 1)?.pixelSize, CGSize(width: 400, height: 600))
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url)?.pixelSize, CGSize(width: 600, height: 400))
        let printPage = try XCTUnwrap(ImageDecoder.printBitmap(for: url, maxPixelSize: 2_048, pageIndex: 1))
        try assertPDFColor(NSImage(cgImage: printPage, size: .zero), expected: .green)
    }

    func testPDFCropOriginAndIntrinsicQuarterTurnsMatchRenderedPage() throws {
        // A nonzero crop origin and /Rotate must affect both the bitmap and geometry.
        for rotation in [0, 90, 180, 270] {
            let url = directory.appendingPathComponent("crop-\(rotation).pdf")
            try makeCroppedPDF(at: url, rotation: rotation)
            let expected = rotation % 180 == 0 ? CGSize(width: 200, height: 100) : CGSize(width: 100, height: 200)
            XCTAssertEqual(ImageDecoder.documentMetadata(for: url)?.pixelSize, expected)
            let image = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))
            let size = try XCTUnwrap(ViewerGeometry.decodedSize(for: image))
            XCTAssertEqual(size.width / size.height, expected.width / expected.height, accuracy: 0.001)
            // The red media box outside the green crop must never leak into any edge.
            try assertPDFColor(image, expected: .green)
        }
    }

    func testPDFIntrinsicRotationMovesTheActualCornerPixels() throws {
        for rotation in [0, 90, 180, 270] {
            let url = directory.appendingPathComponent("corner-\(rotation).pdf")
            try makeCroppedPDF(at: url, rotation: rotation, markCorner: true)
            let image = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
            // Clockwise positions: top-left, top-right, bottom-right, bottom-left.
            for (index, point) in [(0.25, 0.25), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)].enumerated() {
                let color = try XCTUnwrap(bitmap.colorAt(
                    x: Int(Double(bitmap.pixelsWide) * point.0),
                    y: Int(Double(bitmap.pixelsHigh) * point.1)
                )?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(color.blueComponent, index == rotation / 90 ? 1 : 0, accuracy: 0.03)
                XCTAssertEqual(color.greenComponent, index == rotation / 90 ? 0 : 1, accuracy: 0.03)
            }
        }
    }

    func testPrintedPDFRespectsAllUserRotations() throws {
        let url = directory.appendingPathComponent("print-corners.pdf")
        try makeCroppedPDF(at: url, rotation: 0, markCorner: true)
        for degrees in [0, 90, 180, 270] {
            let turn = QuarterTurn.zero.rotated(by: Double(degrees))
            let cg = try XCTUnwrap(ImageDecoder.printBitmap(for: url, maxPixelSize: 400, rotation: turn))
            XCTAssertEqual(cg.width > cg.height, degrees % 180 == 0)
            let bitmap = NSBitmapImageRep(cgImage: cg)
            for (index, point) in [(0.25, 0.25), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)].enumerated() {
                let color = try XCTUnwrap(bitmap.colorAt(x: Int(Double(cg.width) * point.0), y: Int(Double(cg.height) * point.1))?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(color.blueComponent, index == degrees / 90 ? 1 : 0, accuracy: 0.03)
                XCTAssertEqual(color.greenComponent, index == degrees / 90 ? 0 : 1, accuracy: 0.03)
            }
            XCTAssertNil(ImageDecoder.rotatedPrintBitmap(cg, rotation: turn, isCancelled: { true }))
        }
    }

    @MainActor
    func testPreviewFailuresExplainCauseAndClearOnNavigation() throws {
        let locked = directory.appendingPathComponent("locked.pdf")
        try makePDF(at: locked, locked: true)
        XCTAssertEqual(ImageDecoder.previewFailure(for: locked), .passwordRequired)
        XCTAssertEqual(ImageDecoder.previewFailure(for: directory.appendingPathComponent("missing.png")), .unreadable)
        let broken = directory.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: broken)
        XCTAssertEqual(ImageDecoder.previewFailure(for: broken), .cannotDecode)
        let large = directory.appendingPathComponent("large.pdf")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(ImageDecoder.maximumFallbackSourceBytes + 1))
        try handle.close()
        XCTAssertEqual(ImageDecoder.previewFailure(for: large), .fileTooLarge)
        let browser = ImageBrowserStore()
        browser.reportImageLoadResult(isAvailable: false, failure: .passwordRequired)
        XCTAssertEqual(browser.previewFailure, .passwordRequired)
        browser.open(file: broken)
        XCTAssertNil(browser.previewFailure)
        browser.reportImageLoadResult(isAvailable: true)
        XCTAssertFalse(browser.imageLoadFailed)
        browser.suspendCanvasRendering()
    }

    @MainActor
    func testPDFStatusFadesWithoutCoveringPageAndCanBePinned() async throws {
        try XCTSkipIf(NSWorkspace.shared.isVoiceOverEnabled, "VoiceOver intentionally keeps controls visible")
        let url = directory.appendingPathComponent("hud.pdf")
        try makePDF(at: url)
        let browser = ImageBrowserStore()
        browser.open(file: url)
        try await waitForScan(browser)
        let host = NSHostingView(rootView: ImageCanvasView(browser: browser, l: L10n(language: .english)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close(); browser.suspendCanvasRendering() }
        var uncoveredPageColor: NSColor?
        func sample(_ name: String) throws -> NSColor {
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            uncoveredPageColor = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)
            return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 45)?.usingColorSpace(.deviceRGB))
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        let initial = try sample("PDF-status-visible")
        try await Task.sleep(nanoseconds: 2_400_000_000)
        let hidden = try sample("PDF-status-hidden")
        XCTAssertGreaterThan(initial.greenComponent, hidden.greenComponent + 0.05)
        let page = try XCTUnwrap(uncoveredPageColor)
        XCTAssertEqual(hidden.redComponent, page.redComponent, accuracy: 0.01)
        XCTAssertEqual(hidden.greenComponent, page.greenComponent, accuracy: 0.01)
        XCTAssertEqual(hidden.blueComponent, page.blueComponent, accuracy: 0.01)
        browser.keepsStatusVisible = true
        try await Task.sleep(nanoseconds: 400_000_000)
        let pinned = try sample("PDF-status-pinned")
        XCTAssertGreaterThan(pinned.greenComponent, hidden.greenComponent + 0.05)
        XCTAssertFalse(window.isVisible, "This test must never capture or control the desktop")
    }

    @MainActor
    func testDropCollectsEveryFileInOrderWithoutDuplicates() async throws {
        let first = directory.appendingPathComponent("one.png")
        let second = directory.appendingPathComponent("two.png")
        let urls = await DocumentDrop.fileURLs(from: [
            NSItemProvider(item: first as NSURL, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(item: second.dataRepresentation as NSData, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(item: first as NSURL, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(object: "ignored" as NSString)
        ])
        XCTAssertEqual(urls, [first, second].map { $0.standardizedFileURL.resolvingSymlinksInPath() })
    }

    @MainActor
    func testDefaultApplicationsIdentifiesOtherCopyAndShowsVersionAndPath() throws {
        func app(_ name: String, id: String, version: String) throws -> URL {
            let url = directory.appendingPathComponent(name + ".app")
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleName": "LumaView", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
            return url
        }
        let current = try app("current", id: "test.luma", version: "2.0")
        let old = try app("old", id: "test.luma", version: "1.0")
        let handler = TestDefaultApplicationHandler()
        let format = DefaultImageFormat.common[0]
        handler.applications[format.id] = old
        let model = DefaultApplicationsModel(applicationURL: current, handler: handler)
        model.refresh()
        XCTAssertTrue(model.isAnotherCopy(format))
        XCTAssertFalse(model.isDefault(format))
        XCTAssertTrue(model.applicationDetails(for: format)?.contains(old.path) == true)
        XCTAssertTrue(model.applicationDetails(for: format)?.contains("1.0") == true)
        handler.applications[format.id] = current
        model.refresh()
        XCTAssertFalse(model.isAnotherCopy(format))
        XCTAssertTrue(model.isDefault(format))
    }

    func testPDFRejectsInvalidPagesCancellationAndLockedDocuments() throws {
        let url = directory.appendingPathComponent("pages.pdf")
        try makePDF(at: url)
        for page in [-1, 3, Int.max] {
            XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024, pageIndex: page)))
            XCTAssertNil(ImageDecoder.printBitmap(for: url, maxPixelSize: 2_048, pageIndex: page))
        }
        XCTAssertNil(ImageDecoder.documentMetadata(for: url, isCancelled: { true }))
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024), isCancelled: { true }))
        let broken = directory.appendingPathComponent("broken.pdf")
        try Data("not a PDF".utf8).write(to: broken)
        XCTAssertNil(ImageDecoder.documentMetadata(for: broken))
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: broken, maxPixelSize: 1_024)))
        let locked = directory.appendingPathComponent("locked.pdf")
        try makePDF(at: locked, locked: true)
        XCTAssertFalse(try XCTUnwrap(CGPDFDocument(locked as CFURL)).isUnlocked)
        XCTAssertNil(ImageDecoder.documentMetadata(for: locked))
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: locked, maxPixelSize: 1_024)))
    }

    func testPDFInformationUsesSelectedPageAndPointDimensions() throws {
        let url = directory.appendingPathComponent("pages.pdf")
        try makePDF(at: url)
        let info = ImageInformationReader.read(from: url, pageIndex: 1)
        XCTAssertEqual(info.fileFormat, "PDF")
        XCTAssertEqual(info.pdfPageNumber, 2)
        XCTAssertEqual(info.pdfPageCount, 3)
        XCTAssertEqual(info.pdfPageSize, CGSize(width: 400, height: 600))
        XCTAssertNil(info.dimensions, "PDF page points must not be labelled as image pixels")
        XCTAssertFalse(info.hasEXIF)
    }

    @MainActor
    func testPDFNavigationPreservesViewportAndKeepsWindowsIndependent() async throws {
        let url = directory.appendingPathComponent("01-pages.pdf")
        let next = directory.appendingPathComponent("02-next.png")
        try makePDF(at: url)
        try makePNG(at: next, width: 120, height: 80)
        let first = ImageBrowserStore(), second = ImageBrowserStore()
        first.open(url: url)
        second.open(url: url)
        try await waitForScan(first)
        try await waitForScan(second)
        try await waitForPageSize(first, CGSize(width: 600, height: 400))
        try await waitForPageSize(second, CGSize(width: 600, height: 400))
        XCTAssertEqual(first.pdfPageCount, 3)
        XCTAssertFalse(first.hasPreviousPage)
        first.previousPage()
        first.selectPDFPage(3)
        XCTAssertEqual(first.pdfPageIndex, 0)
        first.zoomIn()
        first.rotate(by: 90)
        let zoom = first.zoom
        let rotation = first.quarterTurn
        let generation = first.selectionGeneration
        first.nextPage()
        XCTAssertGreaterThan(first.selectionGeneration, generation)
        XCTAssertEqual(first.zoom, zoom)
        XCTAssertEqual(first.quarterTurn, rotation)
        try await waitForPageSize(first, CGSize(width: 400, height: 600))
        XCTAssertEqual(second.pdfPageIndex, 0)
        first.nextPage()
        first.nextPage()
        XCTAssertEqual(first.pdfPageIndex, 2)
        XCTAssertFalse(first.hasNextPage)
        // Burst page changes then file navigation must discard all stale page metadata.
        first.previousPage()
        first.previousPage()
        first.nextPage()
        first.next()
        try await waitForPageSize(first, CGSize(width: 120, height: 80))
        XCTAssertEqual(first.selectedURL, next)
        XCTAssertEqual(first.zoom, 1)
        XCTAssertEqual(first.quarterTurn, .zero)
        XCTAssertEqual(first.pdfPageIndex, 0)
        XCTAssertEqual(first.pdfPageCount, 0)
        XCTAssertFalse(first.hasMultiplePDFPages)
        first.previous()
        try await waitForPageSize(first, CGSize(width: 400, height: 600))
        XCTAssertEqual(first.pdfPageIndex, 1)
        XCTAssertEqual(first.pdfPageCount, 3)
        XCTAssertEqual(second.pdfPageIndex, 0)
    }

    @MainActor
    func testPDFResumesPage37AfterImmediateFileRoundTrip() async throws {
        let url = directory.appendingPathComponent("01-manual.pdf")
        let image = directory.appendingPathComponent("02-image.png")
        try makePDF(at: url, pageCount: 225)
        try makePNG(at: image, width: 120, height: 80)
        let store = ImageBrowserStore()
        store.open(file: url)
        try await waitForScan(store)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageCount, 225)
        store.selectPDFPage(36)
        store.zoomIn()
        store.rotate(by: 90)
        // No wait: a cancelled metadata read must not discard the bookmark.
        store.next()
        XCTAssertEqual(store.selectedURL, image)
        store.previous()
        XCTAssertEqual(store.selectedURL, url)
        XCTAssertEqual(store.pdfPageIndex, 36)
        XCTAssertEqual(store.zoom, 1)
        XCTAssertEqual(store.quarterTurn, .zero)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageCount, 225)
        let decoded = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(
            url: store.selectedURL, maxPixelSize: 1_024, pageIndex: store.pdfPageIndex
        )))
        try assertPDFColor(decoded, expected: .red)
        XCTAssertEqual(ImageInformationReader.read(from: url, pageIndex: store.pdfPageIndex).pdfPageNumber, 37)
    }

    @MainActor
    func testPDFReadingPositionsUseFullPathsAndStayWindowLocal() async throws {
        let a = directory.appendingPathComponent("manual.pdf")
        let otherFolder = directory.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        let b = otherFolder.appendingPathComponent("manual.pdf")
        try makePDF(at: a)
        try makePDF(at: b)
        let store = ImageBrowserStore()
        store.open(file: a)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        store.selectPDFPage(1)
        store.open(file: b)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageIndex, 0)
        store.selectPDFPage(2)
        store.open(file: a)
        try await waitForPageSize(store, CGSize(width: 400, height: 600))
        XCTAssertEqual(store.pdfPageIndex, 1)
        store.open(file: b)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageIndex, 2)
        let otherWindow = ImageBrowserStore()
        otherWindow.open(file: b)
        try await waitForPageSize(otherWindow, CGSize(width: 600, height: 400))
        XCTAssertEqual(otherWindow.pdfPageIndex, 0)
        // Intentionally returning to the first page replaces the old bookmark.
        store.selectPDFPage(0)
        store.open(file: a)
        store.open(file: b)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageIndex, 0)
    }

    @MainActor
    func testPDFReadingPositionClampsWhenPagesAreRemoved() async throws {
        let url = directory.appendingPathComponent("01-edited.pdf")
        let image = directory.appendingPathComponent("02-image.png")
        try makePDF(at: url)
        try makePNG(at: image, width: 120, height: 80)
        let store = ImageBrowserStore()
        store.open(file: url)
        try await waitForScan(store)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        store.selectPDFPage(2)
        store.next()
        try makeCroppedPDF(at: url, rotation: 90)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        store.previous()
        try await waitForPageSize(store, CGSize(width: 100, height: 200))
        XCTAssertEqual(store.pdfPageCount, 1)
        XCTAssertEqual(store.pdfPageIndex, 0)
        XCTAssertFalse(store.hasMultiplePDFPages)
        XCTAssertFalse(store.imageLoadFailed)
        store.next()
        try makePDF(at: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(4)], ofItemAtPath: url.path)
        store.previous()
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageIndex, 0, "Restoring pages must not revive the obsolete bookmark")
        XCTAssertEqual(store.pdfPageCount, 3)
    }

    func testPDFReadingHistoryIsBoundedAndKeepsRecentlyUsedPositions() {
        var history = PDFReadingHistory()
        let urls = (0...PDFReadingHistory.capacity).map {
            directory.appendingPathComponent("\($0).pdf")
        }
        for url in urls.dropLast() { history.remember(pageIndex: 36, for: url) }
        XCTAssertEqual(history.pageIndex(for: urls[0]), 36)
        history.remember(pageIndex: 9, for: urls.last!)
        XCTAssertEqual(history.pageIndex(for: urls[1]), 0, "Evict the least recently read document")
        XCTAssertEqual(history.pageIndex(for: urls[0]), 36)
        XCTAssertEqual(history.pageIndex(for: urls.last!), 9)
        history.remember(pageIndex: 0, for: urls[0])
        XCTAssertEqual(history.pageIndex(for: urls[0]), 0)
    }

    func testPDFReplacingFileInvalidatesEveryPageCache() throws {
        let url = directory.appendingPathComponent("updated.pdf")
        try makePDF(at: url)
        let request = ImageRenderRequest(url: url, maxPixelSize: 1_024, pageIndex: 1)
        let before = try XCTUnwrap(ImageDecoder.renderedImage(for: request))
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url, pageIndex: 1)?.pageCount, 3)
        try makeCroppedPDF(at: url, rotation: 90)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        XCTAssertNil(ImageDecoder.renderedImage(for: request), "The removed second page must not survive in cache")
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url)?.pageCount, 1)
        let after = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))
        XCTAssertFalse(before === after)
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url)?.pixelSize, CGSize(width: 100, height: 200))
    }

    private func makePDF(at url: URL, locked: Bool = false, pageCount: Int = 3) throws {
        var box = CGRect(x: 0, y: 0, width: 600, height: 400)
        let options: [CFString: Any] = locked ? [kCGPDFContextUserPassword: "fixture", kCGPDFContextOwnerPassword: "owner"] : [:]
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, options as CFDictionary))
        let pages = [(CGSize(width: 600, height: 400), NSColor.red), (CGSize(width: 400, height: 600), NSColor.green), (CGSize(width: 600, height: 400), NSColor.blue)]
        for index in 0..<pageCount {
            let (size, color) = pages[index % pages.count]
            var page = CGRect(origin: .zero, size: size)
            let boxData = Data(bytes: &page, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            context.setFillColor(color.cgColor)
            context.fill(page)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func makeCroppedPDF(at url: URL, rotation: Int, markCorner: Bool = false) throws {
        let content = "1 0 0 rg 0 0 300 200 re f\n0 1 0 rg 50 30 200 100 re f\n"
            + (markCorner ? "0 0 1 rg 50 80 100 50 re f\n" : "")
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /CropBox [50 30 250 130] /Rotate \(rotation) /Resources << >> /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream"
        ]
        var text = "%PDF-1.4\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        try Data(text.utf8).write(to: url)
    }

    private func assertPDFColor(_ image: NSImage, expected: NSColor, file: StaticString = #filePath, line: UInt = #line) throws {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let expected = try XCTUnwrap(expected.usingColorSpace(.deviceRGB))
        for point in [(1, 1), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2), (bitmap.pixelsWide / 2, bitmap.pixelsHigh / 2)] {
            let color = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, expected.redComponent, accuracy: 0.03, file: file, line: line)
            XCTAssertEqual(color.greenComponent, expected.greenComponent, accuracy: 0.03, file: file, line: line)
            XCTAssertEqual(color.blueComponent, expected.blueComponent, accuracy: 0.03, file: file, line: line)
        }
    }

    @MainActor
    private func waitForPageSize(_ store: ImageBrowserStore, _ size: CGSize) async throws {
        for _ in 0..<200 {
            if store.originalPixelSize == size { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected page size \(size), got \(String(describing: store.originalPixelSize))")
    }

    func testImageInformationReadsEXIFOnDemand() throws {
        let url = directory.appendingPathComponent("camera.jpg")
        try makeJPEGWithEXIF(at: url)

        let information = ImageInformationReader.read(from: url)

        XCTAssertEqual(information.fileName, "camera.jpg")
        XCTAssertEqual(information.fileFormat, "JPEG")
        XCTAssertEqual(information.dimensions, "320 × 240")
        XCTAssertGreaterThan(information.fileSize ?? 0, 0)
        XCTAssertEqual(information.capturedAt, "2026-10-17 12:34:56")
        XCTAssertEqual(information.camera, "Luma Labs LumaCam 1")
        XCTAssertEqual(information.lens, "Luma 50mm f/1.8")
        XCTAssertEqual(information.exposure, "1/125 s")
        XCTAssertEqual(information.aperture, "f/2.8")
        XCTAssertEqual(information.iso, "200")
        XCTAssertEqual(information.focalLength, "50 mm")
        XCTAssertTrue(information.hasEXIF)
    }

    func testEXIFOrientationAgreesWithTheDecodedImageDimensions() throws {
        // The window uses the header dimensions, while ImageIO applies EXIF
        // orientation when decoding. A disagreement introduces white rails or
        // crops the portrait photograph before the user rotates it even once.
        for orientation in 1...8 {
            let url = directory.appendingPathComponent("orientation-\(orientation).jpg")
            try makeJPEGWithEXIF(at: url, orientation: orientation)
            let expectedSize = orientation >= 5
                ? CGSize(width: 240, height: 320)
                : CGSize(width: 320, height: 240)
            let preview = try XCTUnwrap(ImageDecoder.navigationPreview(for: url, maxPixelSize: 1_024))
            let rendered = try XCTUnwrap(ImageDecoder.renderedImage(
                for: ImageRenderRequest(url: url, maxPixelSize: 1_024)
            ))

            XCTAssertEqual(ImageDecoder.pixelSize(for: url), expectedSize, "EXIF orientation \(orientation)")
            XCTAssertEqual(ViewerGeometry.decodedSize(for: preview), expectedSize, "EXIF orientation \(orientation)")
            XCTAssertEqual(ViewerGeometry.decodedSize(for: rendered), expectedSize, "EXIF orientation \(orientation)")
            XCTAssertEqual(ImageInformationReader.read(from: url).dimensions,
                           "\(Int(expectedSize.width)) × \(Int(expectedSize.height))")
        }
    }

    func testExtremeEXIFNumbersDoNotOverflowOrProduceAnInfiniteExposure() throws {
        for seconds in [Double.leastNonzeroMagnitude, 1e-30, Double.greatestFiniteMagnitude] {
            let exposure = try XCTUnwrap(ImageInformationReader.formattedExposure(seconds))
            XCTAssertTrue(exposure.hasSuffix(" s"))
            XCTAssertFalse(exposure.lowercased().contains("inf"))
            XCTAssertFalse(exposure.lowercased().contains("nan"))
        }
        for seconds in [0, -1, Double.infinity, Double.nan] {
            XCTAssertNil(ImageInformationReader.formattedExposure(seconds))
        }
        XCTAssertEqual(ImageInformationReader.formattedExposure(1.0 / 125), "1/125 s")
        XCTAssertEqual(ImageInformationReader.formattedExposure(0.8), "0.8 s")
        XCTAssertEqual(ImageInformationReader.formattedExposure(0.3), "0.3 s")
        XCTAssertEqual(ImageInformationReader.formattedExposure(1.0 / 3), "1/3 s")
        XCTAssertEqual(ImageInformationReader.formattedDecimal(50), "50")
        XCTAssertEqual(ImageInformationReader.formattedDecimal(2.8), "2.8")
    }

    @MainActor
    func testImageInformationInspectorFitsCompleteEXIFWithoutInternalScrolling() {
        let information = ImageInformation(
            fileName: "camera-with-complete-metadata.jpg",
            fileFormat: "JPEG",
            fileSize: 12_345_678,
            pixelWidth: 6_000,
            pixelHeight: 4_000,
            capturedAt: "2026-10-17 12:34:56",
            camera: "Luma Labs LumaCam One",
            lens: "Luma Prime 50mm f/1.8",
            exposure: "1/125 s",
            aperture: "f/2.8",
            iso: "200",
            focalLength: "50 mm"
        )
        let controller = NSHostingController(
            rootView: ImageInformationInspector(information: information, l: L10n(language: .english))
        )

        controller.view.layoutSubtreeIfNeeded()
        let fittedSize = controller.view.fittingSize

        // The inspector has no fixed short height or inner scroll view: a
        // complete file + EXIF record must determine its own popover height.
        XCTAssertGreaterThan(fittedSize.height, 260)
        XCTAssertLessThanOrEqual(fittedSize.width, ImageInformationInspector.maximumPreferredWidth)

        let compactController = NSHostingController(
            rootView: ImageInformationInspector(
                information: ImageInformation(
                    fileName: "image.png",
                    fileFormat: "PNG",
                    fileSize: 1_024,
                    pixelWidth: 32,
                    pixelHeight: 32,
                    capturedAt: nil,
                    camera: nil,
                    lens: nil,
                    exposure: nil,
                    aperture: nil,
                    iso: nil,
                    focalLength: nil
                ),
                l: L10n(language: .english)
            )
        )
        compactController.view.layoutSubtreeIfNeeded()
        XCTAssertLessThan(
            compactController.view.fittingSize.width,
            ImageInformationInspector.maximumPreferredWidth,
            "A compact record should not inherit the width of a full EXIF record."
        )
    }

    func testSketchDocumentUsesBundledPreviewForAllImageOperations() throws {
        let previewDirectory = directory.appendingPathComponent("previews")
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let previewURL = previewDirectory.appendingPathComponent("preview.png")
        try makePNG(at: previewURL, width: 144, height: 96)

        let documentURL = directory.appendingPathComponent("sample.sketch")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", documentURL.path, "previews"]
        zip.currentDirectoryURL = directory
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        XCTAssertTrue(ImageFile.canOpen(documentURL))
        XCTAssertEqual(ImageDecoder.pixelSize(for: documentURL), CGSize(width: 144, height: 96))
        XCTAssertNotNil(ImageDecoder.navigationPreview(for: documentURL, maxPixelSize: 48))
        XCTAssertNotNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: documentURL, maxPixelSize: 1_024)))
        XCTAssertNotNil(ImageDecoder.sourceImage(for: documentURL))

        let packageURL = directory.appendingPathComponent("package.sketch")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: previewDirectory, to: packageURL.appendingPathComponent("previews"))
        XCTAssertTrue(ImageFile.canOpen(packageURL))
        XCTAssertEqual(ImageDecoder.pixelSize(for: packageURL), CGSize(width: 144, height: 96))
    }

    func testSketchArchiveStopsAtPreviewByteLimit() throws {
        let previewDirectory = directory.appendingPathComponent("previews")
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let oversizedPreview = previewDirectory.appendingPathComponent("preview.png")
        try Data(repeating: 0x00, count: 64 * 1024 * 1024 + 1).write(to: oversizedPreview)

        let documentURL = directory.appendingPathComponent("oversized.sketch")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", documentURL.path, "previews"]
        zip.currentDirectoryURL = directory
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        XCTAssertNil(ImageDecoder.pixelSize(for: documentURL))
    }

    func testCancelledSketchDecodeReturnsWithoutStartingPreviewWork() throws {
        let documentURL = directory.appendingPathComponent("cancelled.sketch")
        try Data("not a sketch archive".utf8).write(to: documentURL)
        XCTAssertNil(ImageDecoder.pixelSize(for: documentURL, isCancelled: { true }))
        XCTAssertNil(ImageDecoder.renderedImage(
            for: ImageRenderRequest(url: documentURL, maxPixelSize: 1_024),
            isCancelled: { true }
        ))
    }

    func testSketchExtractionEnforcesOutputLimitAndHandlesLaunchFailure() {
        func run(_ command: String, limit: Int) -> Data? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let result = SketchPreviewExtractor.boundedOutput(
                from: process, byteLimit: limit, deadline: .now() + .seconds(2)
            )
            XCTAssertFalse(process.isRunning, "An extraction must not leave its subprocess running")
            return result
        }
        XCTAssertEqual(run("printf 12345678", limit: 8), Data("12345678".utf8))
        XCTAssertNil(run("printf 123456789", limit: 8))
        XCTAssertNil(run("printf partial; exit 1", limit: 64))

        let missing = Process()
        missing.executableURL = directory.appendingPathComponent("missing-unzip")
        XCTAssertNil(SketchPreviewExtractor.boundedOutput(
            from: missing, byteLimit: 64, deadline: .now() + .seconds(2)
        ))
    }

    func testSketchExtractionTimeoutAndCancellationTerminateAStalledProcess() {
        for cancel in [false, true] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            // No descendant process: SIGTERM is deliberately ignored to verify
            // the extractor's bounded escalation also reaps the child.
            process.arguments = ["-c", "trap '' TERM; printf partial; while :; do :; done"]
            let cancellationTime = DispatchTime.now() + .milliseconds(150)
            let result = SketchPreviewExtractor.boundedOutput(
                from: process,
                byteLimit: 64,
                deadline: .now() + .milliseconds(cancel ? 2_000 : 150),
                isCancelled: { cancel && DispatchTime.now() >= cancellationTime }
            )
            XCTAssertNil(result)
            XCTAssertFalse(process.isRunning)
        }
    }

    func testSketchPackagePreviewReplacementInvalidatesCachedDimensionsAndPixels() throws {
        let package = directory.appendingPathComponent("replaced.sketch", isDirectory: true)
        let previews = package.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        let preview = previews.appendingPathComponent("preview.png")
        try makePNG(at: preview, width: 144, height: 96)
        let packageDate = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: package.path)[.modificationDate] as? Date
        )
        let oldKey = ImageMemoryCache.cacheKey(for: package)
        XCTAssertEqual(ImageMetadataCache.shared.pixelSize(for: package), CGSize(width: 144, height: 96))
        XCTAssertNotNil(ImageDecoder.navigationPreview(for: package))

        try makePNG(at: preview, width: 300, height: 200)
        try FileManager.default.setAttributes([.modificationDate: packageDate], ofItemAtPath: package.path)
        XCTAssertNotEqual(ImageMemoryCache.cacheKey(for: package), oldKey)
        XCTAssertEqual(ImageMetadataCache.shared.pixelSize(for: package), CGSize(width: 300, height: 200))
        let replaced = try XCTUnwrap(ImageDecoder.navigationPreview(for: package))
        XCTAssertEqual(ViewerGeometry.decodedSize(for: replaced), CGSize(width: 300, height: 200))
    }

    func testSketchPackageOpensAsADocumentAndNavigatesItsParentFolder() async throws {
        let package = directory.appendingPathComponent("01-design.sketch", isDirectory: true)
        let previews = package.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        try makePNG(at: previews.appendingPathComponent("preview.png"), width: 144, height: 96)
        let next = directory.appendingPathComponent("02-photo.png")
        try makePNG(at: next, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(url: package) }
        let immediateURL = await MainActor.run { store.selectedURL }
        XCTAssertEqual(immediateURL, package.standardizedFileURL.resolvingSymlinksInPath())
        try await waitForScan(store)
        let state = await MainActor.run { (store.folderURL, store.files.map(\.name), store.selectedURL) }
        XCTAssertEqual(state.0, directory.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(state.1, ["01-design.sketch", "02-photo.png"])
        XCTAssertEqual(state.2, package.standardizedFileURL.resolvingSymlinksInPath())

        await MainActor.run { store.next() }
        let nextURL = await MainActor.run { store.selectedURL }
        XCTAssertEqual(nextURL, next.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testReplacingAnInFlightFolderOpenKeepsTheLatestDocument() async throws {
        let firstFolder = directory.appendingPathComponent("first", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let first = firstFolder.appendingPathComponent("first.png")
        let second = secondFolder.appendingPathComponent("second.png")
        try makePNG(at: first, width: 120, height: 80)
        try makePNG(at: second, width: 80, height: 120)
        let store = await MainActor.run { ImageBrowserStore() }

        // The first scan cannot publish its result until this actor turn yields.
        await MainActor.run {
            store.open(url: first)
            store.next()
            store.open(url: second)
        }
        try await waitForScan(store)
        let state = await MainActor.run { (store.folderURL, store.files.map(\.name), store.selectedURL, store.isScanning) }
        XCTAssertEqual(state.0, secondFolder.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(state.1, ["second.png"])
        XCTAssertEqual(state.2, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertFalse(state.3)
    }

    func testEveryUserSelectableLanguageHasAllRequiredTranslations() {
        XCTAssertEqual(AppLanguage.allCases.first, .english)
        for language in AppLanguage.allCases where language != .automatic {
            let l = L10n(language: language)
            for key in AppLanguage.requiredLocalizationKeys {
                XCTAssertNotEqual(l.text(key), key, "\(language.rawValue) is missing \(key)")
            }
        }
        XCTAssertEqual(L10n(language: .english).text("system.menu.file"), "File")
        XCTAssertEqual(L10n(language: .english).text("system.menu.help"), "Help")
        XCTAssertEqual(L10n(language: .chinese).text("system.menu.edit"), "编辑")
        XCTAssertEqual(L10n(language: .chinese).text("system.menu.window"), "窗口")
        XCTAssertEqual(L10n(language: .english).text("toolbar.print"), "Print image (⌘P)")
        XCTAssertEqual(L10n(language: .english).text("toolbar.info"), "Image information")
        XCTAssertEqual(L10n(language: .chinese).text("toolbar.next"), "下一张（→）")
        XCTAssertEqual(L10n(language: .chinese).text("toolbar.info"), "图片信息")
        XCTAssertEqual(L10n(language: .chinese).text("toolbar.rotateLeft"), "向左旋转")
        XCTAssertEqual(L10n(language: .japanese).text("system.menu.file"), "ファイル")
        XCTAssertEqual(L10n(language: .japanese).text("toolbar.next"), "次の画像（→）")
        XCTAssertEqual(L10n(language: .japanese).text("toolbar.rotateLeft"), "左に回転")
        XCTAssertEqual(L10n(language: .japanese).text("toolbar.info"), "画像情報")
        XCTAssertEqual(L10n(language: .french).text("system.menu.file"), "Fichier")
        XCTAssertEqual(L10n(language: .russian).text("system.menu.file"), "Файл")
        XCTAssertEqual(L10n(language: .spanish).text("system.menu.file"), "Archivo")
        XCTAssertEqual(L10n(language: .korean).text("system.menu.file"), "파일")
    }

    func testAutomaticLanguageRespectsSupportedPreferenceOrderAndRegions() {
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["de-DE", "fr-CA", "en"]), .french)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["ru_RU"]), .russian)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["es-MX"]), .spanish)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["ko-KR"]), .korean)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["zh-Hant-TW"]), .chinese)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["ja-JP", "en"]), .japanese)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["ar", "de"]), .english)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: []), .english)
    }

    @MainActor
    func testNativeMenuTitlesCanSwitchBetweenEverySupportedLanguage() {
        let menu = NSMenu()
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        menu.addItem(services)
        for language in AppLanguage.allCases where language != .automatic {
            let l = L10n(language: language)
            MainMenuLocalization.apply(l, to: menu)
            XCTAssertEqual(services.title, l.text("system.item.services"))
        }
        MainMenuLocalization.apply(L10n(language: .english), to: menu)
        XCTAssertEqual(services.title, "Services")
    }

    func testAppearanceModesHaveExplicitSwiftUIAndAppKitRepresentations() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertNil(AppAppearance.system.nsAppearance)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, NSAppearance.Name.aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, NSAppearance.Name.darkAqua)
    }

    @MainActor
    func testDropAndFinderOpenShareUnsupportedFormatFeedback() throws {
        let unsupported = directory.appendingPathComponent("not-an-image.jpg")
        try Data("not a decodable image".utf8).write(to: unsupported)
        let store = ImageBrowserStore()
        let localization = L10n(language: .english)

        // The extension is deliberately accepted by Finder/drop routing, but
        // ImageIO cannot decode it. Keep the selected document state so the
        // canvas shows its explicit unavailable state rather than welcome UI.
        store.open(url: unsupported)
        XCTAssertEqual(store.selectedURL, unsupported.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: unsupported, maxPixelSize: 1_024)))

        let rejected = directory.appendingPathComponent("not-an-image.txt")
        try Data("not an image".utf8).write(to: rejected)
        store.open(url: rejected)
        XCTAssertEqual(store.displayStatusMessage(localization), localization.text("error.unsupportedFormat"))
    }

    @MainActor
    func testPrintWithoutSelectionReportsLocalizedFeedbackInsteadOfPresentingAPanel() {
        let store = ImageBrowserStore()
        let localization = L10n(language: .english)
        store.printSelectedImage()
        XCTAssertEqual(store.displayStatusMessage(localization), localization.text("error.noPrintSelection"))
    }

    @MainActor
    func testExistingFeedbackUsesCurrentLanguageWithoutRepeatingOperations() async throws {
        let store = ImageBrowserStore()
        let english = L10n(language: .english)
        let french = L10n(language: .french)
        let unsupported = directory.appendingPathComponent("notes.txt")
        try Data("text".utf8).write(to: unsupported)
        store.open(file: unsupported)
        XCTAssertEqual(store.displayStatusMessage(english), "Unsupported image format.")
        XCTAssertEqual(store.displayStatusMessage(french), "Format d’image non pris en charge.")

        store.printSelectedImage()
        XCTAssertEqual(store.displayStatusMessage(french), french.text("error.noPrintSelection"))
        try FileManager.default.removeItem(at: unsupported)
        store.open(folder: directory, selecting: nil)
        try await waitForScan(store)
        XCTAssertEqual(store.displayStatusMessage(french), french.text("error.emptyFolder"))

        let file = directory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: file)
        store.open(file: file)
        try await waitForScan(store)
        store.reportImageLoadResult(isAvailable: false)
        for language in AppLanguage.allCases where language != .automatic {
            let l = L10n(language: language)
            XCTAssertEqual(store.displayStatusMessage(l), l.text("preview.cannotDecode"))
            XCTAssertTrue(store.statusAccessibilityLabel(l).contains(l.text("preview.cannotDecode")))
            XCTAssertEqual(store.selectedURL, file)
        }
        store.reportImageLoadResult(isAvailable: true)
        XCTAssertNil(store.displayStatusMessage(french))
    }

    func testPrintBitmapRemainsBoundedAndHonorsCancellation() throws {
        let file = directory.appendingPathComponent("print.png")
        try makePNG(at: file, width: 2_400, height: 1_200)
        let bitmap = try XCTUnwrap(ImageDecoder.printBitmap(for: file, maxPixelSize: 2_048))
        XCTAssertEqual(bitmap.width, 2_048)
        XCTAssertEqual(bitmap.height, 1_024)
        XCTAssertNil(ImageDecoder.printBitmap(for: file, maxPixelSize: 2_048, isCancelled: { true }))
    }

    func testReleaseUpdateOnlyAcceptsNewStableVersionsFromLumaViewRepository() throws {
        let installed = try XCTUnwrap(ReleaseVersion(tag: "1.2.1"))
        let release = GitHubRelease(
            tagName: "v1.3.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/ixiehao/LumaView/releases/tag/v1.3.0")),
            draft: false,
            prerelease: false
        )

        XCTAssertEqual(release.update(newerThan: installed, expectedRepositoryPath: "ixiehao/LumaView")?.version, "v1.3.0")
        XCTAssertNil(GitHubRelease(
            tagName: "v9.0.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/other/LumaView/releases/tag/v9.0.0")),
            draft: false,
            prerelease: false
        ).update(newerThan: installed, expectedRepositoryPath: "ixiehao/LumaView"))
        XCTAssertNil(GitHubRelease(
            tagName: "v1.4.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/ixiehao/LumaView/releases/tag/v1.4.0")),
            draft: false,
            prerelease: true
        ).update(newerThan: installed, expectedRepositoryPath: "ixiehao/LumaView"))
        XCTAssertNil(GitHubRelease(
            tagName: "1.2.1",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/ixiehao/LumaView/releases/tag/v1.2.1")),
            draft: false,
            prerelease: false
        ).update(newerThan: installed, expectedRepositoryPath: "ixiehao/LumaView"))
    }

    @MainActor
    func testUpdateIntervalPersistsAcrossCheckerInstances() async throws {
        let suiteName = "LumaViewTests.update-interval.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        UpdateCheckURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let referenceDate = Date(timeIntervalSinceReferenceDate: 123_456)
        let key = "last-checked"

        let first = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.2.1"),
            session: session,
            defaults: defaults,
            lastCheckedDefaultsKey: key,
            now: { referenceDate }
        )
        await first.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1)
        XCTAssertEqual(defaults.object(forKey: key) as? Date, referenceDate)

        let second = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.2.1"),
            session: session,
            defaults: defaults,
            lastCheckedDefaultsKey: key,
            now: { referenceDate.addingTimeInterval(60) }
        )
        await second.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1, "A relaunch inside the interval must not call GitHub again")

        let due = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.2.1"),
            session: session,
            defaults: defaults,
            lastCheckedDefaultsKey: key,
            now: { referenceDate.addingTimeInterval(12 * 60 * 60) }
        )
        await due.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 2)
    }

    @MainActor
    func testManualUpdateJoinsAutomaticCheckAndDismissesBanner() async throws {
        let suite = "LumaViewTests.updates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        UpdateCheckURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let checker = UpdateChecker(currentVersion: ReleaseVersion(tag: "1.0.0"), session: session, defaults: defaults)
        var notices: [UpdateCheckNotice] = []
        checker.noticeHandler = { notices.append($0) }
        let automatic = Task { await checker.checkForUpdate() }
        for _ in 0..<100 where !checker.isChecking { await Task.yield() }
        XCTAssertTrue(checker.isChecking)
        await checker.checkForUpdate(force: true, announceResult: true)
        await automatic.value
        XCTAssertFalse(checker.isChecking)
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1)
        XCTAssertEqual(notices, [.available])
        XCTAssertTrue(checker.showsUpdateBanner)
        checker.dismissBanner()
        XCTAssertFalse(checker.showsUpdateBanner)
        XCTAssertTrue(checker.hasUpdate, "Dismissal must not remove the settings/help download action")
        await checker.checkForUpdate(force: true)
        XCTAssertFalse(checker.showsUpdateBanner, "The same version must stay dismissed")
        let current = UpdateChecker(currentVersion: ReleaseVersion(tag: "1.2.1"), session: session, defaults: defaults)
        await current.checkForUpdate(force: true, announceResult: true)
        XCTAssertEqual(current.notice, .upToDate)
        let failure = UpdateChecker(session: session, releaseURL: URL(string: "https://example.invalid/fail")!, defaults: defaults)
        await failure.checkForUpdate(force: true, announceResult: true)
        XCTAssertEqual(failure.notice, .unavailable)
        XCTAssertFalse(failure.isChecking)
    }

    @MainActor
    func testUpdateCheckRecoversWhenTheSystemClockMovesBackwards() async throws {
        let suiteName = "LumaViewTests.update-clock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let referenceDate = Date(timeIntervalSinceReferenceDate: 123_456)
        let key = "last-checked"
        defaults.set(referenceDate.addingTimeInterval(24 * 60 * 60), forKey: key)

        UpdateCheckURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let checker = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.2.1"),
            session: session,
            defaults: defaults,
            lastCheckedDefaultsKey: key,
            now: { referenceDate }
        )

        await checker.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1,
                       "A future persisted timestamp must not suppress update checks")
        XCTAssertEqual(defaults.object(forKey: key) as? Date, referenceDate)
        await checker.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1,
                       "A successful check must restore the normal throttle")
    }

    @MainActor
    func testReopeningChangedFileRefreshesDimensionsAndRenderRequest() async throws {
        let url = directory.appendingPathComponent("edited.png")
        try makePNG(at: url, width: 240, height: 120)
        let browser = ImageBrowserStore()
        browser.open(url: url)
        for _ in 0..<200 {
            if browser.originalPixelSize != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(browser.originalPixelSize, CGSize(width: 240, height: 120))
        let firstRequest = ImageRenderRequest(
            url: browser.selectedURL, maxPixelSize: 1_024, selectionGeneration: browser.selectionGeneration
        )
        let firstImage = try XCTUnwrap(ImageDecoder.renderedImage(for: firstRequest))
        XCTAssertEqual(ViewerGeometry.decodedSize(for: firstImage), CGSize(width: 240, height: 120))

        try makePNG(at: url, width: 120, height: 240)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        browser.open(url: url)
        let reopenedRequest = ImageRenderRequest(
            url: browser.selectedURL, maxPixelSize: 1_024, selectionGeneration: browser.selectionGeneration
        )
        XCTAssertNotEqual(firstRequest, reopenedRequest, "A same-path reopen must restart the canvas task")
        for _ in 0..<200 {
            if browser.originalPixelSize != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(browser.originalPixelSize, CGSize(width: 120, height: 240))
        let reopenedImage = try XCTUnwrap(ImageDecoder.renderedImage(for: reopenedRequest))
        XCTAssertEqual(ViewerGeometry.decodedSize(for: reopenedImage), CGSize(width: 120, height: 240))
        // Selection identity must not fragment the shared file-fingerprint cache.
        let anotherWindowRequest = ImageRenderRequest(url: url, maxPixelSize: 1_024)
        XCTAssertTrue(reopenedImage === ImageDecoder.renderedImage(for: anotherWindowRequest))
    }

    func testStoreNavigationZoomAndRotationStayBounded() async throws {
        try makePNG(at: directory.appendingPathComponent("photo-1.png"), width: 96, height: 64)
        try makePNG(at: directory.appendingPathComponent("photo-2.png"), width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(folder: directory, selecting: nil) }
        try await waitForScan(store)
        let nextURL = try await MainActor.run { try XCTUnwrap(store.files.dropFirst().first?.url) }
        try await waitForNavigationPreview(at: nextURL)

        let result = await MainActor.run { () -> (Int, Int?, CGFloat, QuarterTurn) in
            for _ in 0..<10 { store.next() }
            for _ in 0..<10 { store.previous() }
            for _ in 0..<160 { store.zoomIn() }
            for _ in 0..<320 { store.zoomOut() }
            for _ in 0..<4 { store.rotate(by: 90) }
            return (store.files.count, store.selectedIndex, store.zoom, store.quarterTurn)
        }

        XCTAssertEqual(result.0, 2)
        XCTAssertEqual(result.1, 0)
        XCTAssertEqual(result.2, 0.15)
        XCTAssertEqual(result.3, .zero)

        let leftThenRight = await MainActor.run { () -> QuarterTurn in
            store.rotate(by: -90)
            XCTAssertEqual(store.quarterTurn, .counterClockwise)
            store.rotate(by: 90)
            return store.quarterTurn
        }
        XCTAssertEqual(leftThenRight, .zero)
    }

    @MainActor
    func testCanvasRenderingSuspensionKeepsDocumentStateButReleasesVisibleFrameIntent() {
        let browser = ImageBrowserStore()
        XCTAssertFalse(browser.isCanvasRenderingSuspended)
        browser.suspendCanvasRendering()
        XCTAssertTrue(browser.isCanvasRenderingSuspended)
        browser.resumeCanvasRendering()
        XCTAssertFalse(browser.isCanvasRenderingSuspended)
    }

    func testOpeningAFinderFileSelectsItAndKeepsFolderNavigation() async throws {
        try makePNG(at: directory.appendingPathComponent("photo-1.png"), width: 96, height: 64)
        let second = directory.appendingPathComponent("photo-2.png")
        try makePNG(at: second, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(url: second) }
        try await waitForScan(store)

        let state = await MainActor.run { (store.selectedFile?.url, store.files.count, store.hasNext) }
        XCTAssertEqual(state.0, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(state.1, 2)
        XCTAssertFalse(state.2)
    }

    func testFinderFileIsSelectedBeforeItsFolderIndexCompletes() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(url: second) }
        let immediateSelection = await MainActor.run { store.selectedURL }
        XCTAssertEqual(immediateSelection, second.standardizedFileURL.resolvingSymlinksInPath())

        try await waitForScan(store)
        let indexedState = await MainActor.run { (store.files.count, store.selectedURL, store.positionText) }
        XCTAssertEqual(indexedState.0, 2)
        XCTAssertEqual(indexedState.1, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(indexedState.2, "2 / 2")
    }

    func testExplicitlyOpenedHiddenImageSurvivesIndexingAndCanNavigate() async throws {
        let hidden = directory.appendingPathComponent(".selected.png")
        let visible = directory.appendingPathComponent("visible.png")
        try makePNG(at: hidden, width: 96, height: 64)
        try makePNG(at: visible, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(url: hidden) }
        try await waitForScan(store)
        let selected = await MainActor.run { store.selectedURL }
        XCTAssertEqual(selected, hidden.standardizedFileURL.resolvingSymlinksInPath())
        let names = await MainActor.run { store.files.map(\.name) }
        XCTAssertEqual(Set(names), Set([hidden.lastPathComponent, visible.lastPathComponent]))
        await MainActor.run {
            if store.hasNext { store.next() } else { store.previous() }
        }
        let navigated = await MainActor.run { store.selectedURL }
        XCTAssertEqual(navigated, visible.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testNavigationPressedDuringFolderScanIsAppliedAfterIndexing() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        // Execute both actions in one main-actor turn. The folder index cannot complete
        // until that turn yields, which is the real Finder/Open File edge case.
        await MainActor.run {
            store.open(url: first)
            store.next()
        }
        try await waitForScan(store)

        let selected = await MainActor.run { store.selectedURL }
        XCTAssertEqual(selected, second.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testOpeningAnotherWindowDoesNotClearExistingNavigationPreview() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        XCTAssertNotNil(ImageDecoder.navigationPreview(for: first))

        let otherWindow = await MainActor.run { ImageBrowserStore() }
        await MainActor.run { otherWindow.open(url: second) }
        XCTAssertNotNil(ImageMemoryCache.shared.navigationPreview(for: first))
    }

    func testSeparateWindowStoresKeepTheirOwnOpenedImage() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        let third = directory.appendingPathComponent("photo-3.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        try makePNG(at: third, width: 96, height: 64)
        let firstWindow = await MainActor.run { ImageBrowserStore() }
        let secondWindow = await MainActor.run { ImageBrowserStore() }

        await MainActor.run {
            firstWindow.open(url: first)
            secondWindow.open(url: second)
        }
        try await waitForScan(firstWindow)
        try await waitForScan(secondWindow)

        let selections = await MainActor.run { (firstWindow.selectedURL, secondWindow.selectedURL) }
        XCTAssertEqual(selections.0, first.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(selections.1, second.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testNavigatingOneWindowNeverChangesAnotherWindowSelection() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        let third = directory.appendingPathComponent("photo-3.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        try makePNG(at: third, width: 96, height: 64)
        let firstWindow = await MainActor.run { ImageBrowserStore() }
        let secondWindow = await MainActor.run { ImageBrowserStore() }

        await MainActor.run {
            firstWindow.open(url: first)
            secondWindow.open(url: third)
        }
        try await waitForScan(firstWindow)
        try await waitForScan(secondWindow)

        await MainActor.run { firstWindow.next() }
        let selections = await MainActor.run { (firstWindow.selectedURL, secondWindow.selectedURL) }
        XCTAssertEqual(selections.0, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(selections.1, third.standardizedFileURL.resolvingSymlinksInPath())
    }

    private func makeFile(_ name: String) throws {
        try Data("fixture".utf8).write(to: directory.appendingPathComponent(name))
    }

    private func makeJPEGWithEXIF(at url: URL, orientation: Int = 1) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 320,
            pixelsHigh: 240,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let image = try XCTUnwrap(bitmap.cgImage)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Luma Labs",
                kCGImagePropertyTIFFModel: "LumaCam 1"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:17 12:34:56",
                kCGImagePropertyExifLensModel: "Luma 50mm f/1.8",
                kCGImagePropertyExifExposureTime: 1.0 / 125.0,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifISOSpeedRatings: [200],
                kCGImagePropertyExifFocalLength: 50.0
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makePNG(at url: URL, width: Int, height: Int) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func waitForScan(_ store: ImageBrowserStore) async throws {
        for _ in 0..<200 {
            if await MainActor.run(body: { !store.isScanning }) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for the folder scan")
    }

    private func waitForNavigationPreview(at url: URL) async throws {
        for _ in 0..<200 {
            if ImageMemoryCache.shared.navigationPreview(for: url) != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for adjacent-image prefetch")
    }
}

private final class UpdateCheckURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func reset() {
        lock.lock()
        requests = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        Self.lock.unlock()

        let body = Data(#"{"tag_name":"v1.2.1","html_url":"https://github.com/ixiehao/LumaView/releases/tag/v1.2.1","draft":false,"prerelease":false}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: request.url?.path == "/fail" ? 503 : 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// These windows are never ordered on screen. Only the receiver under test
/// considers itself key; no macOS event is posted and system focus is unchanged.
@MainActor
private final class PDFKeyboardTestWindow: LumaDocumentWindow {
    var receivesTestKeys = true
    override var isKeyWindow: Bool { receivesTestKeys }
}

@MainActor
private final class TestDefaultApplicationHandler: DefaultApplicationHandling {
    var applications: [String: URL] = [:]
    var requests: [String] = []
    var errors: [String: Error] = [:]
    var ignored: Set<String> = []

    func applicationURL(for type: UTType) -> URL? { applications[type.identifier] }
    func setApplication(at url: URL, for type: UTType) async throws {
        requests.append(type.identifier)
        await Task.yield()
        if let error = errors[type.identifier] { throw error }
        if !ignored.contains(type.identifier) { applications[type.identifier] = url }
    }
}
