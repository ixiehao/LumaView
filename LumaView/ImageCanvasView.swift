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
    @State private var image: NSImage?
    @State private var displayedURL: URL?
    @State private var decodedURL: URL?
    @State private var isLoading = false
    @State private var activeRequest: ImageRenderRequest?
    @State private var renderOperation: Operation?
    @GestureState private var gestureScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            // `canvasPresentationRevision` is changed only after rotation is
            // stored. Reading both values here creates one stable snapshot for
            // the transform, its geometry and AX state, even though
            // `Published`'s regular notification is sent before assignment.
            let rotation = browser.quarterTurn
            let presentationRevision = browser.canvasPresentationRevision
            let request = renderRequest(for: geometry.size)
            let renderTask = CanvasRenderTask(
                request: request,
                isSuspended: browser.isCanvasRenderingSuspended
            )
            let isCurrentImage = displayedURL == browser.selectedURL
            // Keep the local value distinct from the helper method. Swift 5.10
            // otherwise resolves the name to itself inside `flatMap`, which
            // breaks a documented Xcode 15 source build.
            let renderedZoomPercent = isCurrentImage
                ? image.flatMap { absoluteZoomPercent(for: $0, in: geometry.size, rotation: rotation) }
                : nil
            ZStack {
                if isCurrentImage, let image {
                    imageViewport(
                        image,
                        in: geometry.size,
                        rotation: rotation,
                        absoluteZoomPercent: renderedZoomPercent
                    )
                    // A quarter turn is a new layout epoch, not a new image
                    // decode. Recreating this visual subtree clears SwiftUI's
                    // cached transform/layout while retaining the NSImage.
                    .id(presentationRevision)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    emptyCanvas
                }

                VStack {
                    Spacer()
                    statusLine(absoluteZoomPercent: renderedZoomPercent)
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
        rotation: QuarterTurn,
        absoluteZoomPercent: Int?
    ) -> some View {
        let layout = ViewerGeometry.decodedSize(for: image).flatMap {
            ViewerGeometry.canvasLayout(
                imageSize: $0,
                viewportSize: container,
                rotation: rotation,
                zoom: browser.zoom * gestureScale
            )
        }

        return Group {
            if let layout {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: layout.unrotatedImageSize.width,
                            height: layout.unrotatedImageSize.height
                        )
                        .rotationEffect(.degrees(rotation.degrees))
                        // The outer frame is in the displayed orientation. It
                        // is therefore exactly what the window-sizing layer
                        // consumes at fit zoom, rather than an unrotated image
                        // frame padded after the fact.
                        .frame(
                            width: layout.canvasSize.width,
                            height: layout.canvasSize.height,
                            alignment: .center
                        )
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
            } else {
                emptyCanvas
            }
        }
        .accessibilityElement(children: .ignore)
        // Scroll views do not reliably expose an AXValue on every macOS release.
        // Put the rotation in the accessible name as well, so VoiceOver and UI
        // regression tests can both observe the state change after a toolbar action.
        .accessibilityLabel("\(browser.selectedFile?.name ?? "LumaView"), \(Int(rotation.degrees))°")
        .accessibilityValue("\(absoluteZoomPercent ?? Int((browser.zoom * 100).rounded()))%, \(Int(rotation.degrees))°")
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
                if let message = browser.displayStatusMessage {
                    statusDot
                    Text(message)
                        .lineLimit(1)
                }
            } else if let message = browser.displayStatusMessage {
                Text(message)
            }
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(14)
        .opacity(browser.selectedFile == nil && browser.displayStatusMessage == nil ? 0 : 1)
        // A combined status line gives VoiceOver one concise announcement and
        // gives the multi-window UI gate a stable way to wait for folder
        // indexing before it sends a navigation command.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("image.status")
        .accessibilityLabel(browser.statusAccessibilityLabel)
    }

    private var statusDot: some View {
        Circle().fill(.secondary.opacity(0.45)).frame(width: 2.5, height: 2.5)
    }

    /// `zoom == 1` means “fit this window”; it is not inherently 100%. The value shown
    /// to the user instead compares current on-screen image pixels with the source file's
    /// original pixel dimensions, so it remains meaningful across differently sized photos.
    private func absoluteZoomPercent(
        for image: NSImage,
        in container: CGSize,
        rotation: QuarterTurn
    ) -> Int? {
        guard let original = browser.originalPixelSize,
              original.width > 0, original.height > 0 else { return nil }
        guard let decodedSize = ViewerGeometry.decodedSize(for: image),
              let fitted = ViewerGeometry.canvasLayout(
                  imageSize: decodedSize,
                  viewportSize: container,
                  rotation: rotation,
                  zoom: browser.zoom * gestureScale
              )?.unrotatedImageSize else { return nil }
        let displayed = CGSize(
            // SwiftUI layout uses points; the source dimensions are physical
            // pixels. Include the display backing scale for an absolute value.
            width: fitted.width * displayScale,
            height: fitted.height * displayScale
        )
        let scale = min(displayed.width / original.width, displayed.height / original.height)
        guard scale.isFinite, scale >= 0 else { return nil }
        return Int((scale * 100).rounded())
    }

    private func renderRequest(for container: CGSize) -> ImageRenderRequest {
        // Decode size intentionally does not depend on orientation. A right-angle
        // turn reuses the same NSImage and only changes its display transform;
        // treating a 90° turn as a fresh image request causes an unnecessary
        // decode during the window's intermediate resize pass. The longest
        // visible canvas edge is orientation-invariant when the document swaps
        // its axes, while the normal cap still bounds memory use.
        let zoomDemand = min(max(browser.zoom, 1), 4)
        let longestCanvasEdge = max(container.width, container.height)
        let calculatedTarget = Int(longestCanvasEdge * displayScale * zoomDemand * 1.25)
        return ImageRenderRequest(url: browser.selectedURL, maxPixelSize: calculatedTarget)
    }

    private func prepareImageLoad(for request: ImageRenderRequest) {
        guard activeRequest != request else { return }
        renderOperation?.cancel()
        activeRequest = request
        guard let url = request.url else {
            image = nil
            displayedURL = nil
            decodedURL = nil
            isLoading = false
            return
        }

        // A resize/zoom can request a sharper decode of the same image. Keep
        // its current pixels until that decode completes, avoiding a flash or
        // a downgrade to the navigation preview. Never keep a different file.
        if displayedURL != url || image == nil {
            decodedURL = nil
            let preview = ImageMemoryCache.shared.hotNavigationPreview(for: url)
            image = preview
            displayedURL = preview == nil ? nil : url
        }
        isLoading = true
    }

    private func releaseDisplayedImage() {
        renderOperation?.cancel()
        renderOperation = nil
        activeRequest = nil
        image = nil
        displayedURL = nil
        decodedURL = nil
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
                // A failed resolution upgrade should not erase an already
                // usable image. A new URL still reports its normal decode error.
                if let decoded {
                    image = decoded
                    displayedURL = request.url
                    decodedURL = request.url
                } else if decodedURL != request.url {
                    // A navigation preview is only a bridge, not proof that
                    // this file still decodes successfully.
                    image = nil
                    displayedURL = nil
                }
                isLoading = false
                browser.reportImageLoadResult(isAvailable: image != nil, failureMessage: l.text("canvas.noPreview"))
            }
        }
        renderOperation = operation
        ImageDecodeQueue.renders.addOperation(operation)
    }
}
