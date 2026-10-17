import AppKit
import Darwin
import Foundation
import XCTest

final class LumaViewLaunchTests: XCTestCase {
    private var fixtureDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaViewUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        // A valid one-pixel PNG is enough to exercise the real Finder-style document
        // route and parent-folder navigation without involving a system open panel.
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL0dAAAAABJRU5ErkJggg=="))
        try png.write(to: fixtureDirectory.appendingPathComponent("01-first.png"), options: .atomic)
        try png.write(to: fixtureDirectory.appendingPathComponent("02-next.png"), options: .atomic)
        try makeToolbarFixture()
        try makePNG(at: fixtureDirectory.appendingPathComponent("90-exif-current.png"), width: 1_600, height: 900)
        try makePNG(at: fixtureDirectory.appendingPathComponent("91-exif-next.png"), width: 1_600, height: 900)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    func testLaunchExposesAccessiblePrimaryControls() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["Open file"].waitForExistence(timeout: 5))
    }

    func testFinderStyleOpenLoadsFirstImageAndArrowKeysNavigateFolder() throws {
        let app = launchApp(opening: fixtureDirectory.appendingPathComponent("01-first.png"))
        XCTAssertTrue(app.windows["01-first.png"].waitForExistence(timeout: 5))

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.windows["02-next.png"].waitForExistence(timeout: 5))

        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(app.windows["01-first.png"].waitForExistence(timeout: 5))
    }

    func testBrowsingMovesToTheNextImageAndKeepsFitMode() throws {
        let landscape = fixtureDirectory.appendingPathComponent("04-landscape.png")
        let portrait = fixtureDirectory.appendingPathComponent("05-portrait.png")
        try makePNG(at: landscape, width: 1_600, height: 900)
        try makePNG(at: portrait, width: 900, height: 1_600)

        let app = launchApp(opening: landscape)
        XCTAssertTrue(canvas(in: app, named: landscape.lastPathComponent).waitForExistence(timeout: 8))

        app.typeKey(.rightArrow, modifierFlags: [])
        let portraitCanvas = canvas(in: app, named: portrait.lastPathComponent)
        XCTAssertTrue(portraitCanvas.waitForExistence(timeout: 8))
        XCTAssertTrue(portraitCanvas.label.contains("0°"))
        // The window includes a unified toolbar above this element. Verify the
        // actual drawable canvas—not the outer window—switches to the next
        // image's aspect ratio. The accessible frame includes the 54pt toolbar,
        // so its ratio is necessarily more portrait than the source canvas.
        let outerWindowRatio = portraitCanvas.frame.width / portraitCanvas.frame.height
        XCTAssertLessThan(outerWindowRatio, 900.0 / 1_600.0)
        XCTAssertGreaterThan(outerWindowRatio, 0.48)
    }

    func testRotationToolbarExposesDistinctWorkingActions() throws {
        let file = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let app = launchApp(opening: file)
        let canvas = app.descendants(matching: .any)["image.rendered.03-toolbar.png"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let rotateLeft = app.buttons.matching(NSPredicate(format: "label == %@", "Rotate left")).firstMatch
        let rotateRight = app.buttons.matching(NSPredicate(format: "label == %@", "Rotate right")).firstMatch
        XCTAssertTrue(rotateLeft.waitForExistence(timeout: 5))
        XCTAssertTrue(rotateRight.waitForExistence(timeout: 5))
        XCTAssertTrue(rotateLeft.isEnabled)
        XCTAssertTrue(rotateRight.isEnabled)

        rotateRight.click()
        expect(canvas, accessibilityLabelContaining: "90°")
        // A correctly reshaped portrait window can move this toolbar item into
        // the standard overflow menu. Its Command-[ shortcut remains available
        // regardless of that native toolbar layout.
        app.activate()
        app.typeKey("[", modifierFlags: .command)
        expect(canvas, accessibilityLabelContaining: "0°")
    }

    func testRotationReshapesTheDocumentCanvasForTheNewOrientation() throws {
        let file = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let app = launchApp(opening: file)
        let renderedCanvas = canvas(in: app, named: file.lastPathComponent)
        XCTAssertTrue(renderedCanvas.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(renderedCanvas.frame.width / renderedCanvas.frame.height, 1)

        let rotateRight = app.buttons.matching(NSPredicate(format: "label == %@", "Rotate right")).firstMatch
        XCTAssertTrue(rotateRight.waitForExistence(timeout: 5))
        app.activate()
        rotateRight.click()

        let portraitFrame = NSPredicate { _, _ in
            let frame = renderedCanvas.frame
            return renderedCanvas.label.contains("90°") && frame.width < frame.height
        }
        let resized = expectation(for: portraitFrame, evaluatedWith: renderedCanvas)
        wait(for: [resized], timeout: 5)
    }

    func testImageInformationToolbarPresentsMetadataInspector() throws {
        let file = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let app = launchApp(opening: file)
        XCTAssertTrue(canvas(in: app, named: file.lastPathComponent).waitForExistence(timeout: 5))

        let information = app.buttons["Image information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        XCTAssertTrue(information.isEnabled)
        information.click()

        XCTAssertTrue(app.descendants(matching: .any)["image.informationInspector"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Image Information"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No EXIF metadata in this image."].waitForExistence(timeout: 5))
    }

    func testBrowsingClosesImageInformationInspector() throws {
        let first = fixtureDirectory.appendingPathComponent("90-exif-current.png")
        let next = fixtureDirectory.appendingPathComponent("91-exif-next.png")
        let app = launchApp(opening: first)
        XCTAssertTrue(canvas(in: app, named: first.lastPathComponent).waitForExistence(timeout: 5))

        let information = app.buttons["Image information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        app.activate()
        information.click()
        let inspector = app.descendants(matching: .any)["image.informationInspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(canvas(in: app, named: next.lastPathComponent).waitForExistence(timeout: 5))
        XCTAssertFalse(inspector.waitForExistence(timeout: 1))
    }

    func testEverySupportedLanguageHasCompleteToolbarLabelsWithoutPrintButton() throws {
        let image = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let configurations: [(language: String, appearance: String, previous: String, information: String, print: String)] = [
            ("english", "light", "Previous image", "Image information", "Print image"),
            ("chinese", "dark", "上一张", "图片信息", "打印图片"),
            ("japanese", "light", "前の画像", "画像情報", "画像をプリント")
        ]
        for configuration in configurations {
            let app = launchApp(
                opening: image,
                language: configuration.language,
                appearance: configuration.appearance
            )
            XCTAssertTrue(canvas(in: app, named: image.lastPathComponent).waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", configuration.previous)).firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", configuration.information)).firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", configuration.print)).firstMatch.exists)
            app.terminate()
        }
    }

    func testUndecodableAcceptedFileShowsExplicitPreviewFailureInsteadOfWelcomeUI() throws {
        let corrupted = fixtureDirectory.appendingPathComponent("broken.jpg")
        try Data("not a JPEG".utf8).write(to: corrupted)
        let app = launchApp(opening: corrupted)
        let failureCanvas = app.descendants(matching: .any)["canvas.unavailable.broken.jpg"]
        XCTAssertTrue(failureCanvas.waitForExistence(timeout: 8))
        XCTAssertTrue(failureCanvas.label.contains("Unable to preview this image."))
        XCTAssertFalse(
            app.descendants(matching: .any)["canvas.welcome"].exists,
            "A decode failure must not be presented as an empty welcome window"
        )
    }

    func testRealOneFourAndEightWindowFiveKRenderingGate() throws {
        let sources = try makeFiveKFixtureSources(count: 8)

        for count in [1, 4, 8] {
            let startedAt = Date()
            let app = launchApp(opening: Array(sources.prefix(count)), tiledForStress: true)
            let sourceNames = sources.prefix(count).map(\.lastPathComponent)
            let firstCanvas = app.descendants(matching: .any)["image.rendered.\(sourceNames[0])"]
            XCTAssertTrue(firstCanvas.waitForExistence(timeout: 25), "\(count)-window run did not render its first 5K canvas")
            let firstRenderElapsed = Date().timeIntervalSince(startedAt)

            // A broad, hardware-tolerant deadline catches serial queue stalls,
            // deadlocked window lifecycle work, and regressions that leave most
            // documents blank. It is intentionally not a microbenchmark: normal
            // CI and thermally constrained Apple Silicon still get a full decode
            // lane turn for every 5K document: 30s startup allowance + 12s/window.
            // This is a lifecycle safety gate, not a device benchmark.
            let allRenderDeadline = 30.0 + Double(count) * 12.0
            var documentScopes: [String: XCUIElement] = [:]
            for sourceName in sourceNames {
                let renderedCanvas = app.descendants(matching: .any)["image.rendered.\(sourceName)"]
                let remaining = max(1, allRenderDeadline - Date().timeIntervalSince(startedAt))
                XCTAssertTrue(
                    renderedCanvas.waitForExistence(timeout: remaining),
                    "\(count)-window run did not render \(sourceName) before its \(Int(allRenderDeadline))s gate"
                )
                let owners = app.windows.allElementsBoundByIndex.filter {
                    $0.descendants(matching: .any)["image.rendered.\(sourceName)"].exists
                }
                XCTAssertEqual(owners.count, 1, "\(sourceName) must be rendered by exactly one real AppKit window")
                XCTAssertEqual(owners.first?.label, sourceName, "A document window title must remain tied to its rendered source")
                let scopes = app.descendants(matching: .any)
                    .matching(identifier: "window.document.\(sourceName)")
                    .allElementsBoundByIndex
                XCTAssertEqual(scopes.count, 1, "\(sourceName) must retain one stable document scope through the stress lifecycle")
                documentScopes[sourceName] = try XCTUnwrap(scopes.first)
            }
            XCTAssertEqual(documentScopes.count, count, "Every rendered window must retain its own stable document scope")
            let allRenderElapsed = Date().timeIntervalSince(startedAt)
            XCTAssertLessThan(firstRenderElapsed, 25, "First 5K canvas exceeded the broad responsiveness gate")
            XCTAssertLessThan(
                allRenderElapsed,
                allRenderDeadline,
                "\(count) real 5K windows exceeded the broad all-render responsiveness gate"
            )

            XCTAssertGreaterThanOrEqual(app.windows.count, count, "Every requested document needs its own AppKit window")
            assertDistinctRenderedCanvases(app: app, sourceNames: sourceNames)
            let rssBytes = try residentMemoryBytes()
            XCTAssertLessThan(
                rssBytes,
                1_200 * 1_024 * 1_024,
                "\(count) visible 5K windows exceeded the controlled RSS safety ceiling"
            )

            let attachment = XCTAttachment(string: String(
                format: "%d real 5K windows: first %.2fs, all %.2fs (limit %.0fs), distinct canvas identity passed, RSS %.1f MiB",
                count,
                firstRenderElapsed,
                allRenderElapsed,
                allRenderDeadline,
                Double(rssBytes) / 1_048_576
            ))
            attachment.name = "LumaView window stress \(count)"
            add(attachment)
            app.terminate()
        }
    }

    /// Verify that every real document window still owns exactly the canvas it
    /// opened. `XCTest` cannot consistently direct a toolbar click at each
    /// background AppKit window after a z-order change, so actual toolbar
    /// rotation and Finder arrow navigation have focused end-to-end tests;
    /// `ImageBrowserStore` separately proves a next action cannot mutate a
    /// second window's selection. The release checklist retains a manual
    /// multi-window action check for that macOS automation boundary.
    private func assertDistinctRenderedCanvases(app: XCUIApplication, sourceNames: [String]) {
        for sourceName in sourceNames {
            let canvas = canvas(in: app, named: sourceName)
            XCTAssertTrue(canvas.exists, "Lost the rendered canvas for \(sourceName)")
            XCTAssertTrue(canvas.label.contains(sourceName), "A document window displayed a different image than it opened")
            XCTAssertTrue(canvas.label.contains("0°"), "A new document window must start with an independent viewport state")
        }
    }

    private func canvas(in window: XCUIElement, named sourceName: String) -> XCUIElement {
        window.descendants(matching: .any)["image.rendered.\(sourceName)"]
    }

    private func canvas(in app: XCUIApplication, named sourceName: String) -> XCUIElement {
        app.descendants(matching: .any)["image.rendered.\(sourceName)"]
    }

    private func launchApp(
        opening file: URL? = nil,
        language: String = "automatic",
        appearance: String? = nil
    ) -> XCUIApplication {
        launchApp(
            opening: file.map { [$0] } ?? [],
            tiledForStress: false,
            language: language,
            appearance: appearance
        )
    }

    private func launchApp(
        opening files: [URL],
        tiledForStress: Bool,
        language: String = "automatic",
        appearance: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-luma.language", language
        ]
        if let appearance {
            app.launchArguments += ["-luma.appearance", appearance]
        }
        app.launchEnvironment["LUMAVIEW_DISABLE_UPDATE_CHECK"] = "1"
        if files.count == 1, let file = files.first {
            app.launchEnvironment["LUMAVIEW_UI_TEST_OPEN_FILE"] = file.path
        } else if !files.isEmpty {
            app.launchEnvironment["LUMAVIEW_UI_TEST_OPEN_FILES"] = files.map(\.path).joined(separator: "\u{1F}")
        }
        if tiledForStress {
            app.launchEnvironment["LUMAVIEW_UI_TEST_TILE_WINDOWS"] = "1"
            app.launchEnvironment["LUMAVIEW_UI_TEST_RENDER_MAX_PIXELS"] = "5120"
        }
        app.launch()
        return app
    }

    private func makeFiveKFixtureSources(count: Int) throws -> [URL] {
        let source = fixtureDirectory.appendingPathComponent("01-5k.jpg")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 5_120,
            pixelsHigh: 2_880,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.06, green: 0.13, blue: 0.25, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 5_120, height: 2_880)).fill()
        NSColor(calibratedRed: 0.17, green: 0.67, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 480, y: 500, width: 2_400, height: 1_400), xRadius: 260, yRadius: 260).fill()
        NSColor(calibratedRed: 0.98, green: 0.32, blue: 0.58, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 3_400, y: 1_380, width: 620, height: 620)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78]))
            .write(to: source, options: .atomic)

        var sources = [source]
        for index in 2...count {
            let copy = fixtureDirectory.appendingPathComponent(String(format: "%02d-5k.jpg", index))
            // Keep physical directory entries rather than hard links. Finder
            // navigation is path-based, but some file-provider volumes coalesce
            // hard-linked identities during enumeration; the release gate must
            // exercise eight independently discoverable documents.
            try FileManager.default.copyItem(at: source, to: copy)
            sources.append(copy)
        }
        return sources
    }

    private func makeToolbarFixture() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1_600,
            pixelsHigh: 900,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemIndigo.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1_600, height: 900)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: fixtureDirectory.appendingPathComponent("03-toolbar.png"), options: .atomic)
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
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url, options: .atomic)
    }

    private func residentMemoryBytes() throws -> Int {
        let processIdentifier = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.lumaview.browser")
                .first?.processIdentifier
        )
        var taskInfo = proc_taskinfo()
        let readSize = proc_pidinfo(
            processIdentifier,
            PROC_PIDTASKINFO,
            0,
            &taskInfo,
            Int32(MemoryLayout<proc_taskinfo>.size)
        )
        XCTAssertEqual(readSize, Int32(MemoryLayout<proc_taskinfo>.size), "Could not read the rendered app's RSS")
        return Int(taskInfo.pti_resident_size)
    }

    private func expect(
        _ element: XCUIElement,
        accessibilityLabelContaining expectedValue: String,
        message: String = "Timed out waiting for an accessible visual state"
    ) {
        let expectation = expectation(
            for: NSPredicate(format: "label CONTAINS %@", expectedValue),
            evaluatedWith: element
        )
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(element.label.contains(expectedValue), message)
    }
}
