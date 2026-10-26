import AppKit
import Combine
import UniformTypeIdentifiers

/// The only rotations offered by LumaView. Keeping the state discrete avoids
/// floating-point bounds calculations and makes the displayed dimensions
/// deterministic after a complete rotation cycle.
enum QuarterTurn: Int, CaseIterable, Sendable {
    case zero
    case clockwise
    case upsideDown
    case counterClockwise

    var degrees: Double { Double(rawValue * 90) }
    var swapsAxes: Bool { self == .clockwise || self == .counterClockwise }

    func rotated(by degrees: Double) -> QuarterTurn {
        guard degrees.isFinite else { return self }
        let steps = Int((degrees / 90).rounded())
        guard abs(degrees - Double(steps * 90)) < 0.001 else { return self }
        let raw = (rawValue + steps % 4 + 4) % 4
        return QuarterTurn(rawValue: raw) ?? self
    }
}

/// One geometry contract for the image view and the document window. The
/// source dimensions stay in their decoded orientation; only the display
/// bounds swap for a quarter turn. That leaves no second trigonometric or
/// aspect-ratio implementation that can drift from the canvas.
enum ViewerGeometry {
    struct CanvasLayout: Equatable {
        let unrotatedImageSize: CGSize
        let displayedImageSize: CGSize
        let canvasSize: CGSize
    }

    static func displayedSize(for imageSize: CGSize, rotation: QuarterTurn) -> CGSize? {
        guard imageSize.width > 0, imageSize.height > 0,
              imageSize.width.isFinite, imageSize.height.isFinite else { return nil }
        return rotation.swapsAxes
            ? CGSize(width: imageSize.height, height: imageSize.width)
            : imageSize
    }

    /// ImageIO-backed NSImages normally report a point size, but a CGImage
    /// representation is authoritative when that value is zero. Centralising
    /// this fallback prevents a zero-sized SwiftUI frame on decoded images.
    static func decodedSize(for image: NSImage) -> CGSize? {
        if let size = validatedSize(image.size) {
            return size
        }
        let width = image.representations.map(\.pixelsWide).max() ?? 0
        let height = image.representations.map(\.pixelsHigh).max() ?? 0
        return validatedSize(CGSize(width: width, height: height))
    }

    /// Lays out the complete image at fit zoom, then grows only the scrollable
    /// canvas when a person zooms in. At fit zoom the displayed image and
    /// canvas have the same dimensions whenever the owning window uses this
    /// contract's display bounds.
    static func canvasLayout(
        imageSize: CGSize,
        viewportSize: CGSize,
        rotation: QuarterTurn,
        zoom: CGFloat
    ) -> CanvasLayout? {
        guard let displayedSourceSize = displayedSize(for: imageSize, rotation: rotation),
              let viewport = validatedSize(viewportSize) else { return nil }

        let fitScale = min(
            viewport.width / displayedSourceSize.width,
            viewport.height / displayedSourceSize.height
        )
        guard fitScale.isFinite, fitScale > 0 else { return nil }

        let clampedZoom = min(max(zoom, 0.15), 12)
        let unrotatedImageSize = CGSize(
            width: imageSize.width * fitScale * clampedZoom,
            height: imageSize.height * fitScale * clampedZoom
        )
        guard let displayedImageSize = displayedSize(for: unrotatedImageSize, rotation: rotation) else {
            return nil
        }
        return CanvasLayout(
            unrotatedImageSize: unrotatedImageSize,
            displayedImageSize: displayedImageSize,
            canvasSize: CGSize(
                width: max(viewport.width, displayedImageSize.width),
                height: max(viewport.height, displayedImageSize.height)
            )
        )
    }

    private static func validatedSize(_ size: CGSize) -> CGSize? {
        guard size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite else { return nil }
        return size
    }
}

struct ImageFile: Identifiable, Hashable, Sendable {
    let url: URL

