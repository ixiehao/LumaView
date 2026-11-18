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

    @MainActor
    func testAnimatedImagesPlayRotateNavigateAndClose() throws {
        let fixtures: [(String, String)] = [
            ("gif", "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"),
            ("webp", "UklGRqgAAABXRUJQVlA4WAoAAAACAAAAdwAATwAAQU5JTQYAAAD/////AABBTk1GOgAAAAAAAAAAAHcAAE8AACADAAJWUDhMIgAAAC93wBMAD/CHkaeYP6N5/mMJhNlG9ac9g0ncI6L/AVhVdVBBTk1GOgAAAAAAAAAAAHcAAE8AACADAABWUDhMIQAAAC93wBMAD3AF6afAl2L+4wBhtlENzp92EveI6H9UVQMcFAA="),
        ]
        for (format, encoded) in fixtures {
            let folder = fixtureDirectory.appendingPathComponent(format, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = folder.appendingPathComponent("01-animation.\(format)")
            try XCTUnwrap(Data(base64Encoded: encoded)).write(to: image)
            try makePNG(at: folder.appendingPathComponent("02-still.png"), width: 120, height: 80)
            let app = launchApp(opening: image)
            let rendered = canvas(in: app, named: image.lastPathComponent)
            XCTAssertTrue(waitForAnimation(rendered, x: 0.25, y: 0.5), "\(format) should animate")
            clickToolbarItem("Rotate right", in: app)
            let rotation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                rendered.exists && rendered.label.contains("90°")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotation], timeout: 5), .completed)
            XCTAssertTrue(waitForAnimation(rendered, x: 0.5, y: 0.25), "\(format) should animate after rotation")
            app.typeKey(.rightArrow, modifierFlags: [])
            XCTAssertTrue(canvas(in: app, named: "02-still.png").waitForExistence(timeout: 8), "\(format) navigation")
            app.typeKey(.leftArrow, modifierFlags: [])
            XCTAssertTrue(rendered.waitForExistence(timeout: 8))
            XCTAssertTrue(waitForAnimation(rendered, x: 0.25, y: 0.5), "\(format) should resume on return")
            app.typeKey("w", modifierFlags: .command)
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.windows.firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
            app.terminate()
        }
    }

    @MainActor
    private func waitForAnimation(_ element: XCUIElement, x: CGFloat, y: CGFloat) -> Bool {
        guard element.waitForExistence(timeout: 8) else { return false }
        var first: NSColor?
        let deadline = Date().addingTimeInterval(7)
        while Date() < deadline {
            guard element.exists,
                  let bitmap = NSBitmapImageRep(data: element.screenshot().pngRepresentation),
                  let color = bitmap.colorAt(x: Int(CGFloat(bitmap.pixelsWide - 1) * x),
                                             y: Int(CGFloat(bitmap.pixelsHigh - 1) * y))?.usingColorSpace(.sRGB) else { return false }
            if let previous = first {
                let difference = abs(previous.redComponent - color.redComponent)
                    + abs(previous.greenComponent - color.greenComponent)
                    + abs(previous.blueComponent - color.blueComponent)
                if difference > 0.5 { return true }
            } else { first = color }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @MainActor
    func testLaunchExposesAccessiblePrimaryControls() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["Open file"].waitForExistence(timeout: 5))
    }

    @MainActor
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

    @MainActor
    func testFinderStyleOpenLoadsFirstImageAndArrowKeysNavigateFolder() throws {
        let app = launchApp(opening: fixtureDirectory.appendingPathComponent("01-first.png"))
        XCTAssertTrue(app.windows["01-first.png"].waitForExistence(timeout: 5))

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.windows["02-next.png"].waitForExistence(timeout: 5))

        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(app.windows["01-first.png"].waitForExistence(timeout: 5))
    }

    @MainActor
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

    @MainActor
    func testPDFPageControlsShortcutsAndCurrentPageInformation() throws {
        try assertPDFPageControlsAndInformation(legacyInformationAnchor: false)
    }

    @MainActor
    func testPDFInformationUsesTheMontereyCompatibleAnchor() throws {
        try assertPDFPageControlsAndInformation(legacyInformationAnchor: true)
    }

    @MainActor
    private func assertPDFPageControlsAndInformation(legacyInformationAnchor: Bool) throws {
        let folder = fixtureDirectory.appendingPathComponent("pdf", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pdf = folder.appendingPathComponent("01-pages.pdf")
        let image = folder.appendingPathComponent("02-image.png")
        try makePDF(at: pdf, pageSizes: [CGSize(width: 600, height: 400), CGSize(width: 400, height: 600), CGSize(width: 600, height: 400)])
        try makePNG(at: image, width: 800, height: 600)
        let app = launchApp(opening: pdf, legacyInformationAnchor: legacyInformationAnchor)
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
        clickToolbarItem("Image information", in: app)
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

    @MainActor
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

    @MainActor
    func testToolbarRotationCyclesThroughEveryRightAngle() throws {
        exerciseRotationSequence(verifyPixels: false)
    }

    @MainActor
    func testRenderedRotationPixelsFillTheCanvasAtEveryRightAngle() throws {
        exerciseRotationSequence(verifyPixels: true)
    }

    @MainActor
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
            // Rotating to portrait can move this command into toolbar overflow.
            clickToolbarItem("Rotate right", in: app)
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

    @MainActor
    private func clickToolbarItem(_ title: String, in app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if button.exists && button.isHittable {
            XCTAssertTrue(button.isEnabled, file: file, line: line)
            button.click()
            return
        }
        let overflow = app.toolbars.popUpButtons.firstMatch
        XCTAssertTrue(overflow.waitForExistence(timeout: 5), file: file, line: line)
        overflow.click()
        let item = app.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(item.isEnabled, file: file, line: line)
        // AppKit forwards overflow commands privately. A real click invokes
        // them reliably where XCTest's AX menu selection can leave them open.
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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
        // A late occlusion notification must not release a full-screen frame.
        let disappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: rendered
        )
        disappeared.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 3), .completed)
        // Menu coordinates remain stable while AppKit hides the titlebar in a
        // full-screen Space. Wait for the transition to enable its command;
        // screen-sized geometry alone does not establish that it has finished.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let viewMenu = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 5))
        // The hidden menu's AX frame remains at y=0, but hovering its centre
        // hits the full-screen toolbar on macOS 15. Reach the actual top edge
        // first, then wait for AppKit to expose a clickable menu bar.
        viewMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).hover()
        let menuRevealed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: viewMenu
        )
        let revealResult = XCTWaiter.wait(for: [menuRevealed], timeout: 5)
        if revealResult != .completed { print("Full-screen menu did not reveal: \(app.debugDescription)") }
        XCTAssertEqual(revealResult, .completed)
        viewMenu.click()
        let exitFullScreen = app.menuItems["Exit Full Screen"]
        let commandReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"),
            object: exitFullScreen
        )
        let commandResult = XCTWaiter.wait(for: [commandReady], timeout: 5)
        if commandResult != .completed { print("Full-screen command unavailable: \(app.debugDescription)") }
        XCTAssertEqual(commandResult, .completed)
        // Use XCTest's menu-selection event path, which hovers/selects the
        // item before activation. A raw coordinate click can leave the native
        // full-screen menu tracking on macOS 15 without invoking its action.
        exitFullScreen.click()
        expectFullScreen(false, in: window)
        expectCanvasAspect(rendered, ratio: 1 / 1.2)
    }

    @MainActor
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

    @MainActor
    private func fullWindowFrame(_ window: XCUIElement) -> CGRect {
        let toolbar = window.toolbars.firstMatch
        return toolbar.exists ? window.frame.union(toolbar.frame) : window.frame
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func testChangingLanguageRelocalizesExistingDecodeFailure() throws {
        let corrupted = fixtureDirectory.appendingPathComponent("broken.jpg")
        try Data("not a JPEG".utf8).write(to: corrupted)
        // A launch-argument preference would override changes made in Settings.
        let app = launchApp(opening: corrupted, language: nil)
        chooseLanguage("English", in: app)
        defer { chooseLanguage("English", in: app) }
        let status = app.descendants(matching: .any)["image.status"]
        expectStatus(status, containing: "This Mac cannot decode the file")

        // This test checks settings-driven localization, not punctuation-key
        // injection, which depends on the host's active input source.
        app.menuBars.menuBarItems["LumaView"].click()
        let settings = app.menuItems.matching(NSPredicate(
            format: "title IN %@ OR label IN %@", ["Settings…", "Preferences…"], ["Settings…", "Preferences…"]
        )).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
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

    @MainActor
    private func expectStatus(_ status: XCUIElement, containing message: String) {
        // SwiftUI exposes this combined status as StaticText.value on macOS 14.
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", message, message
        ), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [translated], timeout: 5), .completed)
    }

    @MainActor
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

    @MainActor
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

    @MainActor
    private func canvas(in window: XCUIElement, named sourceName: String) -> XCUIElement {
        window.descendants(matching: .any)["image.rendered.\(sourceName)"]
    }

    @MainActor
    private func canvas(in app: XCUIApplication, named sourceName: String) -> XCUIElement {
        app.descendants(matching: .any)["image.rendered.\(sourceName)"]
    }

    @MainActor
    private func launchApp(
        opening file: URL? = nil,
        language: String? = "automatic",
        appearance: String? = nil,
        legacyInformationAnchor: Bool = false
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
        if legacyInformationAnchor {
            app.launchEnvironment["LUMAVIEW_TEST_LEGACY_POPOVER"] = "1"
        }
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

    @MainActor
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

    @MainActor
    private func expectCanvasAspect(_ element: XCUIElement, ratio: CGFloat) {
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let size = element.frame.size
            return size.height > 0 && abs(size.width / size.height - ratio) < 0.015
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 5), .completed,
                       "Canvas \(element.frame.size) must adapt to image aspect \(ratio)")
    }

    @MainActor
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

    @MainActor
    private func captureCanvas(_ element: XCUIElement, in app: XCUIApplication) throws -> NSBitmapImageRep {
        func failure(_ description: String) -> NSError {
            NSError(domain: "LumaViewUICapture", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
        }
        guard app.state == .runningForeground,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleURL?.lastPathComponent == "LumaView.app" else {
            throw failure("The tested LumaView must be foreground before capturing its window")
        }
        let frame = fullWindowFrame(app.windows.firstMatch)
        let canvasFrame = element.frame
        guard frame.width > 0, frame.height > 0,
              canvasFrame.width > 0, canvasFrame.height > 0,
              frame.contains(canvasFrame) else {
            throw failure("Cannot identify a canvas contained in the tested window")
        }
        // XCTest captures only this element through its automation service.
        // Avoid a separately signed screencapture process and its independent
        // TCC permission. Failure to obtain real pixels remains a test failure.
        guard let bitmap = NSBitmapImageRep(data: element.screenshot().pngRepresentation) else {
            throw failure("XCTest could not capture the tested canvas as PNG")
        }
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              abs(CGFloat(bitmap.pixelsWide) / CGFloat(bitmap.pixelsHigh)
                  - canvasFrame.width / canvasFrame.height) < 0.01 else {
            throw failure("The captured pixels do not match the tested canvas bounds")
        }
        return bitmap
    }

}
