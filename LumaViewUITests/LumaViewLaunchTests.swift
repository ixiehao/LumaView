import AppKit
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
        try makeToolbarFixture(width: 1_200, height: 1_000)
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

    func testNavigationLoadsTheNextImageAtFitZoom() throws {
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
    }

    func testToolbarRotationCyclesThroughEveryRightAngle() throws {
        let file = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let app = launchApp(opening: file)
        let canvas = app.descendants(matching: .any)["image.rendered.03-toolbar.png"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Exercise the visible toolbar action only. Keyboard/menu routing is
        // tested at the command layer; making this end-to-end test depend on
        // focus and the native overflow menu was the source of prior flakes.
        for expectedAngle in [90, 180, 270, 0] {
            let rotateRight = app.buttons
                .matching(NSPredicate(format: "label == %@", "Rotate right"))
                .firstMatch
            XCTAssertTrue(rotateRight.waitForExistence(timeout: 5))
            XCTAssertTrue(rotateRight.isEnabled)
            rotateRight.click()
            expect(canvas, accessibilityLabelContaining: "\(expectedAngle)°")
        }
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
        if let file {
            app.launchEnvironment["LUMAVIEW_UI_TEST_OPEN_FILE"] = file.path
        }
        app.launch()
        return app
    }

    private func makeToolbarFixture(width: Int, height: Int) throws {
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
        NSColor.systemIndigo.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
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
