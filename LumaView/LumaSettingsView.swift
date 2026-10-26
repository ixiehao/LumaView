import AppKit
import SwiftUI

/// Keep navigation in the content view: Settings promotes a TabView to a
/// tall icon toolbar, even when its tabs only have text labels.
struct LumaSettingsView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @StateObject private var defaults = DefaultApplicationsModel()
    @AppStorage("luma.language") private var languageRaw = AppLanguage.automatic.rawValue
    @AppStorage("luma.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @State private var tab = 0

    init(updateChecker: UpdateChecker, defaultApplications: DefaultApplicationsModel? = nil, initialTab: Int = 0) {
        self.updateChecker = updateChecker
        _defaults = StateObject(wrappedValue: defaultApplications ?? DefaultApplicationsModel())
        _tab = State(initialValue: initialTab)
    }

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .automatic }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var l: L10n { L10n(language: language) }
    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var navigationWidth: CGFloat {
        let titles = ["settings.general", "settings.defaultApplications"]
        let width = titles.reduce(CGFloat(64)) { sum, key in
            sum + (l.text(key) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        }
        return max(260, width)
    }

    var body: some View {
        VStack(spacing: 24) {
            Picker(l.text("settings.title"), selection: $tab) {
                Text(l.text("settings.general")).tag(0)
                Text(l.text("settings.defaultApplications")).tag(1)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: navigationWidth)
            .accessibilityIdentifier("settings.navigation")

            if tab == 0 {
                generalSettings
            } else {
                DefaultApplicationsPane(model: defaults, l: l)
            }
        }
        .padding(24)
        .frame(width: 560, height: tab == 0 ? (updateChecker.hasUpdate ? 320 : 280) : 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.locale, language.locale)
        .navigationTitle(l.text("settings.title"))

    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 14) {
                row("app.appearance") {
                    Picker(l.text("app.appearance"), selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(l.appearanceName(option)).tag(option.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .accessibilityIdentifier("settings.appearance")
                }
                row("app.language") {
                    Picker(l.text("app.language"), selection: $languageRaw) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(l.languageName(option)).tag(option.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .accessibilityIdentifier("settings.language")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(l.text("settings.currentVersion"))
                    Text(installedVersion).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    if updateChecker.isChecking { ProgressView().controlSize(.small) }
                    Button(l.text(updateChecker.isChecking ? "update.checking" : "update.menu.check")) {
                        Task { await updateChecker.checkForUpdate(force: true, announceResult: true) }
                    }
                    .accessibilityIdentifier("settings.checkForUpdates")
                }
                if let update = updateChecker.availableUpdate {
                    HStack {
                        Text(l.text("update.available", update.version))
                        Spacer(minLength: 12)
                        Button(l.text("button.downloadUpdate")) { updateChecker.openDownloadPage() }
                    }
                }
                Text(l.text("settings.updatePrivacy"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func row<Control: View>(_ key: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 20) {
            Text(l.text(key))
            Spacer(minLength: 0)
            control().frame(width: 220, alignment: .trailing)
        }
        .frame(minHeight: 28)
    }


}

struct DefaultApplicationsPane: View {
    @ObservedObject var model: DefaultApplicationsModel
    let l: L10n

    private let formatWidth: CGFloat = 88
    private let extensionWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l.text("defaults.description"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                columns {
                    Text(l.text("defaults.format")).frame(width: formatWidth, alignment: .leading)
                    Text(l.text("defaults.extensions")).frame(width: extensionWidth, alignment: .leading)
                    Text(l.text("defaults.currentApplication"))
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(height: 28)
                .background(Color(nsColor: .windowBackgroundColor))
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(DefaultImageFormat.common.enumerated()), id: \.element.id) { index, format in
                            columns {
                                Toggle(format.name, isOn: Binding(
                                    get: { model.isDefault(format) || model.selected.contains(format.id) },
                                    set: { model.select(format, enabled: $0) }
                                ))
                                .toggleStyle(.checkbox)
                                .disabled(model.isApplying || model.isDefault(format))
                                .frame(width: formatWidth, alignment: .leading)
                                .accessibilityIdentifier("defaults.format.\(format.name)")
                                Text(format.extensions)
                                    .foregroundStyle(.secondary)
                                    .frame(width: extensionWidth, alignment: .leading)
                                Text(model.isAnotherCopy(format) ? l.text("defaults.otherCopy", model.applicationName(for: format) ?? "LumaView") : (model.applicationName(for: format) ?? l.text("defaults.none")))
                                    .lineLimit(1).truncationMode(.middle)
                                    .help(model.applicationDetails(for: format) ?? l.text("defaults.none"))
                            }
                            .frame(height: 28)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                        }
                    }
                }
                .accessibilityIdentifier("defaults.formats")
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))

            HStack(spacing: 16) {
                Button(l.text("defaults.selectImages")) { model.selectAllImages() }
                    .disabled(model.isApplying)
                Button(l.text("defaults.clear")) { model.clearSelection() }
                    .disabled(model.isApplying || model.selected.isEmpty)
                Spacer(minLength: 0)
            }
            .buttonStyle(.link)
            .font(.caption)

            if !model.isInstalled {
                status(l.text("defaults.installFirst"))
            }
            if let result = model.result {
                VStack(alignment: .leading, spacing: 4) {
                    if result.appliedCount > 0 { Text(l.text("defaults.applied", result.appliedCount)) }
                    if !result.failedFormats.isEmpty {
                        Text(l.text("defaults.failed", result.failedFormats.joined(separator: ", ")))
                    }
                    if result.cancelled { Text(l.text("defaults.cancelled")) }
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("defaults.result")
            }

            HStack(alignment: .center, spacing: 20) {
                status(l.text("defaults.finderHint"))
                Spacer(minLength: 0)
                if model.isApplying { ProgressView().controlSize(.small) }
                Button(l.text("defaults.apply")) { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.isInstalled || model.isApplying || model.selected.isEmpty)
                    .fixedSize()
                    .accessibilityIdentifier("defaults.apply")
            }
            .padding(.top, 4)
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private func columns<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private func status(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
