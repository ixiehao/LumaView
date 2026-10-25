import AppKit
import Darwin
import ImageIO

typealias ImageCancellationProbe = @Sendable () -> Bool

/// Operation is Objective-C thread-safe for `isCancelled`, but it is not annotated
/// Sendable. This small immutable bridge keeps cancellation probes safe across the
/// ImageIO, Process and OperationQueue worker boundaries.
final class ImageOperationCancellation: @unchecked Sendable {
    private weak var operation: Operation?

    init(_ operation: Operation) {
        self.operation = operation
    }

    var isCancelled: Bool { operation?.isCancelled ?? true }
}

/// Sketch documents are zip archives (or, in a few workflows, directory packages) that
/// contain a compact preview of the last edited page. Reading that preview avoids
/// parsing Sketch's private editing model and keeps preview work bounded to a bitmap.
enum SketchPreviewExtractor {
    private static let previewPaths = [
        "previews/preview.png",
        "previews/preview.jpg",
        "previews/preview.jpeg"
    ]
    private static let maximumPreviewBytes = 64 * 1024 * 1024
    private static let extractionTimeout: DispatchTimeInterval = .seconds(4)
    private static let previewCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 2
        return cache
    }()
    // Archive extraction invokes /usr/bin/unzip. Serialising cache misses keeps several
    // windows from starting duplicate (or memory-heavy) unzip processes for the same
    // document; the short critical section is only entered for uncached Sketch files.
    private static let extractionLock = NSLock()

    static func previewData(
        from url: URL,
        isCancelled: @escaping ImageCancellationProbe = { false }
    ) -> Data? {
        guard url.pathExtension.lowercased() == "sketch", !isCancelled() else { return nil }
        let cacheKey = ImageMemoryCache.cacheKey(for: url)
        if let cached = previewCache.object(forKey: cacheKey) {
            return Data(referencing: cached)
        }

        // `lock()` is not cancellable. Polling `try()` here lets a stale render
        // leave behind a slow Sketch extraction instead of waiting up to 4 s.
        while !extractionLock.try() {
            guard !isCancelled() else { return nil }
            Thread.sleep(forTimeInterval: 0.01)
        }
        defer { extractionLock.unlock() }
        guard !isCancelled() else { return nil }
        // Another window may have completed the preview while this caller was waiting.
        if let cached = previewCache.object(forKey: cacheKey) {
            return Data(referencing: cached)
        }

        let deadline = DispatchTime.now() + extractionTimeout
        var isDirectory = ObjCBool(false)
        let isPackage = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        if isPackage {
            for path in previewPaths {
                guard !isCancelled() else { return nil }
                if let data = boundedData(at: url.appendingPathComponent(path), deadline: deadline, isCancelled: isCancelled) {
                    storePreview(data, for: cacheKey)
                    return data
                }
            }
            return nil
        }

        for path in previewPaths {
            guard !isCancelled() else { return nil }
            if let data = archiveEntry(path, in: url, deadline: deadline, isCancelled: isCancelled) {
                storePreview(data, for: cacheKey)
                return data
            }
        }
        return nil
    }

    private static func boundedData(at url: URL, deadline: DispatchTime, isCancelled: ImageCancellationProbe) -> Data? {
        guard !isCancelled(), DispatchTime.now() < deadline else { return nil }
        // Validate the opened file, not a pathname that may be a symlink or
        // change between the size check and the read. O_NONBLOCK also prevents
        // an invalid package preview backed by a FIFO from hanging open().
        // A single remote filesystem read can still wait for the OS; the
        // monotonic deadline is checked before opening and between reads.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              attributes.st_size > 0,
              attributes.st_size <= Int64(maximumPreviewBytes) else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while !isCancelled(), DispatchTime.now() < deadline {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!, $0.count) }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard count <= maximumPreviewBytes - data.count else { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard !isCancelled(), DispatchTime.now() < deadline, !data.isEmpty,
              CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
        return data
    }

    /// `unzip` is part of macOS and is invoked without a shell. Output is drained
    /// through a bounded pipe: extraction is terminated as soon as the preview
    /// exceeds the limit, so a malicious archive cannot fill the temp volume.
    private static func archiveEntry(
        _ entry: String,
        in archive: URL,
        deadline: DispatchTime,
        isCancelled: @escaping ImageCancellationProbe
    ) -> Data? {
        let values = try? archive.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, entry]
        guard let data = boundedOutput(
            from: process,
            byteLimit: maximumPreviewBytes,
            deadline: deadline,
            isCancelled: isCancelled
        ), !data.isEmpty,
              CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
        return data
    }

    /// Drain on this worker so cancellation never closes a descriptor owned by
    /// another reader. Nonblocking reads make the output limit and shared
    /// deadline apply even when a subprocess emits nothing or ignores SIGTERM.
    static func boundedOutput(
        from process: Process,
        byteLimit: Int,
        deadline: DispatchTime,
        isCancelled: ImageCancellationProbe = { false }
    ) -> Data? {
        guard byteLimit > 0, !isCancelled(), DispatchTime.now() < deadline else { return nil }
        let output = Pipe()
        let termination = DispatchSemaphore(value: 0)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in termination.signal() }
        defer {
            if process.isRunning {
                process.terminate()
                if termination.wait(timeout: .now() + .milliseconds(250)) != .success, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = termination.wait(timeout: .now() + .seconds(1))
                }
            }
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        let descriptor = output.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else { return nil }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Process may already close the parent's pipe writer on launch.
        try? output.fileHandleForWriting.close()

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while !isCancelled(), DispatchTime.now() < deadline {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!, $0.count) }
            if count > 0 {
                guard count <= byteLimit - data.count else { return nil }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                if termination.wait(timeout: .now() + .milliseconds(40)) == .success {
                    guard !isCancelled(), process.terminationStatus == 0 else { return nil }
                    return data
                }
            } else if errno == EAGAIN {
                var descriptorState = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                _ = poll(&descriptorState, 1, 40)
            } else if errno != EINTR {
                return nil
            }
        }
        return nil
    }

    private static func storePreview(_ data: Data, for key: NSString) {
        previewCache.setObject(data as NSData, forKey: key, cost: data.count)
    }
}