    init(url: URL) {
        self.url = url.standardizedFileURL.resolvingSymlinksInPath()
    }

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.uppercased() }

    // The UTType test covers every format the installed macOS can decode. The extension
    // fallback makes files such as WebP and RAW visible when their metadata is incomplete.
    static let commonExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "tif", "tiff", "heic", "heif", "webp",
        "bmp", "ico", "icns", "avif", "jxl", "jp2", "j2k", "pdf", "dng", "raw",
        "cr2", "nef", "arw", "orf", "rw2", "sketch"
    ]

    static func canOpen(_ url: URL) -> Bool {
        // A Sketch document can be a package rather than a regular file. Its rendered
        // page preview is handled by SketchPreviewExtractor in ImagePipeline.
        if url.pathExtension.lowercased() == "sketch" {
            return FileManager.default.fileExists(atPath: url.path)
        }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return false }
        if values?.contentType?.conforms(to: .image) == true { return true }
        return commonExtensions.contains(url.pathExtension.lowercased())
    }

}

/// Shares an in-flight index between document windows that point at the same
/// folder and limits unrelated folder scans to two. Each window receives a
/// cancellable lease: when its last consumer leaves, an old scan is stopped
/// instead of continuing to occupy an I/O lane in the background.
actor FolderIndexCoordinator {
    static let shared = FolderIndexCoordinator()

    private struct InFlight {
        let task: Task<Result<[ImageFile], Error>, Never>
        var subscribers: Set<UUID>
    }

    private var inFlight: [URL: InFlight] = [:]
    private var availableSlots = 2

    func files(in folder: URL) async -> Result<[ImageFile], Error> {
        let canonicalURL = folder.standardizedFileURL.resolvingSymlinksInPath()
        let subscriber = UUID()
        return await withTaskCancellationHandler(
            operation: {
                await self.join(canonicalURL, subscriber: subscriber)
            },
            onCancel: {
                Task { await self.leave(canonicalURL, subscriber: subscriber) }
            }
        )
    }

    private func join(_ canonicalURL: URL, subscriber: UUID) async -> Result<[ImageFile], Error> {
        guard !Task.isCancelled else { return .failure(CancellationError()) }
        let task: Task<Result<[ImageFile], Error>, Never>
        if var existing = inFlight[canonicalURL], !existing.task.isCancelled {
            existing.subscribers.insert(subscriber)
            inFlight[canonicalURL] = existing
            task = existing.task
        } else {
            // `withTaskCancellationHandler` releases a lease from a tiny
            // follow-up task. A new window can arrive in that interval, after
            // the old task has been cancelled but before its entry is removed.
            // Never attach it to the cancelled task: it needs a fresh index.
            task = makeScanTask(for: canonicalURL)
            inFlight[canonicalURL] = InFlight(task: task, subscribers: [subscriber])
        }

        let result = await task.value
        leave(canonicalURL, subscriber: subscriber)
        return result
    }

    private func leave(_ canonicalURL: URL, subscriber: UUID) {
        guard var active = inFlight[canonicalURL] else { return }
        active.subscribers.remove(subscriber)
        guard active.subscribers.isEmpty else {
            inFlight[canonicalURL] = active
            return
        }
        // Cancellation propagates to the enumerator through Task.isCancelled.
        active.task.cancel()
        inFlight.removeValue(forKey: canonicalURL)
    }

    private func makeScanTask(for canonicalURL: URL) -> Task<Result<[ImageFile], Error>, Never> {
        let coordinator = self
        return Task.detached(priority: .utility) {
            guard await coordinator.acquireSlot() else {
                return .failure(CancellationError())
            }
            if Task.isCancelled {
                await coordinator.releaseSlot()
                return .failure(CancellationError())
            }
            let result = ImageBrowserStore.scanFolder(canonicalURL, isCancelled: { Task.isCancelled })
            await coordinator.releaseSlot()
            return result
        }
    }

    /// A polling semaphore is deliberate here: unlike a continuation queue it
    /// immediately observes cancellation while waiting behind two old scans.
    private func acquireSlot() async -> Bool {
        while availableSlots == 0 {
            guard !Task.isCancelled else { return false }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        guard !Task.isCancelled else { return false }
        availableSlots -= 1
        return true
    }

    private func releaseSlot() {
        availableSlots = min(availableSlots + 1, 2)
    }
}

/// Header dimensions are shared by every window, but are only read from a
/// background task. Storing them by the versioned image cache key makes arrow
/// navigation avoid repeating filesystem metadata work for an unchanged file.
final class ImageMetadataCache {
    static let shared = ImageMetadataCache()

    private struct Entry {
        let metadata: ImageDocumentMetadata
        var lastAccess: UInt64
    }

    private let lock = NSLock()
    private let countLimit = 1_024
    private var entries: [String: Entry] = [:]
    private var accessCounter: UInt64 = 0

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func clear() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        accessCounter = 0
        lock.unlock()
    }

    func pixelSize(for url: URL, isCancelled: @escaping @Sendable () -> Bool = { false }) -> CGSize? {
        metadata(for: url, isCancelled: isCancelled)?.pixelSize
    }

    func metadata(for url: URL, pageIndex: Int = 0, isCancelled: @escaping @Sendable () -> Bool = { false }) -> ImageDocumentMetadata? {
        let stringKey = "\(ImageMemoryCache.cacheKey(for: url))#page:\(pageIndex)"
        lock.lock()
        if var cached = entries[stringKey] {
            accessCounter &+= 1
            cached.lastAccess = accessCounter
            entries[stringKey] = cached
            lock.unlock()
            return cached.metadata
        }
        lock.unlock()

        guard !isCancelled(), let metadata = ImageDecoder.documentMetadata(for: url, pageIndex: pageIndex, isCancelled: isCancelled), !isCancelled() else {
            return nil
        }

        lock.lock()
        accessCounter &+= 1
        entries[stringKey] = Entry(metadata: metadata, lastAccess: accessCounter)
        while entries.count > countLimit,
              let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            entries.removeValue(forKey: oldest.key)
        }
        lock.unlock()
        return metadata
    }
}

