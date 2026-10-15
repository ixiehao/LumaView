import AppKit
import SwiftUI

private struct CanvasRenderTask: Hashable {
    let request: ImageRenderRequest
    let isSuspended: Bool
}

struct ImageCanvasView: View {
    @ObservedObject var browser: ImageBrowserStore
    let l: L10n
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?
    @State private var displayedURL: URL?
    @State private var isLoading = false
    @State private var activeRequest: ImageRenderRequest?
    @State private var renderOperation: Operation?
    @GestureState private var gestureScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let request = renderRequest(for: geometry.size)
            let renderTask = CanvasRenderTask(
                request: request,
                isSuspended: browser.isCanvasRenderingSuspended
            )
            let isCurrentImage = displayedURL == browser.selectedURL
            let absoluteZoomPercent = isCurrentImage ? image.flatMap { absoluteZoomPercent(for: $0, in: geometry.size) } : nil
            ZStack {
                if isCurrentImage, let image {
                    imageViewport(image, in: geometry.size, absoluteZoomPercent: absoluteZoomPercent)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    emptyCanvas
                }

                VStack {
                    Spacer()
                    statusLine(absoluteZoomPercent: absoluteZoomPercent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: renderTask) {
                guard !renderTask.isSuspended else {
                    releaseDisplayedImage()
                    return
                }
                guard request.url != nil else {
                    loadImage(for: request)
                    return
                }
                prepareImageLoad(for: request)
                // Fast arrow-key navigation should settle on the newest request before
                // consuming the single large-image worker with an intermediate frame.
                try? await Task.sleep(nanoseconds: 55_000_000)
                guard !Task.isCancelled else { return }
                loadImage(for: request)
            }
            .onDisappear { releaseDisplayedImage() }
        }
    }

