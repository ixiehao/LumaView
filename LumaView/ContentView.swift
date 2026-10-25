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
        .alert(l.text("update.check.title"), isPresented: updateNoticeBinding) {
            Button(l.text("button.ok"), role: .cancel) {
                updateChecker.dismissNotice()
            }
        } message: {
            Text(updateNoticeMessage)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(windowAccessibilityIdentifier.map { "window.document.\($0)" } ?? "window.welcome")
    }

    private var updateNoticeBinding: Binding<Bool> {
        Binding(
            get: { updateChecker.notice != nil },
            set: { isPresented in
                if !isPresented { updateChecker.dismissNotice() }
            }
        )
    }

    private var updateNoticeMessage: String {
        switch updateChecker.notice {
        case .upToDate:
            l.text("update.check.upToDate")
        case .unavailable:
            l.text("update.check.unavailable")
        case nil:
            ""
        }
    }

    private func receiveDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                browser.open(url: url)
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
