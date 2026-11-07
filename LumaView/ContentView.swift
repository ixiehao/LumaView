import SwiftUI
import UniformTypeIdentifiers

/// The application is deliberately a single-canvas viewer. Folder discovery is
/// retained only as the source for previous/next navigation; it has no persistent
/// browser chrome, list rendering, or sidebar state.
struct ContentView: View {
    @ObservedObject var browser: ImageBrowserStore
    @ObservedObject var updateChecker: UpdateChecker
    /// Stable per-document automation identity. It is not announced by
    /// VoiceOver; it lets the UI suite distinguish multiple real windows even
    /// while their selected image and native window title change.
    let windowAccessibilityIdentifier: String?
    @AppStorage("luma.language") private var languageRaw = AppLanguage.automatic.rawValue
    @AppStorage("luma.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @State private var isDropTarget = false
    @State private var dropTask: Task<Void, Never>?

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .automatic }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var l: L10n { L10n(language: language) }

    var body: some View {
        viewer
            .preferredColorScheme(appearance.colorScheme)
            .environment(\.locale, language.locale)
    }

    private var viewer: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            ImageCanvasView(browser: browser, l: l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // An available-update notice is transient chrome. Overlay it so it
            // never changes the canvas height that the document window locks
            // to the current image aspect ratio.
            UpdateAvailableBanner(checker: updateChecker, l: l)
                .zIndex(1)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: receiveDrop(providers:))
        .onDisappear {
            dropTask?.cancel()
            dropTask = nil
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.09))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                    .padding(20)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(windowAccessibilityIdentifier.map { "window.document.\($0)" } ?? "window.welcome")
    }

    private func receiveDrop(providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        dropTask?.cancel()
        let selectionGeneration = browser.selectionGeneration
        dropTask = Task { @MainActor [weak browser] in
            let urls = await DocumentDrop.fileURLs(from: providers)
            // A slow provider must not replace a newer drop, a file opened
            // meanwhile, or reopen documents after its window disappeared.
            guard !Task.isCancelled, let browser,
                  browser.selectionGeneration == selectionGeneration else { return }
            if urls.count == 1, let url = urls.first {
                browser.open(url: url)
            } else {
                let images = urls.filter(ImageFile.canOpen)
                if images.isEmpty, let url = urls.first { browser.open(url: url) }
                else { LumaViewWindowRegistry.shared.openDocumentWindows(for: images) }
            }
        }
        return true
    }
}

/// Displays the one canonical LumaView logo asset. It is intentionally not
/// re-drawn in SwiftUI, so every placement shares the approved mark exactly.
struct LumaMark: View {
    let size: CGFloat

    init(size: CGFloat = 18) {
        self.size = size
    }

    var body: some View {
        Image("LumaLogo")
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("LumaView")
    }
}

struct LumaWordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            LumaMark(size: 18)
            Text("LumaView")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LumaView")
    }
}

/// Resolve every dropped file in its original order. No window/UI work happens
/// in item-provider callbacks, and duplicate aliases are opened only once.
@MainActor
enum DocumentDrop {
    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        var seen = Set<URL>()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            guard !Task.isCancelled else { return [] }
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    continuation.resume(returning: url)
                }
            }
            guard !Task.isCancelled else { return [] }
            if let url, url.isFileURL {
                let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
                if seen.insert(canonical).inserted { urls.append(canonical) }
            }
        }
        return urls
    }
}