    private func imageViewport(
        _ image: NSImage,
        in container: CGSize,
        absoluteZoomPercent: Int?
    ) -> some View {
        let rotation = Int(browser.rotation.rounded())
        let fitted = fittedSize(for: image.size, in: container)
        let displayZoom = browser.zoom * gestureScale
        let imageSize = CGSize(width: fitted.width * displayZoom, height: fitted.height * displayZoom)
        let rotatedSize = rotatedBounds(for: imageSize, degrees: browser.rotation)
        let edgeInset = previewInset(for: container)
        let canvasSize = CGSize(
            width: max(container.width, rotatedSize.width + edgeInset * 2),
            height: max(container.height, rotatedSize.height + edgeInset * 2)
        )

        return ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: imageSize.width, height: imageSize.height)
                .rotationEffect(.degrees(browser.rotation))
                .shadow(color: Color.primary.opacity(colorScheme == .dark ? 0.24 : 0.14), radius: 12, y: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.17 : 0.11), lineWidth: 1)
                }
                // The explicit canvas frame is the important part: when the image fits,
                // it exactly matches the visible preview area and centers on both axes.
                // When zoomed beyond it, ScrollView gains only the space it needs.
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: .center)
                .gesture(
                    MagnificationGesture()
                        .updating($gestureScale) { value, state, _ in state = value }
                        .onEnded { value in
                            browser.zoom = min(max(browser.zoom * value, 0.15), 12)
                        }
                )
                .onTapGesture(count: 2) { browser.fitImage() }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .ignore)
        // Scroll views do not reliably expose an AXValue on every macOS release.
        // Put the rotation in the accessible name as well, so VoiceOver and UI
        // regression tests can both observe the state change after a toolbar action.
        .accessibilityLabel("\(browser.selectedFile?.name ?? "LumaView"), \(rotation)°")
        .accessibilityValue("\(absoluteZoomPercent ?? Int((browser.zoom * 100).rounded()))%, \(rotation)°")
        .accessibilityIdentifier("image.rendered.\(browser.selectedFile?.name ?? "unknown")")
    }

    private var emptyCanvas: some View {
        Group {
            if let selected = browser.selectedFile {
                unavailableCanvas(for: selected)
            } else {
                welcomeCanvas
            }
        }
    }

    private var welcomeCanvas: some View {
        VStack(spacing: 14) {
            // Render the canonical high-resolution logo at its final size.
            LumaMark(size: 116)
                .accessibilityHidden(true)
                .padding(.bottom, 4)
            Text("LumaView")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(.primary)
            Text(l.text("canvas.drop"))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            Button(action: { browser.chooseImage(l) }) {
                HStack(spacing: 6) {
                    LumaIcon(kind: .image, size: 14, color: .white)
                    Text(l.text("button.openImage"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
        }
        .padding(30)
        .accessibilityIdentifier("canvas.welcome")
    }

    /// A failed decode is not an empty library. Keeping the selected file visible in
    /// the state and giving it an explicit error prevents the welcome screen from
    /// suggesting that a valid file was never opened.
    private func unavailableCanvas(for selected: ImageFile) -> some View {
        VStack(spacing: 12) {
            LumaIcon(kind: .image, size: 32, color: .secondary)
                .padding(16)
                .background(Color.secondary.opacity(0.10), in: Circle())
            Text(l.text("canvas.noPreview"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(selected.name)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 320)
            Button(l.text("button.openImage")) { browser.chooseImage(l) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(l.text("canvas.noPreview")) \(selected.name)")
        .accessibilityIdentifier("canvas.unavailable.\(selected.name)")
    }

    private func statusLine(absoluteZoomPercent: Int?) -> some View {
        HStack(spacing: 8) {
            if let selected = browser.selectedFile {
                Text(selected.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusDot
                Text(browser.positionText).monospacedDigit()
                statusDot
                Text(absoluteZoomPercent.map { "\($0)%" } ?? "—")
                    .monospacedDigit()
                if let message = browser.statusMessage {
                    statusDot
                    Text(message)
                        .lineLimit(1)
                }
            } else if let message = browser.statusMessage {
                Text(message)
            }
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(14)
        .opacity(browser.selectedFile == nil && browser.statusMessage == nil ? 0 : 1)
        // A combined status line gives VoiceOver one concise announcement and
        // gives the multi-window UI gate a stable way to wait for folder
        // indexing before it sends a navigation command.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("image.status")
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private var statusDot: some View {
        Circle().fill(.secondary.opacity(0.45)).frame(width: 2.5, height: 2.5)
    }

    private var statusAccessibilityLabel: String {
        if let selected = browser.selectedFile {
            return "\(selected.name), \(browser.positionText)"
        }
        return browser.statusMessage ?? "LumaView"
    }

    private func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let inset = previewInset(for: container)
        let availableWidth = max(container.width - inset * 2, 1)
        let availableHeight = max(container.height - inset * 2, 1)
        let scale = min(availableWidth / imageSize.width, availableHeight / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func previewInset(for container: CGSize) -> CGFloat {
        // Keep only a slim breathing edge: document windows now open at the
        // image's aspect ratio, so the preview should use the available canvas
        // rather than appearing inset inside a fixed, oversized window.
        min(max(min(container.width, container.height) * 0.035, 18), 36)
    }

    private func rotatedBounds(for size: CGSize, degrees: Double) -> CGSize {
        let radians = abs(degrees.truncatingRemainder(dividingBy: 180)) * .pi / 180
        return CGSize(
            width: abs(size.width * cos(radians)) + abs(size.height * sin(radians)),
            height: abs(size.width * sin(radians)) + abs(size.height * cos(radians))
        )
    }

    /// `zoom == 1` means “fit this window”; it is not inherently 100%. The value shown
    /// to the user instead compares current on-screen image pixels with the source file's
    /// original pixel dimensions, so it remains meaningful across differently sized photos.
    private func absoluteZoomPercent(for image: NSImage, in container: CGSize) -> Int? {
        guard let original = browser.originalPixelSize,
              original.width > 0, original.height > 0 else { return nil }
        let fitted = fittedSize(for: image.size, in: container)
        let displayed = CGSize(
            // SwiftUI layout uses points; the source dimensions are physical
            // pixels. Include the display backing scale for an absolute value.
            width: fitted.width * browser.zoom * gestureScale * displayScale,
            height: fitted.height * browser.zoom * gestureScale * displayScale
        )
        let scale = min(displayed.width / original.width, displayed.height / original.height)
        guard scale.isFinite, scale >= 0 else { return nil }
        return Int((scale * 100).rounded())
    }

    private func renderRequest(for container: CGSize) -> ImageRenderRequest {
        // Request the image's *fitted* display size, not the window's longest edge.
        // In a wide Retina window this avoids decoding a portrait or square image
        // at several times the pixels it can visibly use.
        let zoomDemand = min(max(browser.zoom, 1), 4)
        let fitted = browser.originalPixelSize.map { fittedSize(for: $0, in: container) } ?? container
        let calculatedTarget = Int(max(fitted.width, fitted.height) * displayScale * zoomDemand * 1.25)
        let target = uiTestRenderPixelOverride ?? calculatedTarget
        return ImageRenderRequest(url: browser.selectedURL, maxPixelSize: target)
    }

    private var uiTestRenderPixelOverride: Int? {
        guard let rawValue = ProcessInfo.processInfo.environment["LUMAVIEW_UI_TEST_RENDER_MAX_PIXELS"],
              let requested = Int(rawValue) else { return nil }
        return min(max(requested, 1_024), 5_120)
    }

    private func prepareImageLoad(for request: ImageRenderRequest) {
        guard activeRequest != request else { return }
        renderOperation?.cancel()
        activeRequest = request
        guard let url = request.url else {
            image = nil
            displayedURL = nil
            isLoading = false
            return
        }

        // Do not leave pixels from the previous URL on screen while a new image
        // decodes. A compact preview is safe because it is explicitly keyed to
        // the requested URL; otherwise the canvas shows its loading state.
        let preview = ImageMemoryCache.shared.hotNavigationPreview(for: url)
        image = preview
        displayedURL = preview == nil ? nil : url
        isLoading = true
    }

    private func releaseDisplayedImage() {
        renderOperation?.cancel()
        renderOperation = nil
        activeRequest = nil
        image = nil
        displayedURL = nil
        isLoading = false
    }

    private func loadImage(for request: ImageRenderRequest) {
        prepareImageLoad(for: request)
        guard request.url != nil else {
            return
        }
        let operation = BlockOperation()
        let cancellation = ImageOperationCancellation(operation)
        operation.addExecutionBlock { [weak operation] in
            guard operation?.isCancelled == false else { return }
            let decoded: NSImage? = autoreleasepool {
                guard operation?.isCancelled == false else { return nil }
                return ImageDecoder.renderedImage(for: request, isCancelled: {
                    cancellation.isCancelled
                })
            }
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async {
                guard renderOperation === operation, activeRequest == request, operation?.isCancelled == false else { return }
                image = decoded
                displayedURL = decoded == nil ? nil : request.url
                isLoading = false
                browser.statusMessage = decoded == nil
                    ? l.text("canvas.noPreview")
                    : nil
            }
        }
        renderOperation = operation
        ImageDecodeQueue.renders.addOperation(operation)
    }
}