/// An explicitly bounded, thread-safe LRU image cache. Unlike `NSCache`, this
/// has deterministic eviction: a new document window never flushes another
/// window's recent frames, and the least recently used frames leave first.
private final class ImageLRUCache {
    private struct Entry {
        let image: NSImage
        let cost: Int
        var lastAccess: UInt64
    }

    private let costLimit: Int
    private let countLimit: Int
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var totalCost = 0
    private var accessCounter: UInt64 = 0

    init(costLimit: Int, countLimit: Int) {
        self.costLimit = costLimit
        self.countLimit = countLimit
    }

    func image(for key: NSString) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        let stringKey = key as String
        guard var entry = entries[stringKey] else { return nil }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        entries[stringKey] = entry
        return entry.image
    }

    func insert(_ image: NSImage, for key: NSString, cost: Int) {
        lock.lock()
        defer { lock.unlock() }
        let stringKey = key as String
        if let oldEntry = entries.removeValue(forKey: stringKey) {
            totalCost -= oldEntry.cost
        }
        // A frame larger than the entire budget cannot be cached. Reject it
        // before eviction so it cannot flush every useful smaller frame.
        let cost = max(cost, 1)
        guard cost <= costLimit else { return }
        accessCounter &+= 1
        entries[stringKey] = Entry(image: image, cost: cost, lastAccess: accessCounter)
        totalCost += cost
        trimIfNeeded()
    }

    func removeAll() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        totalCost = 0
        lock.unlock()
    }

    private func trimIfNeeded() {
        while totalCost > costLimit || entries.count > countLimit {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { return }
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
    }
}