/// Keep app-owned feedback semantic until it is displayed. A language change
/// must not require repeating I/O or clearing an existing warning.
enum ImageBrowserStatus: String, CaseIterable, Sendable {
    case unsupportedFormat = "error.unsupportedFormat"
    case emptyFolder = "error.emptyFolder"
    case noPrintSelection = "error.noPrintSelection"
    case preparingPrint = "status.preparingPrint"
    case printPreparationFailed = "error.printPreparation"
    case previewUnavailable = "canvas.noPreview"
}

/// Window-local reading positions, not rendered pages. Only nonzero positions
/// need storage; the least recently visited document is evicted at the limit.
struct PDFReadingHistory {
    static let capacity = 128
    private var positions: [URL: Int] = [:]
    private var recentURLs: [URL] = []

    mutating func pageIndex(for url: URL) -> Int {
        guard let index = positions[url] else { return 0 }
        touch(url)
        return index
    }

    mutating func remember(pageIndex: Int, for url: URL) {
        guard pageIndex > 0 else {
            positions.removeValue(forKey: url)
            recentURLs.removeAll { $0 == url }
            return
        }
        positions[url] = pageIndex
        touch(url)
        if recentURLs.count > Self.capacity {
            positions.removeValue(forKey: recentURLs.removeFirst())
        }
    }

    private mutating func touch(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.append(url)
    }
}

