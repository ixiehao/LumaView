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
    private var isChecking = false
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

    func checkForUpdate(force: Bool = false, announceResult: Bool = false) async {
        guard !isChecking else { return }
        if !force,
           let lastCheckedAt,
           now().timeIntervalSince(lastCheckedAt) < Self.checkInterval { return }

        isChecking = true
        defer {
            let completedAt = now()
            lastCheckedAt = completedAt
            defaults.set(completedAt, forKey: lastCheckedDefaultsKey)
            isChecking = false
        }

        var request = URLRequest(url: releaseURL)
        request.timeoutInterval = 10
        request.setValue("LumaView update checker", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                if announceResult { notice = .unavailable }
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            availableUpdate = release.update(
                newerThan: currentVersion,
                expectedRepositoryPath: expectedRepositoryPath
            )
            if announceResult, availableUpdate == nil { notice = .upToDate }
        } catch {
            // Offline and transient API failures never interfere with viewing.
            if announceResult { notice = .unavailable }
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
        if let update = checker.availableUpdate {
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
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(Color.accentColor.opacity(0.09))
            .overlay(alignment: .bottom) { Divider().opacity(0.55) }
            .accessibilityElement(children: .contain)
        }
    }
}
