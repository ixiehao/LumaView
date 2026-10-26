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

    func testOpenShortcutWorksAfterTheLastDocumentWindowCloses() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["Open file"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("o", modifierFlags: .command)

        // Limit the query to the native panel, excluding the similarly named
        // Touch Bar item that can survive a change of key window.
        let dialog = app.dialogs.containing(.button, identifier: "CancelButton").firstMatch
        let panelWindow = app.windows.containing(.button, identifier: "CancelButton").firstMatch
        let presented = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            dialog.exists || panelWindow.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [presented], timeout: 5), .completed,
                       "File → Open must remain available without a document window")
        let panel = dialog.exists ? dialog : panelWindow
        panel.buttons["CancelButton"].click()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
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
        let landscapeCanvas = canvas(in: app, named: landscape.lastPathComponent)
        XCTAssertTrue(landscapeCanvas.waitForExistence(timeout: 8))
        expectCanvasAspect(landscapeCanvas, ratio: 16.0 / 9.0)

        app.typeKey(.rightArrow, modifierFlags: [])
        let portraitCanvas = canvas(in: app, named: portrait.lastPathComponent)
        XCTAssertTrue(portraitCanvas.waitForExistence(timeout: 8))
        XCTAssertTrue(portraitCanvas.label.contains("0°"))
        expectCanvasAspect(portraitCanvas, ratio: 9.0 / 16.0)
    }

    func testPDFPageControlsShortcutsAndCurrentPageInformation() throws {
        let folder = fixtureDirectory.appendingPathComponent("pdf", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pdf = folder.appendingPathComponent("01-pages.pdf")
        let image = folder.appendingPathComponent("02-image.png")
        try makePDF(at: pdf, pageSizes: [CGSize(width: 600, height: 400), CGSize(width: 400, height: 600), CGSize(width: 600, height: 400)])
        try makePNG(at: image, width: 800, height: 600)
        let app = launchApp(opening: pdf)
        app.typeKey("i", modifierFlags: [.command, .control]) // Pin the HUD for this controls test.
        let rendered = canvas(in: app, named: pdf.lastPathComponent)
        let previous = app.buttons["pdf.previousPage"]
        let next = app.buttons["pdf.nextPage"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(previous.isEnabled)
        expect(rendered, accessibilityLabelContaining: "Page 1 of 3")
        expectCanvasAspect(rendered, ratio: 1.5)
        next.click()
        expect(rendered, accessibilityLabelContaining: "Page 2 of 3")
        expectCanvasAspect(rendered, ratio: 1 / 1.5)
        XCTAssertTrue(previous.isEnabled)

        // Bare arrows turn pages; Page Up/Down remain aliases. Left/Right
        // below still navigate files rather than pages.
        app.typeKey(.downArrow, modifierFlags: [])
        expect(rendered, accessibilityLabelContaining: "Page 3 of 3")
        XCTAssertFalse(next.isEnabled)
        app.typeKey(.upArrow, modifierFlags: [])
        expect(rendered, accessibilityLabelContaining: "Page 2 of 3")
        app.typeKey(.pageUp, modifierFlags: [])
        expect(rendered, accessibilityLabelContaining: "Page 1 of 3")
        app.typeKey(.pageDown, modifierFlags: [])
        expect(rendered, accessibilityLabelContaining: "Page 2 of 3")
        expectCanvasAspect(rendered, ratio: 1 / 1.5)
        // Portrait pages may move Information into AppKit's overflow menu.
        if app.buttons["Image information"].exists {
            app.buttons["Image information"].click()
        } else {
            let overflow = app.toolbars.popUpButtons.firstMatch
            XCTAssertTrue(overflow.exists)
            overflow.click()
            app.menuItems["Image information"].click()
        }
        let inspector = app.popovers.firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        expectInspector(inspector, toShow: "Page 2 of 3")
        expectInspector(inspector, toShow: "400 × 600 pt")
        app.typeKey(.pageDown, modifierFlags: [])
        expect(rendered, accessibilityLabelContaining: "Page 3 of 3")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: inspector
        )], timeout: 5), .completed)

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(canvas(in: app, named: image.lastPathComponent).waitForExistence(timeout: 5))
        XCTAssertFalse(next.exists)
        app.typeKey(.leftArrow, modifierFlags: [])
        expect(rendered, accessibilityLabelContaining: "Page 3 of 3")
        XCTAssertTrue(previous.isEnabled)
        XCTAssertFalse(next.isEnabled)
        expectCanvasAspect(rendered, ratio: 1.5)
        let status = app.descendants(matching: .any)["image.status"]
        let zoomReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (status.value as? String)?.hasSuffix("%") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomReady], timeout: 5), .completed)
        let fitZoom = try XCTUnwrap(Double((status.value as? String ?? "").replacingOccurrences(of: "%", with: "")))
        app.buttons["Zoom in"].click()
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = Double((status.value as? String ?? "").replacingOccurrences(of: "%", with: "")) ?? 0
            return value > fitZoom
        }, object: nil)], timeout: 5), .completed)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fit image")).firstMatch.click()
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
    }

    func testSinglePagePDFDoesNotAddPageNavigation() throws {
        let pdf = fixtureDirectory.appendingPathComponent("single.pdf")
        try makePDF(at: pdf, pageSizes: [CGSize(width: 600, height: 400)])
        let app = launchApp(opening: pdf)
        expectCanvasAspect(canvas(in: app, named: pdf.lastPathComponent), ratio: 1.5)
        XCTAssertFalse(app.buttons["pdf.nextPage"].exists)
        XCTAssertFalse(app.buttons["pdf.previousPage"].exists)
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["Print Current Page…"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func makePDF(at url: URL, pageSizes: [CGSize]) throws {
        var box = CGRect(origin: .zero, size: try XCTUnwrap(pageSizes.first))
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for (index, size) in pageSizes.enumerated() {
            var page = CGRect(origin: .zero, size: size)
            let data = Data(bytes: &page, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: data] as CFDictionary)
            context.setFillColor([NSColor.red, .green, .blue][index % 3].cgColor)
            context.fill(page)
            context.endPDFPage()
        }
        context.closePDF()
    }

    func testToolbarRotationCyclesThroughEveryRightAngle() throws {
        exerciseRotationSequence(verifyPixels: false)
    }

    func testRenderedRotationPixelsFillTheCanvasAtEveryRightAngle() throws {
        try XCTSkipUnless(
            CGPreflightScreenCaptureAccess(),
            "Screen Recording permission is required for pixel verification. Perform the documented visual rotation check when this test is skipped."
        )
        exerciseRotationSequence(verifyPixels: true)
    }

    private func exerciseRotationSequence(verifyPixels: Bool) {
        let file = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let app = launchApp(opening: file)
        let canvas = app.descendants(matching: .any)["image.rendered.03-toolbar.png"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Inspect actual pixels as well as the accessible angle. A label-only
        // assertion used to pass even when 90°/270° left the pixels unrotated.
        // Keep the swatches inside common display gamuts. Fully saturated sRGB
        // primaries can clip when a real monitor's ICC profile is applied.
        let red = NSColor(srgbRed: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        let green = NSColor(srgbRed: 0.2, green: 0.8, blue: 0.2, alpha: 1)
        let blue = NSColor(srgbRed: 0.2, green: 0.2, blue: 0.8, alpha: 1)
        let yellow = NSColor(srgbRed: 0.8, green: 0.8, blue: 0.2, alpha: 1)
        func verify(_ colors: [NSColor], ratio: CGFloat) {
            if verifyPixels {
                expectCanvasPixels(canvas, in: app, colors: colors, ratio: ratio)
            } else {
                expectCanvasAspect(canvas, ratio: ratio)
            }
        }
        verify([red, green, blue, yellow], ratio: 1.2)
        let turns: [(angle: Int, colors: [NSColor], ratio: CGFloat)] = [
            (90, [blue, red, yellow, green], 1 / 1.2),
            (180, [yellow, blue, green, red], 1.2),
            (270, [green, yellow, red, blue], 1 / 1.2),
            (0, [red, green, blue, yellow], 1.2)
        ]
        for turn in turns {
            let rotateRight = app.buttons
                .matching(NSPredicate(format: "label == %@", "Rotate right"))
                .firstMatch
            XCTAssertTrue(rotateRight.waitForExistence(timeout: 5))
            XCTAssertTrue(rotateRight.isEnabled)
            rotateRight.click()
            expect(canvas, accessibilityLabelContaining: "\(turn.angle)°")
            verify(turn.colors, ratio: turn.ratio)
        }

        // Give keyboard events a visible target and explicit focus; the app's
        // AX frame can be infinite on multi-display hosts. Use ABC (see QA.md).
        canvas.click()
        canvas.typeKey("[", modifierFlags: .command)
        expect(canvas, accessibilityLabelContaining: "270°")
        verify([green, yellow, red, blue], ratio: 1 / 1.2)
        canvas.typeKey("]", modifierFlags: .command)
        expect(canvas, accessibilityLabelContaining: "0°")
        verify([red, green, blue, yellow], ratio: 1.2)
    }

    func testImageInformationToolbarPresentsMetadataInspector() throws {
        let file = fixtureDirectory.appendingPathComponent("90-exif-current.png")
        let app = launchApp(opening: file)
        XCTAssertTrue(canvas(in: app, named: file.lastPathComponent).waitForExistence(timeout: 5))

        let information = app.buttons["Image information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        XCTAssertTrue(information.isEnabled)
        app.activate()
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
        let inspector = app.popovers.firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        expectInspector(inspector, toShow: first.lastPathComponent)

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(canvas(in: app, named: next.lastPathComponent).waitForExistence(timeout: 5))
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: inspector
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)

        information.click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        expectInspector(inspector, toShow: next.lastPathComponent, excluding: first.lastPathComponent)
    }

    func testExitingFullScreenRefitsTheImageRotatedWhileFullScreen() throws {
        let file = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let app = launchApp(opening: file)
        let rendered = canvas(in: app, named: file.lastPathComponent)
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        expectCanvasAspect(rendered, ratio: 1.2)

        let window = app.windows[file.lastPathComponent]
        let fullScreenButton = window.buttons[XCUIIdentifierFullScreenWindow]
        XCTAssertTrue(fullScreenButton.waitForExistence(timeout: 5))
        fullScreenButton.click()
        // In full screen, macOS 14 reports the toolbar outside the AX window
        // frame. Measure both instead of mistaking the missing 52 pt for a
        // failed transition. Hidden menus are not reliable state indicators.
        expectFullScreen(true, in: window)
        rendered.typeKey("]", modifierFlags: .command)
        expect(rendered, accessibilityLabelContaining: "90°")
        // Exercise the native menu shortcut without relying on a titlebar that
        // may stay auto-hidden in the CI virtual display.
        rendered.typeKey("f", modifierFlags: [.control, .command])
        expectFullScreen(false, in: window)
        expectCanvasAspect(rendered, ratio: 1 / 1.2)
    }

    private func expectInspector(_ inspector: XCUIElement, toShow fileName: String, excluding staleName: String? = nil) {
        // SwiftUI can propagate the VStack identifier to every text row. Scope
        // the query to the native popover, then match actual text/value instead
        // of treating that inherited identifier as a unique parent element.
        func contains(_ name: String) -> Bool {
            inspector.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@ OR value == %@", name, name
            )).firstMatch.exists
        }
        let current = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            contains(fileName) && (staleName.map { !contains($0) } ?? true)
        }, object: nil)
        let result = XCTWaiter.wait(for: [current], timeout: 5)
        if result != .completed {
            print("Metadata inspector hierarchy:\n\(inspector.debugDescription)")
        }
        XCTAssertEqual(result, .completed, "Inspector must show \(fileName), with no stale file name")
    }

    private func fullWindowFrame(_ window: XCUIElement) -> CGRect {
        let toolbar = window.toolbars.firstMatch
        return toolbar.exists ? window.frame.union(toolbar.frame) : window.frame
    }

    private func expectFullScreen(_ fullScreen: Bool, in window: XCUIElement) {
        // A notched display may reserve its camera safe area even in full
        // screen. Accept the actual screen bounds or its system-defined safe
        // bounds; never use visibleFrame, which also excludes the Dock.
        let screenSizes = NSScreen.screens.flatMap { screen -> [CGSize] in
            let size = screen.frame.size
            let insets = screen.safeAreaInsets
            return [size, CGSize(
                width: size.width - insets.left - insets.right,
                height: size.height - insets.top - insets.bottom
            )]
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let size = self.fullWindowFrame(window).size
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return false }
            let fillsScreen = screenSizes.contains {
                abs(size.width - $0.width) < 2 && abs(size.height - $0.height) < 2
            }
            return fillsScreen == fullScreen
        }, object: nil)
        let result = XCTWaiter.wait(for: [changed], timeout: 8)
        if result != .completed {
            print("Expected full screen: \(fullScreen); window and toolbar: \(fullWindowFrame(window)); screens: \(screenSizes)")
            print("Full-screen hierarchy:\n\(window.debugDescription)")
        }
        XCTAssertEqual(result, .completed, "Full-screen window geometry must match the requested state: \(fullScreen)")
    }

    func testEverySupportedLanguageHasCompleteToolbarLabelsWithoutPrintButton() throws {
        let image = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let configurations: [(language: String, appearance: String, previous: String, information: String, print: String, fileMenu: String)] = [
            ("english", "light", "Previous image", "Image information", "Print image", "File"),
            ("chinese", "dark", "上一张", "图片信息", "打印图片", "文件"),
            ("japanese", "light", "前の画像", "画像情報", "画像をプリント", "ファイル"),
            ("french", "light", "Image précédente", "Informations sur l’image", "Imprimer l’image", "Fichier"),
            ("russian", "dark", "Предыдущее изображение", "Информация об изображении", "Напечатать изображение", "Файл"),
            ("spanish", "light", "Imagen anterior", "Información de la imagen", "Imprimir imagen", "Archivo"),
            ("korean", "dark", "이전 이미지", "이미지 정보", "이미지 프린트", "파일")
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
            XCTAssertTrue(app.menuBars.menuBarItems[configuration.fileMenu].waitForExistence(timeout: 5))
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

    func testChangingLanguageRelocalizesExistingDecodeFailure() throws {
        let corrupted = fixtureDirectory.appendingPathComponent("broken.jpg")
        try Data("not a JPEG".utf8).write(to: corrupted)
        // A launch-argument preference would override changes made in Settings.
        let app = launchApp(opening: corrupted, language: nil)
        chooseLanguage("English", in: app)
        defer { chooseLanguage("English", in: app) }
        let status = app.descendants(matching: .any)["image.status"]
        expectStatus(status, containing: "This Mac cannot decode the file")

        app.typeKey(",", modifierFlags: .command)
        // Locate the setting by its own identifier across native picker roles.
        let language = app.descendants(matching: .any).matching(identifier: "settings.language").firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.click()
        app.menuItems["Français"].click()
        app.typeKey("w", modifierFlags: .command)

        let message = "Ce Mac ne peut pas décoder ce fichier"
        expectStatus(status, containing: message)
        XCTAssertFalse((status.label + (status.value as? String ?? "")).contains("Unable to preview"))
        expect(app.descendants(matching: .any)["canvas.unavailable.broken.jpg"], accessibilityLabelContaining: message)
    }

    private func expectStatus(_ status: XCUIElement, containing message: String) {
        // SwiftUI exposes this combined status as StaticText.value on macOS 14.
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", message, message
        ), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [translated], timeout: 5), .completed)
    }

    private func chooseLanguage(_ name: String, in app: XCUIApplication) {
        let titles = ["Language", "语言", "Langue", "Язык", "Idioma", "言語", "언어"]
        let menu = app.menuBars.menuBarItems.matching(NSPredicate(
            format: "title IN %@ OR label IN %@", titles, titles
        )).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        app.menuItems.matching(NSPredicate(
            format: "title ENDSWITH %@ OR label ENDSWITH %@", name, name
        )).firstMatch.click()
    }

    func testMinimizingReleasesCanvasWithoutReportingDecodeFailureAndRestoresImage() throws {
        let file = fixtureDirectory.appendingPathComponent("03-toolbar.png")
        let app = launchApp(opening: file)
        let rendered = canvas(in: app, named: file.lastPathComponent)
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        app.windows[file.lastPathComponent].buttons[XCUIIdentifierMinimizeWindow].click()
        let released = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: rendered)
        XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 5), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["canvas.unavailable.\(file.lastPathComponent)"].exists)

        app.activate()
        app.menuBars.menuBarItems["Window"].click()
        // Native macOS menus expose title separately from label. The CI AX
        // snapshot reports this item with title and an action as its identifier.
        let restore = app.menuItems.matching(NSPredicate(
            format: "title == %@ OR label == %@",
            file.lastPathComponent, file.lastPathComponent
        )).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5), app.debugDescription)
        restore.click()
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        expectCanvasAspect(rendered, ratio: 1.2)
    }

    private func canvas(in window: XCUIElement, named sourceName: String) -> XCUIElement {
        window.descendants(matching: .any)["image.rendered.\(sourceName)"]
    }

    private func canvas(in app: XCUIApplication, named sourceName: String) -> XCUIElement {
        app.descendants(matching: .any)["image.rendered.\(sourceName)"]
    }

    private func launchApp(
        opening file: URL? = nil,
        language: String? = "automatic",
        appearance: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        if let language { app.launchArguments += ["-luma.language", language] }
        if let appearance {
            app.launchArguments += ["-luma.appearance", appearance]
        }
        app.launchEnvironment["LUMAVIEW_DISABLE_UPDATE_CHECK"] = "1"
        if let file {
            app.launchEnvironment["LUMAVIEW_UI_TEST_OPEN_FILE"] = file.path
        }
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // A foreground process is not necessarily the key document window on
        // macOS. Give the actual content focus before sending keyboard input.
        if let file {
            let content = window.descendants(matching: .any).matching(NSPredicate(
                format: "identifier == %@ OR identifier == %@",
                "image.rendered.\(file.lastPathComponent)",
                "canvas.unavailable.\(file.lastPathComponent)"
            )).firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 8))
            if content.identifier.hasPrefix("image.rendered.") {
                content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            } else {
                // The unavailable canvas is an Open File button, not an inert
                // focus target. Clicking it would start a modal file panel.
                window.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: 180, dy: 20)).click()
            }
        } else {
            // The welcome window's brand/title area contains no action button.
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 180, dy: 20)).click()
        }
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
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        let quadrants: [[UInt8]] = [[204, 51, 51, 255], [51, 204, 51, 255], [51, 51, 204, 255], [204, 204, 51, 255]]
        for y in 0..<height {
            for x in 0..<width {
                let color = quadrants[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
                let offset = y * bitmap.bytesPerRow + x * 4
                for channel in 0..<4 { pixels[offset + channel] = color[channel] }
            }
        }
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

    private func expectCanvasAspect(_ element: XCUIElement, ratio: CGFloat) {
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let size = element.frame.size
            return size.height > 0 && abs(size.width / size.height - ratio) < 0.015
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 5), .completed,
                       "Canvas \(element.frame.size) must adapt to image aspect \(ratio)")
    }

    private func expectCanvasPixels(_ element: XCUIElement, in app: XCUIApplication, colors: [NSColor], ratio: CGFloat) {
        expectCanvasAspect(element, ratio: ratio)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        var captureFailure: String?
        var capturedBitmap: NSBitmapImageRep?
        var sampledColors = ""
        let displayed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let bitmap: NSBitmapImageRep
            do {
                let captured = try self.captureCanvas(element, in: app)
                guard let converted = captured.converting(to: .sRGB, renderingIntent: .relativeColorimetric) else {
                    throw NSError(domain: "LumaViewUICapture", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Cannot convert the screenshot ICC profile to sRGB"])
                }
                bitmap = converted
                capturedBitmap = bitmap
            } catch {
                captureFailure = error.localizedDescription
                return true // Finish polling and report a capture failure, never skip it.
            }
            // Sample near both side edges, away from the native rounded corners
            // and status pill. This catches the historic white rails as well as
            // wrong orientation, stale frames, and blank render transitions.
            let points: [(CGFloat, CGFloat)] = [(0.02, 0.2), (0.98, 0.2), (0.02, 0.7), (0.98, 0.7)]
            sampledColors = ""
            return zip(points, colors).allSatisfy { point, expected in
                // Convert the bitmap's ICC profile first. colorAt returns
                // calibrated RGB; converting that NSColor again misinterprets
                // the original display-profile channel values.
                guard let color = bitmap.colorAt(
                    x: Int(CGFloat(bitmap.pixelsWide - 1) * point.0),
                    y: Int(CGFloat(bitmap.pixelsHigh - 1) * point.1)
                ) else { return false }
                sampledColors += "\(point): \(color.redComponent),\(color.greenComponent),\(color.blueComponent); "
                return abs(color.redComponent - expected.redComponent) < 0.15
                    && abs(color.greenComponent - expected.greenComponent) < 0.15
                    && abs(color.blueComponent - expected.blueComponent) < 0.15
            }
        }, object: nil)
        let result = XCTWaiter.wait(for: [displayed], timeout: 5)
        if let data = capturedBitmap?.representation(using: .png, properties: [:]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "Rotation canvas \(element.label)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        print("Rotation pixel check: \(element.label), result=\(result.rawValue), samples=\(sampledColors), captureError=\(captureFailure ?? "none")")
        XCTAssertNil(captureFailure, captureFailure ?? "")
        XCTAssertEqual(result, .completed,
                       "Rendered quadrants must rotate and fill the canvas")
    }

    private func captureCanvas(_ element: XCUIElement, in app: XCUIApplication) throws -> NSBitmapImageRep {
        func failure(_ description: String) -> NSError {
            NSError(domain: "LumaViewUICapture", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
        }
        guard app.state == .runningForeground,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleURL?.lastPathComponent == "LumaView.app" else {
            throw failure("The tested LumaView must be foreground before capturing its window")
        }
        let frame = app.windows.firstMatch.frame
        let canvasFrame = element.frame
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let match = windows.first { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == frontmost.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let windowFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(windowFrame.minX - frame.minX) < 2 && abs(windowFrame.minY - frame.minY) < 2
                && abs(windowFrame.width - frame.width) < 2 && abs(windowFrame.height - frame.height) < 2
        }
        guard let windowID = (match?[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              frame.width > 0, frame.height > 0, frame.contains(canvasFrame) else {
            throw failure("Cannot identify the tested LumaView window and its canvas; refusing to capture another surface")
        }

        // XCUIScreenshot's HEVC encoding can fail on a secondary display. The
        // system PNG capture keeps the same real-pixel test without capturing
        // the desktop, menu bar, or any other application's window.
        let url = fixtureDirectory.appendingPathComponent("rotation-window.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(windowID), "-t", "png", url.path]
        capture.standardError = FileHandle.nullDevice
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0,
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw failure("Cannot capture the validation window as PNG; check the test host's Screen Recording permission")
        }
        let scaleX = CGFloat(cgImage.width) / frame.width
        let scaleY = CGFloat(cgImage.height) / frame.height
        let crop = CGRect(
            x: (canvasFrame.minX - frame.minX) * scaleX,
            y: (canvasFrame.minY - frame.minY) * scaleY,
            width: canvasFrame.width * scaleX,
            height: canvasFrame.height * scaleY
        ).integral
        guard let canvas = cgImage.cropping(to: crop) else { throw failure("Cannot crop the captured canvas") }
        return NSBitmapImageRep(cgImage: canvas)
    }

}