@MainActor
final class ImageBrowserStore: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var files: [ImageFile] = []
    @Published private(set) var selectedIndex: Int?
    @Published private(set) var originalPixelSize: CGSize?
    /// Reopening an edited file is a new selection even when its URL is unchanged.
    @Published private(set) var selectionGeneration = 0
    @Published private(set) var pdfPageIndex = 0
    @Published private(set) var pdfPageCount = 0
    @Published var zoom: CGFloat = 1
    @Published var keepsStatusVisible = false
    @Published private(set) var quarterTurn: QuarterTurn = .zero
    /// A post-mutation invalidation token for the canvas. `Published` sends
    /// `objectWillChange` before it stores a new value; that is suitable for
    /// simple controls, but a right-angle transform must never render against
    /// the previous orientation while AppKit has already resized its window.
    /// This revision is incremented only after `quarterTurn` is assigned and
    /// followed by an explicit post-assignment change notification.
    @Published private(set) var canvasPresentationRevision: UInt64 = 0
    @Published var status: ImageBrowserStatus?
    @Published private(set) var folderScanErrorMessage: String?
    @Published private(set) var imageLoadFailed = false
    @Published private(set) var previewFailure: ImagePreviewFailure?
    @Published private(set) var isScanning = false
    @Published private(set) var isPreparingPrint = false
    /// A minimised or occluded AppKit window should not pin a full-resolution
    /// SwiftUI canvas. Its selected file and navigation state stay available.
    @Published private(set) var isCanvasRenderingSuspended = false
    private var scanGeneration = 0
    // The current file is rendered before its containing directory has been
    // indexed. Keep a navigation request made during that short interval so a
    // user can press ←/→ immediately after choosing a file; it is applied as
    // soon as the sorted, local folder index is available.
    private var pendingNavigationOffset = 0
    private var folderScanTask: Task<Void, Never>?
    private var pixelSizeTask: Task<Void, Never>?
    private var metadataOperation: Operation?
    private var navigationPrefetchTask: Task<Void, Never>?
    private var navigationPrefetchOperations: [Operation] = []
    private var printPreparationOperation: Operation?
    private var pdfReadingHistory = PDFReadingHistory()

    deinit {
        folderScanTask?.cancel()
        pixelSizeTask?.cancel()
        metadataOperation?.cancel()
        navigationPrefetchTask?.cancel()
        navigationPrefetchOperations.forEach { $0.cancel() }
        printPreparationOperation?.cancel()
    }

    var selectedFile: ImageFile? {
        guard let selectedIndex, files.indices.contains(selectedIndex) else { return nil }
        return files[selectedIndex]
    }

    var selectedURL: URL? { selectedFile?.url }
    var isPDF: Bool { selectedURL?.pathExtension.lowercased() == "pdf" }
    var hasMultiplePDFPages: Bool { isPDF && pdfPageCount > 1 }
    var hasPreviousPage: Bool { isPDF && pdfPageIndex > 0 }
    var hasNextPage: Bool { isPDF && pdfPageIndex + 1 < pdfPageCount }
    var hasPrevious: Bool { (selectedIndex ?? 0) > 0 }
    var hasNext: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex < files.index(before: files.endIndex)
    }

    var positionText: String {
        guard let selectedIndex else { return "—" }
        return "\(selectedIndex + 1) / \(files.count)"
    }

    var windowTitle: String { selectedFile?.name ?? "LumaView" }

    // Rendering, folder discovery and printing finish independently. A successful
    // decode must not erase an unreadable-folder warning or print progress.
    func displayStatusMessage(_ l: L10n) -> String? {
        if let status {
            return l.text(status.rawValue)
        }
        if let previewFailure { return l.text(previewFailure.rawValue) }
        if imageLoadFailed { return l.text("canvas.noPreview") }
        // File-system diagnostics are supplied by macOS in its system language.
        return folderScanErrorMessage
    }

    func statusAccessibilityLabel(_ l: L10n) -> String {
        let position = hasMultiplePDFPages ? l.text("pdf.pagePosition", pdfPageIndex + 1, pdfPageCount) : positionText
        let parts = [selectedFile?.name, selectedFile == nil ? nil : position, displayStatusMessage(l)]
            .compactMap { $0 }
        return parts.isEmpty ? "LumaView" : parts.joined(separator: ", ")
    }

    func reportImageLoadResult(isAvailable: Bool, failure: ImagePreviewFailure? = nil) {
        previewFailure = isAvailable ? nil : (failure ?? .cannotDecode)
        imageLoadFailed = !isAvailable
    }

    func chooseImage(_ l: L10n) {
        if let url = Self.chooseImageURLs(l, multiple: false).first { open(file: url) }
    }

    static func chooseImageURLs(_ l: L10n, multiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = l.text("dialog.openImage.title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        var supportedTypes: [UTType] = [
            .image,
            .pdf,
            UTType(importedAs: "com.lumaview.sketch-document")
        ]
        for extensionName in ["webp", "avif", "jxl", "sketch"] {
            if let type = UTType(filenameExtension: extensionName) {
                supportedTypes.append(type)
            }
        }
        panel.allowedContentTypes = supportedTypes
        panel.allowsOtherFileTypes = false
        panel.prompt = l.text("dialog.openImage.action")
        return panel.runModal() == .OK ? panel.urls : []
    }

    func open(file url: URL) {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard ImageFile.canOpen(canonicalURL) else {
            status = .unsupportedFormat
            return
        }
        open(
            folder: canonicalURL.deletingLastPathComponent(),
            selecting: canonicalURL
        )
    }

    /// The common entry point for Finder document events and drag-and-drop. Opening a
    /// single file still scans only its parent folder, preserving LumaView's lightweight
    /// previous/next navigation without creating an image library.
    func open(url: URL) {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            status = .unsupportedFormat
            return
        }
        if isDirectory.boolValue && url.pathExtension.lowercased() != "sketch" {
            open(folder: url, selecting: nil)
        } else {
            open(file: url)
        }
    }

    func open(
        folder url: URL,
        selecting preferredURL: URL?
    ) {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        folderURL = canonicalURL
        isScanning = true
        status = nil
        folderScanErrorMessage = nil
        imageLoadFailed = false
        previewFailure = nil
        folderScanTask?.cancel()
        cancelNavigationPrefetches()
        scanGeneration += 1
        pendingNavigationOffset = 0
        let generation = scanGeneration

        // A file opened from Finder is visible immediately. Building the folder
        // index is a separate, cancellable task that later enables previous/next
        // navigation instead of holding the first render hostage to a huge folder.
        if let preferredURL {
            let selected = ImageFile(url: preferredURL)
            files = [selected]
            selectedIndex = nil
            select(index: 0)
        } else {
            pixelSizeTask?.cancel()
            metadataOperation?.cancel()
            printPreparationOperation?.cancel()
            printPreparationOperation = nil
            isPreparingPrint = false
            files = []
            selectedIndex = nil
            originalPixelSize = nil
            pdfPageIndex = 0
            pdfPageCount = 0
            resetViewport()
        }

        folderScanTask = Task { [weak self] in
            let result = await FolderIndexCoordinator.shared.files(in: canonicalURL)
            guard !Task.isCancelled,
                  let self,
                  generation == self.scanGeneration else { return }
            self.finishFolderScan(
                result,
                preferredURL: preferredURL
            )
        }
    }

    nonisolated static func scanFolder(_ url: URL) -> Result<[ImageFile], Error> {
        scanFolder(url, isCancelled: { false })
    }

    /// Enumerate only immediate children and observe cancellation between items.
    /// `contentsOfDirectory` first materialises every child, which delayed the
    /// first photo and kept stale scans running after another file was chosen.
    nonisolated static func scanFolder(
        _ url: URL,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> Result<[ImageFile], Error> {
        guard !isCancelled() else { return .failure(CancellationError()) }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        do {
            guard try canonicalURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                return .failure(POSIXError(.ENOTDIR))
            }
        } catch {
            return .failure(error)
        }
        guard !isCancelled() else { return .failure(CancellationError()) }
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: canonicalURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            return .failure(enumerationError ?? CocoaError(.fileReadUnknown))
        }

        var files: [ImageFile] = []
        while !isCancelled() {
            // A synchronous filesystem call may still wait for macOS (for
            // example a privacy prompt); cancellation is observed on return.
            guard let candidate = enumerator.nextObject() as? URL else { break }
            if isCancelled() { return .failure(CancellationError()) }
            if ImageFile.canOpen(candidate) {
                files.append(ImageFile(url: candidate))
            }
        }
        if isCancelled() { return .failure(CancellationError()) }
        if let enumerationError { return .failure(enumerationError) }
        guard sortFilesNaturally(&files, isCancelled: isCancelled) else {
            return .failure(CancellationError())
        }
        return .success(files)
    }

    /// Folder navigation needs a complete, naturally ordered index, but the
    /// standard library sort cannot observe cancellation after it has started.
    /// This merge sort holds one temporary array and checks cancellation between
    /// runs, so an obsolete huge-directory scan yields promptly.
    nonisolated private static func sortFilesNaturally(
        _ files: inout [ImageFile],
        isCancelled: @escaping @Sendable () -> Bool
    ) -> Bool {
        guard files.count > 1 else { return !isCancelled() }
        var scratch = files
        var runLength = 1
        var sourceIsFiles = true
        while runLength < files.count {
            guard !isCancelled() else { return false }
            let completed: Bool
            if sourceIsFiles {
                completed = mergeNaturalRuns(from: files, into: &scratch, runLength: runLength, isCancelled: isCancelled)
            } else {
                completed = mergeNaturalRuns(from: scratch, into: &files, runLength: runLength, isCancelled: isCancelled)
            }
            guard completed else { return false }
            sourceIsFiles.toggle()
            runLength = min(runLength * 2, files.count)
        }
        if !sourceIsFiles { files = scratch }
        return !isCancelled()
    }

    nonisolated private static func mergeNaturalRuns(
        from source: [ImageFile],
        into destination: inout [ImageFile],
        runLength: Int,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> Bool {
        var start = 0
        var comparisons = 0
        while start < source.count {
            if isCancelled() { return false }
            let middle = min(start + runLength, source.count)
            let end = min(middle + runLength, source.count)
            var left = start
            var right = middle
            var output = start
            while left < middle && right < end {
                comparisons += 1
                if comparisons & 0xFF == 0, isCancelled() { return false }
                if source[left].name.localizedStandardCompare(source[right].name) != .orderedDescending {
                    destination[output] = source[left]
                    left += 1
                } else {
                    destination[output] = source[right]
                    right += 1
                }
                output += 1
            }
            while left < middle {
                destination[output] = source[left]
                left += 1
                output += 1
            }
            while right < end {
                destination[output] = source[right]
                right += 1
                output += 1
            }
            start = end
        }
        return !isCancelled()
    }

    func select(index: Int) {
        guard files.indices.contains(index) else { return }
        selectedIndex = index
        pdfPageIndex = isPDF ? pdfReadingHistory.pageIndex(for: files[index].url) : 0
        pdfPageCount = 0
        prefetchNavigationNeighbours(around: index)
        loadSelectedPage()
    }

    func previousPage() { if hasPreviousPage { selectPDFPage(pdfPageIndex - 1) } }
    func nextPage() { if hasNextPage { selectPDFPage(pdfPageIndex + 1) } }

    func selectPDFPage(_ index: Int) {
        guard isPDF, (0..<pdfPageCount).contains(index), index != pdfPageIndex else { return }
        pdfPageIndex = index
        // Record synchronously: switching files before metadata finishes must
        // still restore the most recently requested page.
        if let url = selectedURL {
            pdfReadingHistory.remember(pageIndex: index, for: url)
        }
        loadSelectedPage(preserveViewport: true)
    }

    private func loadSelectedPage(preserveViewport: Bool = false) {
        guard let url = selectedURL else { return }
        // A print decode belongs to the selected document. Switching images must not
        // later present a print panel for the image the user has already left.
        printPreparationOperation?.cancel()
        printPreparationOperation = nil
        isPreparingPrint = false
        originalPixelSize = nil
        if !preserveViewport { resetViewport() }
        status = nil
        imageLoadFailed = false
        previewFailure = nil
        selectionGeneration += 1
        let generation = selectionGeneration
        let pageIndex = pdfPageIndex

        // Replace, rather than merely ignore, stale header reads. This keeps a
        // held arrow key from enqueuing thousands of user-initiated ImageIO or
        // Sketch metadata operations across multiple windows.
        pixelSizeTask?.cancel()
        metadataOperation?.cancel()
        pixelSizeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 45_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            let operation = BlockOperation()
            operation.qualityOfService = .userInitiated
            let cancellation = ImageOperationCancellation(operation)
            operation.addExecutionBlock { [weak self, weak operation] in
                guard let operation, operation.isCancelled == false else { return }
                let metadata = ImageMetadataCache.shared.metadata(for: url, pageIndex: pageIndex, isCancelled: {
                    cancellation.isCancelled
                })
                guard operation.isCancelled == false else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.metadataOperation === operation,
                          generation == self.selectionGeneration,
                          self.selectedURL == url else { return }
                    self.metadataOperation = nil
                    self.pdfPageCount = self.isPDF ? (metadata?.pageCount ?? self.pdfPageCount) : 0
                    // A document may have lost pages since it was last read.
                    // Restart the normal selection pipeline so rendering, size,
                    // inspector and print all receive the corrected generation.
                    if self.isPDF, let metadata, metadata.pageCount > 0,
                       self.pdfPageIndex >= metadata.pageCount {
                        self.selectPDFPage(metadata.pageCount - 1)
                        return
                    }
                    self.originalPixelSize = metadata?.pixelSize
                }
            }
            self.metadataOperation = operation
            ImageDecodeQueue.metadata.addOperation(operation)
        }
    }

    func previous() { navigate(by: -1) }

    func next() { navigate(by: 1) }

    func zoomIn() { zoom = min(zoom * 1.25, 12) }
    func zoomOut() { zoom = max(zoom / 1.25, 0.15) }
    func fitImage() { zoom = 1 }

    func rotate(by degrees: Double) {
        let nextTurn = quarterTurn.rotated(by: degrees)
        guard nextTurn != quarterTurn else { return }
        quarterTurn = nextTurn
        invalidateCanvasPresentation()
    }

    func resetViewport() {
        let didResetRotation = quarterTurn != .zero
        zoom = 1
        quarterTurn = .zero
        if didResetRotation {
            invalidateCanvasPresentation()
        }
    }

    private func invalidateCanvasPresentation() {
        canvasPresentationRevision &+= 1
        // This notification occurs after both orientation and revision are in
        // storage. It gives SwiftUI a stable snapshot to render, rather than
        // asking a view update started by `Published.willSet` to observe
        // transient old state.
        objectWillChange.send()
    }

    func suspendCanvasRendering() {
        guard !isCanvasRenderingSuspended else { return }
        isCanvasRenderingSuspended = true
        cancelNavigationPrefetches()
    }

    func resumeCanvasRendering() {
        guard isCanvasRenderingSuspended else { return }
        isCanvasRenderingSuspended = false
        if let selectedIndex {
            prefetchNavigationNeighbours(around: selectedIndex)
        }
    }

    func revealInFinder() {
        guard let selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedURL])
    }

    /// There is no sidebar and no persistent thumbnail strip. Instead, retain only the
    /// two likely next destinations as small, memory-bounded bridge frames. It keeps
    /// previous/next navigation perceptibly immediate while the full display-sized decode
    /// remains on its own high-priority queue.
    private func prefetchNavigationNeighbours(around index: Int) {
        cancelNavigationPrefetches()
        guard !isCanvasRenderingSuspended, files.indices.contains(index) else { return }
        let selectedURL = files[index].url
        let neighbourURLs = [index + 1, index - 1]
            .compactMap { files.indices.contains($0) ? files[$0].url : nil }
            .filter { ImageMemoryCache.shared.hotNavigationPreview(for: $0) == nil }

        // Arrow keys can generate many selections in a single event burst. Waiting a
        // moment for that burst to settle means we enqueue at most one pair of useful
        // prefetches instead of filling an OperationQueue with cancelled stale work.
        navigationPrefetchTask = Task { [weak self, neighbourURLs, selectedURL] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled,
                  let self,
                  self.selectedURL == selectedURL else { return }

            self.navigationPrefetchOperations.removeAll(where: \.isFinished)
            for url in neighbourURLs {
                guard !Task.isCancelled else { return }
                let operation = BlockOperation()
                operation.qualityOfService = .utility
                let cancellation = ImageOperationCancellation(operation)
                operation.addExecutionBlock { [weak operation] in
                    guard operation?.isCancelled == false else { return }
                    autoreleasepool {
                        guard operation?.isCancelled == false else { return }
                        _ = ImageDecoder.navigationPreview(for: url, isCancelled: {
                            cancellation.isCancelled
                        })
                    }
                }
                self.navigationPrefetchOperations.append(operation)
                ImageDecodeQueue.navigationPrefetches.addOperation(operation)
            }
        }
    }

    private func cancelNavigationPrefetches() {
        navigationPrefetchTask?.cancel()
        navigationPrefetchTask = nil
        navigationPrefetchOperations.forEach { $0.cancel() }
        navigationPrefetchOperations.removeAll()
    }

    private func finishFolderScan(
        _ result: Result<[ImageFile], Error>,
        preferredURL: URL?
    ) {
        isScanning = false
        folderScanTask = nil
        switch result {
        case .success(var discovered):
            // Directory browsing skips hidden files. An explicitly opened file
            // still belongs to this window even when enumeration omits it.
            if let selected = selectedFile, !discovered.contains(where: { $0.url == selected.url }) {
                let insertion = discovered.firstIndex {
                    selected.name.localizedStandardCompare($0.name) == .orderedAscending
                } ?? discovered.endIndex
                discovered.insert(selected, at: insertion)
            }
            if let activeURL = selectedURL ?? preferredURL,
               let index = discovered.firstIndex(where: { $0.url == activeURL }) {
                files = discovered
                selectedIndex = index
                prefetchNavigationNeighbours(around: index)
                status = nil
                applyPendingNavigation(from: index)
            } else if discovered.isEmpty {
                files = []
                selectedIndex = nil
                originalPixelSize = nil
                resetViewport()
                status = .emptyFolder
            } else {
                files = discovered
                select(index: 0)
                status = nil
            }
        case .failure(let error) where error is CancellationError:
            break
        case .failure(let error):
            // Keep an already-rendering direct file usable even if its folder
            // becomes unavailable while the background navigation scan runs.
            pendingNavigationOffset = 0
            folderScanErrorMessage = error.localizedDescription
            if selectedURL == nil {
                files = []
                selectedIndex = nil
                originalPixelSize = nil
            }
        }
    }

    private func navigate(by offset: Int) {
        guard let selectedIndex else { return }
        let destination = selectedIndex + offset
        if files.indices.contains(destination) {
            select(index: destination)
        } else if isScanning {
            // `files` temporarily contains just the current file while the
            // parent folder is indexed. The destination is not knowable yet,
            // but the intent is valid and must not be lost.
            pendingNavigationOffset += offset
        }
    }

    private func applyPendingNavigation(from selectedIndex: Int) {
        guard pendingNavigationOffset != 0 else { return }
        let destination = min(
            max(selectedIndex + pendingNavigationOffset, files.startIndex),
            files.index(before: files.endIndex)
        )
        pendingNavigationOffset = 0
        guard destination != selectedIndex else { return }
        select(index: destination)
    }

    /// Prepares a print-quality, but bounded, representation off the main actor.
    /// A fixed source decode could turn one 100 MP RAW or TIFF into a multi-hundred-
    /// megabyte spike; 300 DPI at the largest common paper size fits below this limit.
    func printSelectedImage(from hostWindow: NSWindow? = nil) {
        guard let url = selectedURL else {
            status = .noPrintSelection
            return
        }
        guard !isPreparingPrint else { return }

        isPreparingPrint = true
        status = .preparingPrint
        let pageIndex = pdfPageIndex
        let rotation = quarterTurn
        let generation = selectionGeneration
        let paperSize = NSPrintInfo.shared.paperSize
        let printPixelLimit = min(
            5_120,
            max(2_048, Int(max(paperSize.width, paperSize.height) / 72 * 300))
        )

        let preparation = BlockOperation()
        preparation.qualityOfService = .userInitiated
        let cancellation = ImageOperationCancellation(preparation)
        preparation.addExecutionBlock { [weak self, weak preparation] in
            guard let preparation, preparation.isCancelled == false else { return }
            let bitmap: CGImage? = autoreleasepool {
                guard preparation.isCancelled == false else { return nil }
                return ImageDecoder.printBitmap(
                    for: url,
                    maxPixelSize: printPixelLimit,
                    pageIndex: pageIndex,
                    rotation: rotation,
                    isCancelled: { cancellation.isCancelled }
                )
            }
            guard preparation.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.printPreparationOperation === preparation else { return }
                self.printPreparationOperation = nil
                self.isPreparingPrint = false
                guard preparation.isCancelled == false, self.selectedURL == url,
                      self.selectionGeneration == generation else { return }
                guard let bitmap else {
                    self.status = .printPreparationFailed
                    return
                }

                // Cross the worker boundary with immutable pixels; create the
                // AppKit image only on the main actor that owns the print UI.
                let image = NSImage(cgImage: bitmap, size: .zero)
                let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
                printInfo.horizontalPagination = .fit
                printInfo.verticalPagination = .fit
                let view = PrintableImageView(image: image, pageSize: printInfo.paperSize)
                let operation = NSPrintOperation(view: view, printInfo: printInfo)
                operation.showsPrintPanel = true
                operation.showsProgressPanel = true
                self.status = nil
                if let hostWindow {
                    operation.runModal(for: hostWindow, delegate: nil, didRun: nil, contextInfo: nil)
                } else {
                    operation.run()
                }
            }
        }
        printPreparationOperation = preparation
        ImageDecodeQueue.prints.addOperation(preparation)
    }
}

/// A one-page, aspect-fit print representation with consistent margins. It intentionally
/// avoids snapshots of the interactive canvas, including its chrome and status indicator.
private final class PrintableImageView: NSView {
    private let image: NSImage

    init(image: NSImage, pageSize: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: pageSize))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let printableRect = bounds.insetBy(dx: 32, dy: 32)
        guard image.size.width > 0, image.size.height > 0,
              printableRect.width > 0, printableRect.height > 0 else { return }

        let scale = min(printableRect.width / image.size.width, printableRect.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let destination = NSRect(
            x: printableRect.midX - size.width / 2,
            y: printableRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
}
