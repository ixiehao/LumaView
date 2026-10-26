import AppKit
import UniformTypeIdentifiers

struct DefaultImageFormat: Identifiable {
    let name: String
    let extensions: String
    let contentType: UTType
    var id: String { contentType.identifier }

    static let common: [Self] = [
        .init(name: "JPEG", extensions: ".jpg · .jpeg · .jpe", contentType: .jpeg),
        .init(name: "PNG", extensions: ".png", contentType: .png),
        .init(name: "HEIC", extensions: ".heic", contentType: .heic),
        .init(name: "HEIF", extensions: ".heif", contentType: .heif),
        .init(name: "WebP", extensions: ".webp", contentType: .webP),
        .init(name: "GIF", extensions: ".gif", contentType: .gif),
        .init(name: "TIFF", extensions: ".tif · .tiff", contentType: .tiff),
        .init(name: "BMP", extensions: ".bmp", contentType: .bmp),
        .init(name: "ICO", extensions: ".ico", contentType: .ico),
        .init(name: "PDF", extensions: ".pdf", contentType: .pdf)
    ]
}

@MainActor
protocol DefaultApplicationHandling {
    func applicationURL(for type: UTType) -> URL?
    func setApplication(at url: URL, for type: UTType) async throws
}

@MainActor
struct SystemDefaultApplicationHandler: DefaultApplicationHandling {
    func applicationURL(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    func setApplication(at url: URL, for type: UTType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type)
    }
}

@MainActor
final class DefaultApplicationsModel: ObservableObject {
    struct Result {
        var appliedCount = 0
        var failedFormats: [String] = []
        var cancelled = false
    }

    @Published private(set) var selected: Set<String> = []
    @Published private(set) var applications: [String: URL] = [:]
    @Published private(set) var isApplying = false
    @Published private(set) var result: Result?
    let applicationURL: URL
    private let handler: DefaultApplicationHandling

    init(applicationURL: URL = Bundle.main.bundleURL, handler: DefaultApplicationHandling? = nil) {
        self.applicationURL = applicationURL.standardizedFileURL.resolvingSymlinksInPath()
        self.handler = handler ?? SystemDefaultApplicationHandler()
    }

    // Never associate files with a mounted installer or a disposable build.
    var isInstalled: Bool {
        Self.isInstalledApplication(applicationURL)
    }

    static func isInstalledApplication(_ url: URL) -> Bool {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        return url.pathExtension == "app" && roots.contains {
            url.path.hasPrefix($0.standardizedFileURL.resolvingSymlinksInPath().path + "/")
        }
    }

    func isDefault(_ format: DefaultImageFormat) -> Bool {
        applications[format.id]?.standardizedFileURL.resolvingSymlinksInPath() == applicationURL
    }

    func applicationName(for format: DefaultImageFormat) -> String? {
        guard let url = applications[format.id] else { return nil }
        return (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
    }

    func isAnotherCopy(_ format: DefaultImageFormat) -> Bool {
        guard !isDefault(format), let url = applications[format.id],
              let identifier = Bundle(url: applicationURL)?.bundleIdentifier else { return false }
        return Bundle(url: url)?.bundleIdentifier == identifier
    }

    func applicationDetails(for format: DefaultImageFormat) -> String? {
        guard let url = applications[format.id] else { return nil }
        let bundle = Bundle(url: url)
        let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return [applicationName(for: format), version, url.path].compactMap { $0 }.joined(separator: "\n")
    }

    func refresh() {
        guard !isApplying else { return }
        readApplications()
    }

    private func readApplications() {
        applications = Dictionary(uniqueKeysWithValues: DefaultImageFormat.common.compactMap { format in
            handler.applicationURL(for: format.contentType).map { (format.id, $0) }
        })
        selected.subtract(DefaultImageFormat.common.filter(isDefault).map(\.id))
    }

    func select(_ format: DefaultImageFormat, enabled: Bool) {
        guard !isApplying, !isDefault(format) else { return }
        if enabled { selected.insert(format.id) } else { selected.remove(format.id) }
        result = nil
    }

    func selectAllImages() {
        guard !isApplying else { return }
        selected.formUnion(DefaultImageFormat.common.filter { $0.contentType.conforms(to: .image) && !isDefault($0) }.map(\.id))
        result = nil
    }

    func clearSelection() {
        guard !isApplying else { return }
        selected.removeAll()
        result = nil
    }

    func apply() async {
        guard isInstalled, !isApplying, !selected.isEmpty else { return }
        isApplying = true
        result = nil
        defer { isApplying = false }
        var outcome = Result()
        for format in DefaultImageFormat.common where selected.contains(format.id) {
            guard !Task.isCancelled else { outcome.cancelled = true; break }
            do {
                try await handler.setApplication(at: applicationURL, for: format.contentType)
                // Completion alone is insufficient: report what Launch Services
                // actually resolved, including an older copy with the same ID.
                if handler.applicationURL(for: format.contentType)?.standardizedFileURL.resolvingSymlinksInPath() == applicationURL {
                    outcome.appliedCount += 1
                } else {
                    outcome.failedFormats.append(format.name)
                }
            } catch {
                let error = error as NSError
                if Task.isCancelled || (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) ||
                    (error.domain == NSOSStatusErrorDomain && error.code == -128) {
                    outcome.cancelled = true
                    break
                }
                outcome.failedFormats.append(format.name)
            }
        }
        readApplications()
        result = outcome
    }
}