/// In-memory only. Two global LRU budgets are shared across all document
/// windows; no image data is persisted to disk.
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let navigationPreviews = ImageLRUCache(costLimit: 24 * 1024 * 1024, countLimit: 4)
    private let renderedImages = ImageLRUCache(costLimit: 120 * 1024 * 1024, countLimit: 10)
    // Navigation is initiated on the main actor. Keep a tiny path → validated
    // fingerprint index so its optimistic bridge-frame lookup never has to ask
    // a network/removable volume for resource attributes. Full cache lookups
    // still validate the fingerprint off the UI path before decoding.
    private let navigationKeyLock = NSLock()
    private var navigationKeysByPath: [String: NSString] = [:]
    private var navigationKeyAccess: [String: UInt64] = [:]
    private var navigationKeyCounter: UInt64 = 0
    private let navigationKeyCountLimit = 16

    private init() {}

    func navigationPreview(for url: URL) -> NSImage? {
        let key = Self.cacheKey(for: url)
        let image = navigationPreviews.image(for: key)
        updateNavigationKey(key, for: url, if: image != nil)
        return image
    }

    /// A main-thread-safe optimistic lookup for the currently known revision.
    /// The subsequent display-sized decode performs the authoritative filesystem
    /// fingerprint validation, so an externally replaced file cannot remain as
    /// the final frame.
    func hotNavigationPreview(for url: URL) -> NSImage? {
        let path = Self.pathKey(for: url)
        navigationKeyLock.lock()
        let key = navigationKeysByPath[path]
        if key != nil {
            navigationKeyCounter &+= 1
            navigationKeyAccess[path] = navigationKeyCounter
        }
        navigationKeyLock.unlock()
        guard let key else { return nil }

        let image = navigationPreviews.image(for: key)
        guard image == nil else { return image }
        navigationKeyLock.lock()
        if navigationKeysByPath[path] == key {
            navigationKeysByPath.removeValue(forKey: path)
            navigationKeyAccess.removeValue(forKey: path)
        }
        navigationKeyLock.unlock()
        return nil
    }

    func storeNavigationPreview(_ image: NSImage, for url: URL, pixelSize: Int) {
        let key = Self.cacheKey(for: url)
        navigationPreviews.insert(
            image,
            for: key,
            cost: Self.byteCost(for: image, fallbackPixelSize: pixelSize)
        )
        updateNavigationKey(key, for: url, if: true)
    }

    func renderedImage(for key: NSString) -> NSImage? { renderedImages.image(for: key) }

    func storeRenderedImage(_ image: NSImage, for key: NSString, pixelSize: Int) {
        renderedImages.insert(image, for: key, cost: Self.byteCost(for: image, fallbackPixelSize: pixelSize))
    }

    func clearRenderedImages() { renderedImages.removeAll() }
    func clearNavigationPreviews() {
        navigationPreviews.removeAll()
        navigationKeyLock.lock()
        navigationKeysByPath.removeAll(keepingCapacity: false)
        navigationKeyAccess.removeAll(keepingCapacity: false)
        navigationKeyLock.unlock()
    }

    func clearAll() {
        clearNavigationPreviews()
        renderedImages.removeAll()
    }

    var navigationIndexCount: Int {
        navigationKeyLock.lock()
        defer { navigationKeyLock.unlock() }
        return navigationKeysByPath.count
    }

    /// The same pathname can be replaced by an editor or a cloud sync client.
    /// Including the filesystem identity, modification time and size prevents stale pixels
    /// being reused while retaining a lightweight, memory-only cache.
    static func cacheKey(for url: URL) -> NSString {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        var key = fileFingerprint(for: url, attributes: attributes)
        if url.pathExtension.lowercased() == "sketch", attributes?[.type] as? FileAttributeType == .typeDirectory {
            // Updating a file inside an existing package does not necessarily
            // change the package directory's modification date.
            for name in ["preview.png", "preview.jpg", "preview.jpeg"] {
                let preview = url.appendingPathComponent("previews/\(name)").resolvingSymlinksInPath()
                key += "|\(fileFingerprint(for: preview, attributes: try? FileManager.default.attributesOfItem(atPath: preview.path)))"
            }
        }
        return key as NSString
    }

    private static func fileFingerprint(for url: URL, attributes: [FileAttributeKey: Any]?) -> String {
        let identifier = (attributes?[.systemFileNumber] as? NSNumber)?.stringValue ?? ""
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return "\(url.path)|\(identifier)|\(modified)|\(size)"
    }

    private static func pathKey(for url: URL) -> String {
        // Browsing already supplies canonical URLs. This lookup runs on the
        // UI thread, so it must not touch symlinks on slow/removable volumes.
        url.standardizedFileURL.path
    }

    private func updateNavigationKey(_ key: NSString, for url: URL, if shouldStore: Bool) {
        let path = Self.pathKey(for: url)
        navigationKeyLock.lock()
        defer { navigationKeyLock.unlock() }
        if shouldStore {
            navigationKeysByPath[path] = key
            navigationKeyCounter &+= 1
            navigationKeyAccess[path] = navigationKeyCounter
            while navigationKeysByPath.count > navigationKeyCountLimit,
                  let oldest = navigationKeyAccess.min(by: { $0.value < $1.value })?.key {
                navigationKeysByPath.removeValue(forKey: oldest)
                navigationKeyAccess.removeValue(forKey: oldest)
            }
        } else {
            navigationKeysByPath.removeValue(forKey: path)
            navigationKeyAccess.removeValue(forKey: path)
        }
    }

    private static func byteCost(for image: NSImage, fallbackPixelSize: Int) -> Int {
        if let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            // High-bit-depth ImageIO output can use more than four bytes per
            // pixel. Charge its actual row stride instead of capping the cost
            // at the requested dimensions and quietly exceeding the LRU budget.
            let (cost, overflow) = bitmap.bytesPerRow.multipliedReportingOverflow(by: bitmap.height)
            return overflow ? Int.max : max(cost, 1)
        }
        let size = max(1, min(fallbackPixelSize, 5_120))
        return size * size * 4
    }
}

