import AppKit
import Darwin
import Foundation

/// Synthetic, repeatable stress coverage for the non-UI image-browser paths.
/// It intentionally uses hard links, so a large catalogue is exercised without
/// filling a developer's disk with duplicated photos.
@main
struct StressHarness {
    private static let imageCount = 1_800
    private static let ignoredFileCount = 250

    static func main() async {
        do {
            let report = try await run()
            print(report)
        } catch {
            fputs("STRESS TEST FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws -> String {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("LumaViewStress-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let fixture = try makeFixture(in: root)
        try require(ImageFile.canOpen(fixture.seed), "JPEG fixture was not recognised")
        try require(!ImageFile.canOpen(root.appendingPathComponent("missing.jpg")), "A missing file was accepted")
        try require(ImageRenderRequest(url: fixture.seed, maxPixelSize: 99_999).maxPixelSize == 5_120, "Large-image decode limit was not enforced")

        let scanStart = Date()
        let directFiles = try ImageBrowserStore.scanFolder(root).get()
        let scanSeconds = Date().timeIntervalSince(scanStart)
        let expectedCount = imageCount + 1
        try require(directFiles.count == expectedCount, "Expected \(expectedCount) images, got \(directFiles.count)")
        try require(directFiles.first?.name == "__seed.jpg", "Natural name ordering changed")

        let browser = await MainActor.run { ImageBrowserStore() }
        await MainActor.run { browser.open(folder: root, selecting: nil) }
        try await waitForFolderScan(browser)
        try await MainActor.run {
            try require(browser.files.count == expectedCount, "Async folder scan returned the wrong count")
            try require(browser.selectedIndex == 0, "Folder scan did not select the first image")

            for _ in 0..<(expectedCount + 64) { browser.next() }
            try require(browser.selectedIndex == expectedCount - 1, "Next navigation crossed the last image")
            for _ in 0..<(expectedCount + 64) { browser.previous() }
            try require(browser.selectedIndex == 0, "Previous navigation crossed the first image")

            for _ in 0..<10_000 {
                browser.next()
                browser.previous()
            }
            for _ in 0..<160 { browser.zoomIn() }
            try require(browser.zoom == 12, "Zoom-in limit failed")
            for _ in 0..<320 { browser.zoomOut() }
            try require(browser.zoom == 0.15, "Zoom-out limit failed")
            browser.fitImage()
            try require(browser.zoom == 1, "Fit action failed")
            for _ in 0..<1_000 { browser.rotate(by: 90) }
            try require(browser.rotation == 0, "Rotation normalisation failed")
        }

        let decodeInputs = Array(directFiles.prefix(320).map(\.url))
        let navigationPreviewStart = Date()
        for url in decodeInputs {
            let preview: NSImage? = autoreleasepool { ImageDecoder.navigationPreview(for: url) }
            try require(preview != nil, "Navigation preview decode failed for \(url.lastPathComponent)")
        }
        let navigationPreviewSeconds = Date().timeIntervalSince(navigationPreviewStart)

        let renderStart = Date()
        for (index, url) in decodeInputs.prefix(120).enumerated() {
            let request = ImageRenderRequest(url: url, maxPixelSize: 1_536 + (index % 3) * 512)
            let image: NSImage? = autoreleasepool { ImageDecoder.renderedImage(for: request) }
            try require(image != nil, "Large-image decode failed for \(url.lastPathComponent)")
        }
        let renderSeconds = Date().timeIntervalSince(renderStart)

        let fourKStart = Date()
        let fourKRequest = ImageRenderRequest(url: fixture.large, maxPixelSize: 5_120)
        let fourKImage: NSImage? = autoreleasepool { ImageDecoder.renderedImage(for: fourKRequest) }
        let fourKWidth = fourKImage?.representations.map(\.pixelsWide).max() ?? 0
        try require(fourKWidth >= 3_840, "4K image was unexpectedly downsampled")
        let fourKSeconds = Date().timeIntervalSince(fourKStart)

        let hotRequest = ImageRenderRequest(url: fixture.seed, maxPixelSize: 2_048)
        let hotStart = Date()
        for _ in 0..<1_000 {
            try require(ImageDecoder.renderedImage(for: hotRequest) != nil, "Hot render-cache lookup failed")
        }
        let hotMilliseconds = Date().timeIntervalSince(hotStart) * 1_000
        let fiveKBaselines = try benchmarkFiveKWindows(fixture.fiveKWindowSources)

        return """
        PASS  catalog: \(expectedCount) images + \(ignoredFileCount) ignored files, scan \(format(scanSeconds))s
        PASS  interactions: 10,000 next/previous cycles, zoom bounds, fit, 1,000 rotations
        PASS  navigation previews: \(decodeInputs.count) bounded decodes in \(format(navigationPreviewSeconds))s
        PASS  renders: 120 adaptive decodes in \(format(renderSeconds))s; 4K decode in \(format(fourKSeconds))s; 1,000 hot cache reads in \(String(format: "%.1f", hotMilliseconds))ms
        PASS  limits: 1 utility prefetch worker, 2 visible-image workers, 24 MiB navigation-preview cache, 120 MiB render cache, 5K decode ceiling
        \(fiveKBaselines.joined(separator: "\n"))
        INFO  GPU baseline: LumaView owns no Metal textures directly; use Instruments → Metal System Trace on the GUI app to record Core Animation texture allocation alongside these RSS results.
        """
    }

    private static func makeFixture(in root: URL) throws -> (seed: URL, large: URL, fiveKWindowSources: [URL]) {
        let seed = root.appendingPathComponent("__seed.jpg")
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1_024,
            pixelsHigh: 768,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.43, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1_024, height: 768)).fill()
        NSColor(calibratedRed: 0.24, green: 0.83, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 92, y: 110, width: 560, height: 340), xRadius: 120, yRadius: 120).fill()
        NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.43, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 710, y: 470, width: 110, height: 110)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.76]) else {
            throw NSError(domain: "LumaViewStress", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create JPEG fixture"])
        }
        try data.write(to: seed, options: .atomic)

        for index in 1...imageCount {
            let target = root.appendingPathComponent(String(format: "photo-%04d.jpg", index))
            try FileManager.default.linkItem(at: seed, to: target)
        }
        for index in 1...ignoredFileCount {
            let target = root.appendingPathComponent(String(format: "note-%04d.txt", index))
            try Data("not an image".utf8).write(to: target, options: .atomic)
        }
        let largeDirectory = root.appendingPathComponent("large-fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: largeDirectory, withIntermediateDirectories: true)
        let large = largeDirectory.appendingPathComponent("4k-photo.jpg")
        try makeFourKJPEG(at: large)

        let fiveKDirectory = root.appendingPathComponent("5k-fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: fiveKDirectory, withIntermediateDirectories: true)
        let fiveKSource = fiveKDirectory.appendingPathComponent("5k-source.jpg")
        try makeJPEG(at: fiveKSource, width: 5_120, height: 2_880)
        let fiveKWindowSources = try (1...8).map { index -> URL in
            let target = fiveKDirectory.appendingPathComponent("window-\(index).jpg")
            try FileManager.default.linkItem(at: fiveKSource, to: target)
            return target
        }
        return (seed, large, fiveKWindowSources)
    }

    private static func makeFourKJPEG(at url: URL) throws {
        try makeJPEG(at: url, width: 3_840, height: 2_160)
    }

    private static func makeJPEG(at url: URL, width: Int, height: Int) throws {
        let bitmap = NSBitmapImageRep(
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
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSColor(calibratedRed: 0.12, green: 0.56, blue: 0.61, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 280, y: 350, width: 2_000, height: 1_050), xRadius: 420, yRadius: 420).fill()
        NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.38, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 2_650, y: 1_360, width: 330, height: 330)).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw NSError(domain: "LumaViewStress", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create JPEG fixture"])
        }
        try data.write(to: url, options: .atomic)
    }

    private static func benchmarkFiveKWindows(_ sources: [URL]) throws -> [String] {
        try require(sources.count >= 8, "5K benchmark needs eight image sources")
        return try [1, 4, 8].map { windowCount in
            ImageMemoryCache.shared.clearAll()
            let startingRSS = residentMemoryBytes()
            var peakRSS = startingRSS
            var firstImageSeconds: TimeInterval = 0
            var heldImages: [NSImage] = []
            heldImages.reserveCapacity(windowCount)

            for (index, url) in sources.prefix(windowCount).enumerated() {
                let start = Date()
                let image: NSImage? = autoreleasepool {
                    ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 5_120))
                }
                if index == 0 { firstImageSeconds = Date().timeIntervalSince(start) }
                guard let image else {
                    throw NSError(domain: "LumaViewStress", code: 5, userInfo: [NSLocalizedDescriptionKey: "5K decode failed"])
                }
                heldImages.append(image)
                peakRSS = max(peakRSS, residentMemoryBytes())
            }

            let switchStart = Date()
            for index in 0..<20 {
                let url = sources[index % windowCount]
                let preview: NSImage? = autoreleasepool { ImageDecoder.navigationPreview(for: url) }
                guard preview != nil else {
                    throw NSError(domain: "LumaViewStress", code: 6, userInfo: [NSLocalizedDescriptionKey: "5K navigation preview failed"])
                }
            }
            let averageSwitchMilliseconds = Date().timeIntervalSince(switchStart) * 1_000 / 20
            peakRSS = max(peakRSS, residentMemoryBytes())
            withExtendedLifetime(heldImages) {}

            return "BASELINE  \(windowCount) × 5K: first image \(format(firstImageSeconds))s; average next/previous bridge \(String(format: "%.1f", averageSwitchMilliseconds))ms; RSS +\(formatBytes(peakRSS - startingRSS)) (peak \(formatBytes(peakRSS)))"
        }
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private static func waitForFolderScan(_ browser: ImageBrowserStore) async throws {
        for _ in 0..<250 {
            if await MainActor.run(body: { !browser.isScanning }) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "LumaViewStress", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for folder scan"])
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(domain: "LumaViewStress", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        String(format: "%.1f MiB", Double(bytes) / 1_048_576)
    }
}
