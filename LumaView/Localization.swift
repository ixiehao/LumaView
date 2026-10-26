import Foundation
import SwiftUI

/// An in-app language choice. It is deliberately independent of macOS so the
/// interface changes immediately and does not require a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case chinese
    case french
    case russian
    case spanish
    case japanese
    case korean
    case automatic

    var id: String { rawValue }

    static let requiredLocalizationKeys = [
        "menu.openNewWindows", "menu.keepStatusVisible", "preview.passwordRequired", "preview.fileTooLarge", "preview.unreadable", "preview.cannotDecode", "update.checking", "update.later", "defaults.otherCopy",
        "settings.general", "settings.defaultApplications", "defaults.description", "defaults.format", "defaults.extensions",
        "defaults.currentApplication", "defaults.none", "defaults.selectImages", "defaults.clear", "defaults.apply",
        "defaults.installFirst", "defaults.applied", "defaults.failed", "defaults.cancelled", "defaults.finderHint",
        "pdf.previousPage", "pdf.nextPage", "pdf.pagePosition", "pdf.printPage", "metadata.page", "metadata.pageSize",
        "app.appearance", "app.language", "language.automatic", "appearance.light", "appearance.dark",
        "settings.title", "settings.interface", "settings.updates", "settings.currentVersion", "settings.updatePrivacy",
        "about.menu", "about.description", "about.developer", "about.project", "about.feedback", "about.privacy", "about.license",
        "update.available", "update.about.available", "update.menu.available", "update.menu.check", "update.check.title", "update.check.upToDate", "update.check.unavailable", "button.downloadUpdate", "button.ok",
        "menu.browse", "menu.image", "menu.more", "menu.openImage", "menu.printImage", "menu.reveal",
        "system.menu.file", "system.menu.edit", "system.menu.view", "system.menu.window", "system.menu.help",
        "system.item.settings", "system.item.showTabBar", "system.item.hideTabBar", "system.item.showAllTabs",
        "system.item.about", "system.item.services", "system.item.hideApp", "system.item.hideOthers", "system.item.showAll", "system.item.quit",
        "system.item.close", "system.item.save", "system.item.duplicate", "system.item.rename", "system.item.moveTo", "system.item.exportPDF", "system.item.print",
        "system.item.undo", "system.item.redo", "system.item.cut", "system.item.copy", "system.item.paste", "system.item.pasteMatch", "system.item.delete", "system.item.selectAll", "system.item.dictation", "system.item.emoji",
        "system.item.enterFullScreen", "system.item.exitFullScreen", "system.item.showToolbar", "system.item.hideToolbar", "system.item.customizeToolbar", "system.item.minimize", "system.item.zoom", "system.item.bringAllToFront", "system.item.help",
        "button.openImage",
        "dialog.openImage.title", "dialog.openImage.action",
        "error.emptyFolder", "error.unsupportedFormat", "error.noPrintSelection", "error.printPreparation", "status.preparingPrint",
        "toolbar.previous", "toolbar.next", "toolbar.zoomOut", "toolbar.fit", "toolbar.zoomIn", "toolbar.rotateLeft", "toolbar.rotateRight", "toolbar.info", "toolbar.print",
        "command.previous", "command.next", "command.zoomIn", "command.zoomOut", "command.fit", "command.rotateLeft", "command.rotateRight",
        "canvas.drop", "canvas.noPreview",
        "metadata.title", "metadata.fileSection", "metadata.exifSection", "metadata.name", "metadata.format", "metadata.dimensions", "metadata.fileSize", "metadata.capturedAt", "metadata.camera", "metadata.lens", "metadata.exposure", "metadata.aperture", "metadata.iso", "metadata.focalLength", "metadata.noExif"
    ]

    var localizationCode: String? {
        switch self {
        case .automatic: nil
        case .chinese: "zh-Hans"
        case .english: "en"
        case .french: "fr"
        case .russian: "ru"
        case .spanish: "es"
        case .japanese: "ja"
        case .korean: "ko"
        }
    }

    var locale: Locale { Locale(identifier: resolvedLanguage.localizationCode ?? "en") }

    fileprivate var localizationBundle: Bundle {
        Self.localizationBundles[resolvedLanguage] ?? .module
    }

    private var resolvedLanguage: AppLanguage {
        self == .automatic ? Self.preferredLanguage(in: Locale.preferredLanguages) : self
    }

    /// Respect the user's full preference order, including regional variants.
    static func preferredLanguage(in preferences: [String]) -> AppLanguage {
        for preference in preferences {
            let base = preference.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if let language = allCases.first(where: {
                $0.localizationCode?.lowercased().split(separator: "-").first == base && $0 != .automatic
            }) { return language }
        }
        return .english
    }

    /// Like ShotTessera, resource bundles are cached once instead of being rebuilt for
    /// every SwiftUI body refresh. Every user-selectable language owns a real .lproj.
    private static let localizationBundles: [AppLanguage: Bundle] = Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.compactMap { language in
            guard let code = language.localizationCode else { return nil }
            guard let path = Bundle.module.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
            return (language, bundle)
        }
    )
}

/// Key-based localization with explicit format arguments. Missing strings deliberately
/// return their key, which lets the accompanying unit test catch gaps before release.
struct L10n {
    let language: AppLanguage

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = language.localizationBundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    func languageName(_ option: AppLanguage) -> String {
        switch option {
        case .automatic: text("language.automatic")
        case .chinese: "中文"
        case .english: "English"
        case .french: "Français"
        case .russian: "Русский"
        case .spanish: "Español"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }

    func appearanceName(_ option: AppAppearance) -> String {
        switch option {
        case .system: text("language.automatic")
        case .light: text("appearance.light")
        case .dark: text("appearance.dark")
        }
    }
}

/// Locates the resource bundle from both the app and its test host.
private final class LumaViewBundleToken {}

private extension Bundle {
    static var module: Bundle { Bundle(for: LumaViewBundleToken.self) }
}

/// Appearance is stored separately from language so people can keep their chosen
/// interface language while choosing the canvas and window contrast they prefer.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
