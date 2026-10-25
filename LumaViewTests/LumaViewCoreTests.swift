import AppKit
import Combine
import ImageIO
import SwiftUI
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
    func testFullScreenMenuIsInstalledOnceAndPreservesNativeCommand() throws {
        let menu = NSMenu()
        for name in ["App", "File", "Edit", "View"] {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: name)
            menu.addItem(item)
        }
        let viewMenu = try XCTUnwrap(menu.items.last?.submenu)
        let action = #selector(NSWindow.toggleFullScreen(_:))
        MainMenuLocalization.apply(L10n(language: .english), to: menu)
        let installed = try XCTUnwrap(viewMenu.items.first { $0.action == action })
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
            XCTAssertEqual(store.displayStatusMessage, store.folderScanErrorMessage)
            XCTAssertEqual(store.statusAccessibilityLabel, store.folderScanErrorMessage)
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
            store.reportImageLoadResult(isAvailable: true, failureMessage: "No preview")
            XCTAssertEqual(store.displayStatusMessage, warning)
            XCTAssertTrue(store.statusAccessibilityLabel.contains(warning))
            XCTAssertTrue(store.statusAccessibilityLabel.contains(file.lastPathComponent))

            store.statusMessage = "Preparing to print"
            store.reportImageLoadResult(isAvailable: false, failureMessage: "No preview")
            store.reportImageLoadResult(isAvailable: true, failureMessage: "No preview")
            XCTAssertEqual(store.displayStatusMessage, "Preparing to print")
            store.statusMessage = nil
            XCTAssertEqual(store.displayStatusMessage, warning)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        await MainActor.run { store.open(file: file) }
        try await waitForScan(store)
        await MainActor.run {
            XCTAssertEqual(store.files.count, 2)
            XCTAssertNil(store.folderScanErrorMessage)
            XCTAssertNil(store.displayStatusMessage)
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

        await MainActor.run { store.open(url: package, l: L10n(language: .english)) }
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
            store.open(url: first, l: L10n(language: .english))
            store.next()
            store.open(url: second, l: L10n(language: .english))
        }
        try await waitForScan(store)
        let state = await MainActor.run { (store.folderURL, store.files.map(\.name), store.selectedURL, store.isScanning) }
        XCTAssertEqual(state.0, secondFolder.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(state.1, ["second.png"])
        XCTAssertEqual(state.2, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertFalse(state.3)
    }

    func testEveryUserSelectableLanguageHasAllRequiredTranslations() {
        for language in [AppLanguage.chinese, .english, .japanese] {
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
        store.open(url: unsupported, l: localization)
        XCTAssertEqual(store.selectedURL, unsupported.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: unsupported, maxPixelSize: 1_024)))

        let rejected = directory.appendingPathComponent("not-an-image.txt")
        try Data("not an image".utf8).write(to: rejected)
        store.open(url: rejected, l: localization)
        XCTAssertEqual(store.statusMessage, localization.text("error.unsupportedFormat"))
    }

    @MainActor
    func testPrintWithoutSelectionReportsLocalizedFeedbackInsteadOfPresentingAPanel() {
        let store = ImageBrowserStore()
        let localization = L10n(language: .english)
        store.printSelectedImage(localization)
        XCTAssertEqual(store.statusMessage, localization.text("error.noPrintSelection"))
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

        await MainActor.run { store.open(url: second, l: L10n(language: .english)) }
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

        await MainActor.run { store.open(url: second, l: L10n(language: .english)) }
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

        await MainActor.run { store.open(url: hidden, l: L10n(language: .english)) }
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
            store.open(url: first, l: L10n(language: .english))
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
        await MainActor.run { otherWindow.open(url: second, l: L10n(language: .english)) }
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
            firstWindow.open(url: first, l: L10n(language: .english))
            secondWindow.open(url: second, l: L10n(language: .english))
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
            firstWindow.open(url: first, l: L10n(language: .english))
            secondWindow.open(url: third, l: L10n(language: .english))
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
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