/// Visible frames use two high-priority lanes: one slow source therefore cannot
/// block every other document, while the global concurrency ceiling remains small.
/// Adjacent-image prefetching stays on one utility lane and never competes with
/// a visible render.
enum ImageDecodeQueue {
    /// Header reads are cheap individually but can become an I/O storm when an
    /// arrow key is held. Keep them bounded separately from visible decoding.
    static let metadata: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.lumaview.image-metadata"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    static let navigationPrefetches: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.lumaview.navigation-prefetch"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    static let renders: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.lumaview.image-decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    /// Print preparation decodes can be substantially larger than an on-screen render.
    /// Keep them in one bounded lane so several windows cannot cause a memory spike.
    static let prints: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.lumaview.print-preparation"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
}

struct ImageRenderRequest: Hashable {
    let url: URL?
    let maxPixelSize: Int

    init(url: URL?, maxPixelSize: Int) {
        self.url = url
        // Bucket sizes prevent tiny resize/zoom changes from decoding a fresh image.
        let size = max(1_024, min(maxPixelSize, 5_120))
        self.maxPixelSize = ((size + 511) / 512) * 512
    }
}

enum ImageDecoder {
    // Formats that cannot provide an ImageIO thumbnail fall back to AppKit. AppKit
    // may instantiate the original representation before our bounded bitmap exists,
    // so reject implausibly large source files/pages before taking that path.
    static let maximumFallbackSourceBytes = 128 * 1024 * 1024
    static let maximumFallbackSourcePixels = 48_000_000

