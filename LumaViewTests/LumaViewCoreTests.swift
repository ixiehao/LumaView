import AppKit
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
        XCTAssertEqual(L10n(language: .chinese).text("toolbar.next"), "下一张（→）")
        XCTAssertEqual(L10n(language: .chinese).text("toolbar.rotateLeft"), "向左旋转")
        XCTAssertEqual(L10n(language: .japanese).text("system.menu.file"), "ファイル")
        XCTAssertEqual(L10n(language: .japanese).text("toolbar.next"), "次の画像（→）")
        XCTAssertEqual(L10n(language: .japanese).text("toolbar.rotateLeft"), "左に回転")
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

        let first = await MainActor.run {
            UpdateChecker(
                currentVersion: ReleaseVersion(tag: "1.2.1"),
                session: session,
                defaults: defaults,
                lastCheckedDefaultsKey: key,
                now: { referenceDate }
            )
        }
        await first.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1)
        XCTAssertEqual(defaults.object(forKey: key) as? Date, referenceDate)

        let second = await MainActor.run {
            UpdateChecker(
                currentVersion: ReleaseVersion(tag: "1.2.1"),
                session: session,
                defaults: defaults,
                lastCheckedDefaultsKey: key,
                now: { referenceDate.addingTimeInterval(60) }
            )
        }
        await second.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1, "A relaunch inside the interval must not call GitHub again")

        let due = await MainActor.run {
            UpdateChecker(
                currentVersion: ReleaseVersion(tag: "1.2.1"),
                session: session,
                defaults: defaults,
                lastCheckedDefaultsKey: key,
                now: { referenceDate.addingTimeInterval(12 * 60 * 60) }
            )
        }
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

        let result = await MainActor.run { () -> (Int, Int?, CGFloat, Double) in
            for _ in 0..<10 { store.next() }
            for _ in 0..<10 { store.previous() }
            for _ in 0..<160 { store.zoomIn() }
            for _ in 0..<320 { store.zoomOut() }
            for _ in 0..<4 { store.rotate(by: 90) }
            return (store.files.count, store.selectedIndex, store.zoom, store.rotation)
        }

        XCTAssertEqual(result.0, 2)
        XCTAssertEqual(result.1, 0)
        XCTAssertEqual(result.2, 0.15)
        XCTAssertEqual(result.3, 0)
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
