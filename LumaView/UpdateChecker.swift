@preconcurrency import AppKit
import Foundation
import SwiftUI

/// Update metadata is deliberately kept separate from image browsing. The app
/// only asks GitHub for public release metadata; no file paths, images, or
/// other personal data are ever sent from LumaView.
struct ReleaseVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(tag: String) {
        let raw = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let downloadURL: URL
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
    }

    func update(
        newerThan installedVersion: ReleaseVersion,
        expectedRepositoryPath: String
    ) -> AvailableUpdate? {
        guard !draft,
              !prerelease,
              let releaseVersion = ReleaseVersion(tag: tagName),
              installedVersion < releaseVersion,
              htmlURL.scheme == "https",
              htmlURL.host == "github.com",
              htmlURL.path.hasPrefix("/\(expectedRepositoryPath)/releases/") else { return nil }
        return AvailableUpdate(version: tagName, downloadURL: htmlURL)
    }
}

enum UpdateCheckNotice: Equatable {
    case available
    case upToDate
    case unavailable
}

/// Keep these endpoints in one place. `repositorySlug` must be changed when
/// the project is published; the app validates every returned download link
/// against this exact repository before making it clickable.
enum LumaViewProjectLinks {
    static let repositorySlug = "ixiehao/LumaView"
    static let repository = URL(string: "https://github.com/\(repositorySlug)")!
    static let issues = URL(string: "https://github.com/\(repositorySlug)/issues/new/choose")!
    static let releases = URL(string: "https://github.com/\(repositorySlug)/releases")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repositorySlug)/releases/latest")!
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var notice: UpdateCheckNotice?

    private let session: URLSession
    private let currentVersion: ReleaseVersion
    private let releaseURL: URL
    private let expectedRepositoryPath: String
    private let defaults: UserDefaults
    private let lastCheckedDefaultsKey: String
    private let now: () -> Date
    @Published private(set) var isChecking = false
    @Published private(set) var dismissedUpdateVersion: String?
    var noticeHandler: ((UpdateCheckNotice) -> Void)?
    private var shouldAnnounceResult = false
    private(set) weak var noticeWindow: NSWindow?
    private var lastCheckedAt: Date?

    private static let checkInterval: TimeInterval = 12 * 60 * 60
    nonisolated static let defaultLastCheckedDefaultsKey = "luma.update.last-checked-at"

    init(
        currentVersion: ReleaseVersion? = nil,
        session: URLSession = .shared,
        releaseURL: URL = LumaViewProjectLinks.latestReleaseAPI,
        expectedRepositoryPath: String = LumaViewProjectLinks.repositorySlug,
        defaults: UserDefaults = .standard,
        lastCheckedDefaultsKey: String = UpdateChecker.defaultLastCheckedDefaultsKey,
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion ?? Self.installedVersion
        self.session = session
        self.releaseURL = releaseURL
        self.expectedRepositoryPath = expectedRepositoryPath
        self.defaults = defaults
        self.lastCheckedDefaultsKey = lastCheckedDefaultsKey
        self.now = now
        self.lastCheckedAt = defaults.object(forKey: lastCheckedDefaultsKey) as? Date
    }

    var hasUpdate: Bool { availableUpdate != nil }

    var showsUpdateBanner: Bool {
        availableUpdate.map { $0.version != dismissedUpdateVersion } ?? false
    }

    func dismissBanner() { dismissedUpdateVersion = availableUpdate?.version }

    func checkForUpdate(force: Bool = false, announceResult: Bool = false) async {
        if announceResult, !shouldAnnounceResult { noticeWindow = NSApp.keyWindow }
        if isChecking {
            shouldAnnounceResult = shouldAnnounceResult || announceResult
            return
        }
        if !force, let lastCheckedAt {
            let elapsed = now().timeIntervalSince(lastCheckedAt)
            if elapsed >= 0, elapsed < Self.checkInterval { return }
        }

        isChecking = true
        shouldAnnounceResult = announceResult
        var outcome: UpdateCheckNotice = .unavailable
        defer {
            let completedAt = now()
            lastCheckedAt = completedAt
            defaults.set(completedAt, forKey: lastCheckedDefaultsKey)
            isChecking = false
            let announce = shouldAnnounceResult
            shouldAnnounceResult = false
            if announce {
                notice = outcome
                noticeHandler?(outcome)
            }
        }

        var request = URLRequest(url: releaseURL)
        request.timeoutInterval = 10
        request.setValue("LumaView update checker", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            availableUpdate = release.update(
                newerThan: currentVersion,
                expectedRepositoryPath: expectedRepositoryPath
            )
            outcome = availableUpdate == nil ? .upToDate : .available
        } catch {
            // Offline and transient API failures never interfere with viewing.

        }
    }

    func dismissNotice() {
        notice = nil
    }

    func openDownloadPage() {
        guard let downloadURL = availableUpdate?.downloadURL else { return }
        NSWorkspace.shared.open(downloadURL)
    }

    private static var installedVersion: ReleaseVersion {
        let rawVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return ReleaseVersion(tag: rawVersion ?? "0.0.0") ?? ReleaseVersion(tag: "0.0.0")!
    }
}

struct UpdateAvailableBanner: View {
    @ObservedObject var checker: UpdateChecker
    let l: L10n

    var body: some View {
        if checker.showsUpdateBanner, let update = checker.availableUpdate {
            HStack(spacing: 10) {
                LumaMark(size: 18)
                Text(l.text("update.available", update.version))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Button(l.text("button.downloadUpdate")) {
                    checker.openDownloadPage()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(l.text("update.later")) { checker.dismissBanner() }
                    .buttonStyle(.borderless).controlSize(.small)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(Color.accentColor.opacity(0.09))
            .overlay(alignment: .bottom) { Divider().opacity(0.55) }
            .accessibilityElement(children: .contain)
        }
    }
}

/// One presenter for the application, including checks made with no document open.
/// Tests exercise the checker with an injected callback and never display an alert.
@MainActor
final class UpdateNoticePresenter {
    private weak var checker: UpdateChecker?
    private var presenting = false
    init(checker: UpdateChecker) {
        self.checker = checker
        checker.noticeHandler = { [weak self] notice in self?.present(notice) }
    }
    private func present(_ notice: UpdateCheckNotice) {
        guard let checker, !presenting else { return }
        presenting = true
        let window = checker.noticeWindow
        let update = checker.availableUpdate
        Task { @MainActor in
            defer { presenting = false }
            // A check can finish while an Open dialog is still on screen.
            while NSApp.modalWindow != nil || window?.attachedSheet != nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "luma.language") ?? "") ?? .automatic
            let l = L10n(language: language)
            let alert = NSAlert()
            alert.messageText = l.text("update.check.title")
            switch notice {
            case .available:
                alert.informativeText = l.text("update.available", update?.version ?? "")
                alert.addButton(withTitle: l.text("button.downloadUpdate"))
                alert.addButton(withTitle: l.text("update.later"))
            case .upToDate:
                alert.informativeText = l.text("update.check.upToDate")
                alert.addButton(withTitle: l.text("button.ok"))
            case .unavailable:
                alert.informativeText = l.text("update.check.unavailable")
                alert.addButton(withTitle: l.text("button.ok"))
            }
            checker.dismissNotice()
            let response: NSApplication.ModalResponse
            if let window, window.isVisible {
                response = await withCheckedContinuation { continuation in
                    alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                }
            } else {
                response = alert.runModal()
            }
            if notice == .available, response == .alertFirstButtonReturn, let update { NSWorkspace.shared.open(update.downloadURL) }
        }
    }
}