    /// Reads source dimensions from metadata only. This avoids decoding every pixel merely
    /// to report the viewer's absolute scale relative to the original image.
    static func pixelSize(
        for url: URL,
        isCancelled: @escaping ImageCancellationProbe = { false }
    ) -> CGSize? {
        guard !isCancelled() else { return nil }
        if let source = imageSource(for: url, isCancelled: isCancelled),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let size = orientedPixelSize(from: properties), !isCancelled() {
            return size
        }

        guard url.pathExtension.lowercased() != "sketch",
              !isCancelled(), fallbackSourceIsWithinBudget(url),
              let image = sourceImage(for: url, isCancelled: isCancelled), !isCancelled() else { return nil }
        let width = image.representations.map { CGFloat($0.pixelsWide) }.max() ?? image.size.width
        let height = image.representations.map { CGFloat($0.pixelsHigh) }.max() ?? image.size.height
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Thumbnails apply EXIF orientation while decoding. Geometry and the
    /// inspector must use that same displayed orientation, including mirrored
    /// quarter turns, rather than the encoded sensor dimensions.
    static func orientedPixelSize(from properties: [CFString: Any]) -> CGSize? {
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }

    /// Decodes an intentionally bounded bridge frame used only while a neighbour is
    /// promoted to the visible, display-sized render. This cache has no disk backing.
    static func navigationPreview(
        for url: URL,
        maxPixelSize: Int = 1_024,
        isCancelled: @escaping ImageCancellationProbe = { false }
    ) -> NSImage? {
        guard !isCancelled() else { return nil }
        if let cached = ImageMemoryCache.shared.navigationPreview(for: url) { return cached }
        guard let image = decode(url: url, maxPixelSize: maxPixelSize, isCancelled: isCancelled), !isCancelled() else { return nil }
        ImageMemoryCache.shared.storeNavigationPreview(image, for: url, pixelSize: maxPixelSize)
        return image
    }

    static func renderedImage(
        for request: ImageRenderRequest,
        isCancelled: @escaping ImageCancellationProbe = { false }
    ) -> NSImage? {
        guard !isCancelled() else { return nil }
        guard let url = request.url else { return nil }
        let key = "\(ImageMemoryCache.cacheKey(for: url))#\(request.maxPixelSize)" as NSString
        if let cached = ImageMemoryCache.shared.renderedImage(for: key) { return cached }
        guard let image = decode(url: url, maxPixelSize: request.maxPixelSize, isCancelled: isCancelled), !isCancelled() else { return nil }
        ImageMemoryCache.shared.storeRenderedImage(image, for: key, pixelSize: request.maxPixelSize)
        return image
    }

    /// A print representation is deliberately separate from the screen cache:
    /// it uses enough detail for normal 300 DPI output while retaining a firm
    /// memory ceiling for very large TIFF, RAW, PDF and Sketch documents.
    static func printBitmap(
        for url: URL,
        maxPixelSize: Int,
        isCancelled: @escaping ImageCancellationProbe = { false }
    ) -> CGImage? {
        guard let image = decode(
            url: url,
            maxPixelSize: max(2_048, min(maxPixelSize, 5_120)),
            isCancelled: isCancelled
        ), !isCancelled() else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// The image used for printing. Sketch documents print their exported page preview;
    /// regular images retain AppKit's normal source representation.
    static func sourceImage(
        for url: URL,
        isCancelled: @escaping ImageCancellationProbe = { false }
    ) -> NSImage? {
        guard !isCancelled() else { return nil }
        if url.pathExtension.lowercased() == "sketch" {
            return SketchPreviewExtractor.previewData(from: url, isCancelled: isCancelled)
                .flatMap { NSImage(data: $0) }
        }
        guard !isCancelled() else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func decode(
        url: URL,
        maxPixelSize: Int,
        isCancelled: @escaping ImageCancellationProbe
    ) -> NSImage? {
        guard !isCancelled() else { return nil }
        guard let source = imageSource(for: url, isCancelled: isCancelled) else {
            guard url.pathExtension.lowercased() != "sketch" else { return nil }
            return fallbackDecode(url: url, maxPixelSize: maxPixelSize, isCancelled: isCancelled)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), !isCancelled() else {
            return fallbackDecode(url: url, maxPixelSize: maxPixelSize, isCancelled: isCancelled)
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private static func imageSource(for url: URL, isCancelled: @escaping ImageCancellationProbe) -> CGImageSource? {
        guard !isCancelled() else { return nil }
        if url.pathExtension.lowercased() == "sketch" {
            return SketchPreviewExtractor.previewData(from: url, isCancelled: isCancelled)
                .flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        }
        guard !isCancelled() else { return nil }
        return CGImageSourceCreateWithURL(url as CFURL, nil)
    }

    /// Some system-provided formats, such as PDFs, do not always create an ImageIO source.
    /// Rasterise their fallback at the requested size rather than retaining an unbounded image.
    private static func fallbackDecode(
        url: URL,
        maxPixelSize: Int,
        isCancelled: @escaping ImageCancellationProbe
    ) -> NSImage? {
        guard !isCancelled(), fallbackSourceIsWithinBudget(url),
              let source = sourceImage(for: url, isCancelled: isCancelled), !isCancelled() else { return nil }
        let sourceSize = source.size
        let sourcePixels = sourceSize.width * sourceSize.height
        guard sourceSize.width > 0, sourceSize.height > 0,
              sourcePixels.isFinite,
              sourcePixels <= CGFloat(maximumFallbackSourcePixels) else { return nil }
        let scale = min(1, CGFloat(maxPixelSize) / max(sourceSize.width, sourceSize.height))
        let width = max(1, Int((sourceSize.width * scale).rounded(.up)))
        let height = max(1, Int((sourceSize.height * scale).rounded(.up)))
        guard let bitmap = NSBitmapImageRep(
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
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        guard !isCancelled() else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard !isCancelled() else { return nil }
        guard let cgImage = bitmap.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private static func fallbackSourceIsWithinBudget(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let byteCount = (attributes[.size] as? NSNumber)?.intValue,
              byteCount > 0,
              byteCount <= maximumFallbackSourceBytes else { return false }
        return true
    }
}
