import AppKit
import Combine
import SwiftUI

private enum AboutCredits {
    static func make(l: L10n, availableUpdate: AvailableUpdate?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 5

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.linkColor,
            .paragraphStyle: paragraph,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let credits = NSMutableAttributedString()

        func appendBody(_ text: String) {
            credits.append(NSAttributedString(string: text, attributes: bodyAttributes))
        }

        func appendLink(_ text: String, destination: URL) {
            var attributes = linkAttributes
            attributes[.link] = destination
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }

        appendBody("\(l.text("about.description"))\n\n")
        appendBody("\(l.text("about.developer")) · ixiehao\n")
        appendLink("github.com/\(LumaViewProjectLinks.repositorySlug)\n", destination: LumaViewProjectLinks.repository)
        appendLink(l.text("about.feedback"), destination: LumaViewProjectLinks.issues)
        if let availableUpdate {
            appendBody("\n\n\(l.text("update.about.available", availableUpdate.version))\n")
            appendLink(l.text("button.downloadUpdate"), destination: availableUpdate.downloadURL)
        }
        appendBody("\n\n\(l.text("about.privacy"))\n\(l.text("about.license"))")
        return credits
    }
}

/// SwiftUI updates the app's own CommandMenu labels when `luma.language`
/// changes. AppKit owns File, Edit, the system View menu, Window and Help, so
/// their top-level labels must be updated explicitly as well. This keeps the
/// complete menu bar in the language selected inside LumaView rather than
/// leaving a mixed-language macOS menu.
@MainActor
enum MainMenuLocalization {
    private static var pendingUpdate: DispatchWorkItem?
    private static var menuObservers: [NSObjectProtocol] = []
    private static var currentLocalization = L10n(language: .automatic)
    private static var isApplying = false
    private static let leadingSystemMenus: [(index: Int, key: String)] = [
        (1, "system.menu.file"),
        (2, "system.menu.edit"),
        (3, "system.menu.view")
    ]

    private static let trailingSystemMenus: [(titles: Set<String>, key: String)] = [
        (["Window", "窗口", "ウインドウ"], "system.menu.window"),
        (["Help", "帮助", "ヘルプ"], "system.menu.help")
    ]

    // When macOS itself uses a third language, the AppKit-generated titles do
    // not match either LumaView translation.  Selectors are stable across system
    // languages, so use them as the primary identity and keep titles as a legacy
    // fallback for menu items without actions.
    private static let standardItemActionKeys: [String: String] = [
        "orderFrontStandardAboutPanel:": "system.item.about",
        "showSettingsWindow:": "system.item.settings",
        "showPreferencesWindow:": "system.item.settings",
        "toggleTabOverview:": "system.item.showAllTabs",
        "hide:": "system.item.hideApp",
        "hideOtherApplications:": "system.item.hideOthers",
        "unhideAllApplications:": "system.item.showAll",
        "terminate:": "system.item.quit",
        "performClose:": "system.item.close",
        "saveDocument:": "system.item.save",
        "duplicateDocument:": "system.item.duplicate",
        "rename:": "system.item.rename",
        "moveTo:": "system.item.moveTo",
        "exportAsPDF:": "system.item.exportPDF",
        "printDocument:": "system.item.print",
        "undo:": "system.item.undo",
        "redo:": "system.item.redo",
        "cut:": "system.item.cut",
        "copy:": "system.item.copy",
        "paste:": "system.item.paste",
        "pasteAsPlainText:": "system.item.pasteMatch",
        "delete:": "system.item.delete",
        "selectAll:": "system.item.selectAll",
        "startDictation:": "system.item.dictation",
        "orderFrontCharacterPalette:": "system.item.emoji",
        "toggleToolbarShown:": "system.item.showToolbar",
        "runToolbarCustomizationPalette:": "system.item.customizeToolbar",
        "performMiniaturize:": "system.item.minimize",
        "performZoom:": "system.item.zoom",
        "arrangeInFront:": "system.item.bringAllToFront",
        "showHelp:": "system.item.help"
    ]

    private static let trailingMenuActionKeys: [(actions: Set<String>, key: String)] = [
        (["performMiniaturize:", "performZoom:", "arrangeInFront:"], "system.menu.window"),
        (["showHelp:"], "system.menu.help")
    ]

    // System command groups are constructed by AppKit in the macOS language, not
    // by SwiftUI's app-local localization bundle. Translate the visible standard
    // items too so switching languages never leaves a mixed menu hierarchy.
    private static let standardItems: [(titles: Set<String>, key: String)] = [
        (["Settings…", "Preferences…", "设置…", "偏好设置…", "設定…", "環境設定…"], "system.item.settings"),
        (["Show Tab Bar", "显示标签页栏", "タブバーを表示"], "system.item.showTabBar"),
        (["Hide Tab Bar", "隐藏标签页栏", "タブバーを非表示"], "system.item.hideTabBar"),
        (["Show All Tabs", "显示所有标签页", "すべてのタブを表示"], "system.item.showAllTabs"),
        (["About LumaView", "关于 LumaView", "LumaViewについて"], "system.item.about"),
        (["Services", "服务", "サービス"], "system.item.services"),
        (["Hide LumaView", "隐藏 LumaView", "LumaViewを隠す"], "system.item.hideApp"),
        (["Hide Others", "隐藏其他", "ほかを隠す"], "system.item.hideOthers"),
        (["Show All", "显示全部", "すべてを表示"], "system.item.showAll"),
        (["Quit LumaView", "退出 LumaView", "LumaViewを終了"], "system.item.quit"),
        (["Close", "关闭", "閉じる"], "system.item.close"),
        (["Save", "存储", "保存"], "system.item.save"),
        (["Duplicate", "复制", "複製"], "system.item.duplicate"),
        (["Rename…", "重命名…", "名前を変更…"], "system.item.rename"),
        (["Move To…", "移动到…", "移動…"], "system.item.moveTo"),
        (["Export as PDF…", "导出为 PDF…", "PDFとして書き出す…"], "system.item.exportPDF"),
        (["Print…", "打印…", "プリント…"], "system.item.print"),
        (["Undo", "撤销", "取り消す"], "system.item.undo"),
        (["Redo", "重做", "やり直す"], "system.item.redo"),
        (["Cut", "剪切", "カット"], "system.item.cut"),
        (["Copy", "拷贝", "コピー"], "system.item.copy"),
        (["Paste", "粘贴", "ペースト"], "system.item.paste"),
        (["Paste and Match Style", "粘贴并匹配样式", "ペーストしてスタイルを合わせる"], "system.item.pasteMatch"),
        (["Delete", "删除", "削除"], "system.item.delete"),
        (["Select All", "全选", "すべてを選択"], "system.item.selectAll"),
        (["Start Dictation…", "开始听写…", "音声入力を開始…"], "system.item.dictation"),
        (["Emoji & Symbols", "表情与符号", "絵文字と記号"], "system.item.emoji"),
        (["Enter Full Screen", "进入全屏幕", "フルスクリーンにする"], "system.item.enterFullScreen"),
        (["Exit Full Screen", "退出全屏幕", "フルスクリーンを解除"], "system.item.exitFullScreen"),
        (["Show Toolbar", "显示工具栏", "ツールバーを表示"], "system.item.showToolbar"),
        (["Hide Toolbar", "隐藏工具栏", "ツールバーを隠す"], "system.item.hideToolbar"),
        (["Customize Toolbar…", "自定工具栏…", "ツールバーをカスタマイズ…"], "system.item.customizeToolbar"),
        (["Minimize", "最小化", "しまう"], "system.item.minimize"),
        (["Zoom", "缩放", "拡大/縮小"], "system.item.zoom"),
        (["Bring All to Front", "全部置于最前", "すべてを手前に移動"], "system.item.bringAllToFront"),
        (["LumaView Help", "LumaView 帮助", "LumaViewヘルプ"], "system.item.help")
    ]

    static func applyToMainMenu(_ l: L10n) {
        currentLocalization = l
        if menuObservers.isEmpty {
            // SwiftUI may rebuild native menus after an AppStorage change.
            // React to that rebuild rather than polling or replacing its delegate.
            menuObservers = [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                    MainActor.assumeIsolated { menuDidChange(notification) }
                }
            }
        }
        scheduleUpdate()
    }

    private static func menuDidChange(_ notification: Notification) {
        guard !isApplying, let menu = notification.object as? NSMenu,
              let mainMenu = NSApp?.mainMenu else { return }
        var root = menu
        while let parent = root.supermenu { root = parent }
        guard root === mainMenu else { return }
        if menu !== mainMenu,
           let index = notification.userInfo?["NSMenuItemIndex"] as? Int,
           menu.items.indices.contains(index) {
            let item = menu.items[index]
            let action = item.action.map(NSStringFromSelector)
            let key = action.flatMap { standardItemActionKeys[$0] } ?? standardItemKeysByTitle[item.title]
            // Enabled/checked changes need no translation. A native full-screen
            // item is removed because our SwiftUI command already owns it.
            if action != "toggleFullScreen:", item.submenu == nil,
               key.map({ item.title == currentLocalization.text($0) }) ?? true { return }
        }
        scheduleUpdate()
    }

    private static func scheduleUpdate() {
        guard pendingUpdate == nil else { return }
        let update = DispatchWorkItem {
            defer { pendingUpdate = nil }
            guard let menu = NSApp?.mainMenu else { return }
            isApplying = true
            defer { isApplying = false }
            removeNativeFullScreenItems(in: menu)
            apply(currentLocalization, to: menu)
        }
        pendingUpdate = update
        DispatchQueue.main.async(execute: update)
    }

    private static func removeNativeFullScreenItems(in menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(NSWindow.toggleFullScreen(_:)) {
                menu.removeItem(item)
            } else if let submenu = item.submenu {
                removeNativeFullScreenItems(in: submenu)
            }
        }
    }

    // Some native items (for example Services) have no action selector. Match
    // every supported translation so repeated language changes remain reversible.
    private static let standardItemKeysByTitle: [String: String] = {
        var result: [String: String] = [:]
        for item in standardItems {
            for title in item.titles { result[title] = item.key }
            for language in AppLanguage.allCases where language != .automatic {
                result[L10n(language: language).text(item.key)] = item.key
            }
        }
        return result
    }()

    static func apply(_ l: L10n, to menu: NSMenu) {
        // The first four menus are always application, File, Edit and the
        // system View menu. Indexing them prevents the application's separate
        // image View menu from being renamed as the system menu during a
        // language switch.
        for menuInfo in leadingSystemMenus where menu.items.indices.contains(menuInfo.index) {
            setTitle(l.text(menuInfo.key), for: menu.items[menuInfo.index])
        }

        // Window and Help remain at the trailing edge, after LumaView's custom
        // Browse, View, Appearance and Language menus.
        for menuInfo in trailingSystemMenus {
            let actionSet = trailingMenuActionKeys.first(where: { $0.key == menuInfo.key })?.actions ?? []
            if let item = menu.items.reversed().first(where: {
                menuInfo.titles.contains($0.title) || submenu($0.submenu, containsAnyAction: actionSet)
            }) {
                setTitle(l.text(menuInfo.key), for: item)
            }
        }
        localizeStandardItems(in: menu, localization: l)
    }

    private static func setTitle(_ title: String, for item: NSMenuItem) {
        // SwiftUI's standard CommandGroups retain a menu title separately from
        // their parent menu item. Updating both is necessary for the title
        // rendered in the macOS menu bar and for the opened submenu header.
        if item.title != title { item.title = title }
        if let submenu = item.submenu, submenu.title != title { submenu.title = title }
    }

    private static func localizeStandardItems(in menu: NSMenu, localization: L10n) {
        for item in menu.items {
            let titleKey = standardItemKeysByTitle[item.title]
            let actionName = item.action.map(NSStringFromSelector)
            let actionKey: String?
            if actionName == "toggleFullScreen:" {
                // One selector handles both directions. Derive its title from
                // the target window, so relocalizing cannot turn Exit into Enter.
                let window = (item.target as? NSWindow) ?? NSApp?.keyWindow ?? NSApp?.mainWindow
                actionKey = window.map {
                    $0.styleMask.contains(.fullScreen) ? "system.item.exitFullScreen" : "system.item.enterFullScreen"
                } ?? titleKey ?? "system.item.enterFullScreen"
            } else {
                actionKey = actionName.flatMap { standardItemActionKeys[$0] }
            }
            if let key = actionKey ?? titleKey {
                let title = localization.text(key)
                if item.title != title { item.title = title }
            }
            if let submenu = item.submenu {
                localizeStandardItems(in: submenu, localization: localization)
            }
        }
    }

    private static func submenu(_ menu: NSMenu?, containsAnyAction actions: Set<String>) -> Bool {
        guard !actions.isEmpty, let menu else { return false }
        for item in menu.items {
            if let action = item.action, actions.contains(NSStringFromSelector(action)) {
                return true
            }
            if submenu(item.submenu, containsAnyAction: actions) { return true }
        }
        return false
    }
}

/// Normalises file-open events before they reach the window registry.  Keeping
/// this independent of `NSApplicationDelegate` makes the LaunchServices paths
/// testable without fabricating an Apple event in an XCTest process.
enum ExternalDocumentOpenRoute {
    static func acceptedURLs(from urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls
            .filter(\.isFileURL)
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .filter(ImageFile.canOpen)
            .filter { seen.insert($0).inserted }
    }
}

/// Buffers Finder / LaunchServices document events until AppKit has completed
/// launching, then delivers them to the real window registry.  A late event is
/// delivered immediately, which lets the registry adopt a pending welcome
/// window instead of creating a blank companion window.
@MainActor
final class ExternalDocumentOpenRouter {
    private let deliver: ([URL]) -> Void
    private var pendingURLs: [URL] = []
    private(set) var hasFinishedLaunching = false
    private(set) var hasAcceptedDocument = false

    init(deliver: @escaping ([URL]) -> Void) {
        self.deliver = deliver
    }

    @discardableResult
    func receive(_ urls: [URL]) -> Bool {
        let accepted = ExternalDocumentOpenRoute.acceptedURLs(from: urls)
        guard !accepted.isEmpty else { return false }
        hasAcceptedDocument = true
        if hasFinishedLaunching {
            deliver(accepted)
        } else {
            pendingURLs.append(contentsOf: accepted)
        }
        return true
    }

    /// Returns the launch batch so the delegate can decide whether to schedule
    /// the welcome window.  The batch is also delivered here; callers must not
    /// deliver it a second time.
    @discardableResult
    func finishLaunching(alsoOpening urls: [URL] = []) -> [URL] {
        guard !hasFinishedLaunching else { return [] }
        hasFinishedLaunching = true
        let accepted = ExternalDocumentOpenRoute.acceptedURLs(from: pendingURLs + urls)
        pendingURLs.removeAll()
        if !accepted.isEmpty {
            hasAcceptedDocument = true
            deliver(accepted)
        }
        return accepted
    }
}

@MainActor
final class LumaViewAppDelegate: NSObject, NSApplicationDelegate {
    private lazy var documentRouter = ExternalDocumentOpenRouter { urls in
        LumaViewWindowRegistry.shared.openDocumentWindows(for: urls)
    }
    private var welcomeWindowWorkItem: DispatchWorkItem?

    func application(_ application: NSApplication, open urls: [URL]) {
        _ = documentRouter.receive(urls)
    }

    // LaunchServices still uses this classic callback for some Finder and
    // Apple-event paths. Reply explicitly: without it, Finder can keep waiting
    // for an answer even though LumaView has already accepted the document.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let accepted = documentRouter.receive(filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: accepted ? .success : .failure)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        documentRouter.receive([URL(fileURLWithPath: filename)])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI tests exercise the same AppKit document-window route as Finder without
        // driving an NSOpenPanel or depending on a developer's Desktop. This input is
        // intentionally inert unless an XCTest process supplies an existing local file.
        // Some LaunchServices paths deliver their document Apple event one
        // turn after didFinishLaunching.  Defer the welcome decision briefly;
        // if an event arrives later still, the registry converts that empty
        // welcome window into the document window instead of flashing a second
        // blank one.
        if documentRouter.finishLaunching(alsoOpening: uiTestDocumentURLs()).isEmpty {
            scheduleWelcomeWindow()
        }
        localizeSystemMenus(selectedLocalization)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            welcomeWindowWorkItem?.cancel()
            LumaViewWindowRegistry.shared.openWelcomeWindow()
        }
        return true
    }

    func showAboutPanel(l: L10n, updateChecker: UpdateChecker) {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: AboutCredits.make(l: l, availableUpdate: updateChecker.availableUpdate)
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func localizeSystemMenus(_ l: L10n) {
        MainMenuLocalization.applyToMainMenu(l)
    }

    private var selectedLocalization: L10n {
        let rawValue = UserDefaults.standard.string(forKey: "luma.language") ?? AppLanguage.automatic.rawValue
        return L10n(language: AppLanguage(rawValue: rawValue) ?? .automatic)
    }

    @objc private func userDefaultsDidChange() {
        let localization = selectedLocalization
        localizeSystemMenus(localization)
        LumaViewWindowRegistry.shared.applyWindowPreferences(
            localization: localization,
            appearance: selectedAppearance
        )
    }

    private var selectedAppearance: AppAppearance {
        let rawValue = UserDefaults.standard.string(forKey: "luma.appearance") ?? AppAppearance.system.rawValue
        return AppAppearance(rawValue: rawValue) ?? .system
    }

    private func scheduleWelcomeWindow() {
        welcomeWindowWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.documentRouter.hasAcceptedDocument else { return }
            LumaViewWindowRegistry.shared.openWelcomeWindow()
        }
        welcomeWindowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: workItem)
    }

    /// Test-only document input follows the same document-router path as Finder.
    /// It deliberately accepts one URL: focused UI tests should exercise the
    /// production route, not a second multi-window launch mode.
    private func uiTestDocumentURLs() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LUMAVIEW_UI_TEST_OPEN_FILE"] else { return [] }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        return ImageFile.canOpen(url) ? [url] : []
    }
}

/// Determines a comfortable, image-led content size without allowing a large
/// source file to cover menu-bar or Dock space. The result always preserves the
/// image aspect ratio, so a portrait opens as a portrait window and a panorama
/// opens wide instead of inheriting a fixed application rectangle.
enum ImageWindowSizing {
    /// The AppKit window must use the same discrete state as the canvas.  This
    /// bridge deliberately treats the viewer as a right-angle viewer rather
    /// than reintroducing trigonometry in the window layer.
    static func quarterTurn(for degrees: Double) -> QuarterTurn {
        QuarterTurn.zero.rotated(by: degrees)
    }

    /// Returns the bounding size the canvas needs after a viewport rotation.
    /// Keeping this calculation next to window sizing ensures a 90° rotation
    /// reshapes the document window just like browsing to a differently-shaped
    /// image does.
    static func displayedPixelSize(for imageSize: CGSize, rotatedBy degrees: Double) -> CGSize? {
        displayedPixelSize(for: imageSize, quarterTurn: quarterTurn(for: degrees))
    }

    static func displayedPixelSize(for imageSize: CGSize, quarterTurn: QuarterTurn) -> CGSize? {
        ViewerGeometry.displayedSize(for: imageSize, rotation: quarterTurn)
    }

    /// Window sizing only depends on whether the image is in its original or
    /// quarter-turned orientation.  A 180° turn keeps the same canvas bounds,
    /// so it must not needlessly reset the user's centered window.
    static func orientationKey(for rotation: Double) -> Bool {
        quarterTurn(for: rotation).swapsAxes
    }

    static func orientationKey(for quarterTurn: QuarterTurn) -> Bool {
        quarterTurn.swapsAxes
    }

    static func initialContentSize(for imageSize: CGSize, maximumContentSize: CGSize) -> CGSize? {
        guard imageSize.width > 0,
              imageSize.height > 0,
              maximumContentSize.width > 0,
              maximumContentSize.height > 0 else { return nil }

        let maximumScale = min(
            maximumContentSize.width / imageSize.width,
            maximumContentSize.height / imageSize.height
        )
        guard maximumScale.isFinite, maximumScale > 0 else { return nil }

        // Small web images should not create unusably tiny windows; source-size
        // images and large photos are instead shown at their natural or capped
        // screen-filling size. The 1.6 ceiling avoids visibly soft enlargement.
        let longSide = max(imageSize.width, imageSize.height)
        let readableScale = min(1.6, max(1, 680 / longSide))
        let scale = min(maximumScale, readableScale)
        return CGSize(
            width: (imageSize.width * scale).rounded(),
            height: (imageSize.height * scale).rounded()
        )
    }

    /// Enlarges a comfortable image-led size only when both dimensions can stay
    /// inside the visible screen. Scaling as one unit preserves the source aspect
    /// ratio; callers may lower the AppKit minimum for extreme portraits/panoramas.
    static func aspectPreservingContentSize(
        preferred: CGSize,
        minimum: CGSize,
        maximum: CGSize
    ) -> CGSize? {
        guard preferred.width > 0, preferred.height > 0,
              maximum.width > 0, maximum.height > 0 else { return nil }
        let scaleForMinimum = max(
            1,
            minimum.width / preferred.width,
            minimum.height / preferred.height
        )
        let scaleForMaximum = min(
            maximum.width / preferred.width,
            maximum.height / preferred.height
        )
        let scale = min(scaleForMinimum, scaleForMaximum)
        guard scale.isFinite, scale > 0 else { return nil }
        return CGSize(width: (preferred.width * scale).rounded(), height: (preferred.height * scale).rounded())
    }

    /// Builds a frame that is centered in the usable screen area and never
    /// extends past it, even if a screen changes while the app is launching.
    static func centeredFrame(for frameSize: CGSize, in visibleFrame: NSRect) -> NSRect {
        let width = min(max(frameSize.width, 1), visibleFrame.width)
        let height = min(max(frameSize.height, 1), visibleFrame.height)
        return NSRect(
            x: (visibleFrame.midX - width / 2).rounded(),
            y: (visibleFrame.midY - height / 2).rounded(),
            width: width,
            height: height
        )
    }

    /// Preserve a person's current window position while changing the content
    /// aspect.  Initial windows are already centered, while subsequent browse
    /// and rotate operations should not jump back to the middle of the screen.
    static func frame(
        with size: CGSize,
        centeredAt center: CGPoint,
        constrainedTo visibleFrame: NSRect
    ) -> NSRect {
        let width = min(max(size.width, 1), visibleFrame.width)
        let height = min(max(size.height, 1), visibleFrame.height)
        let ideal = NSRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        return NSRect(
            x: min(max(ideal.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(ideal.minY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }
}

/// All visible viewer controls ultimately resolve to one controller: the key
/// document window.  This is intentionally not an application-wide "active"
/// fallback.  A command without a key LumaView document is disabled instead
/// of mutating an arbitrary background window.
fileprivate enum ViewerCommand {
    case open
    case toggleFullScreen
    case previous
    case next
    case zoomOut
    case fit
    case zoomIn
    case rotateLeft
    case rotateRight
    case revealInFinder
    case print
}

/// Owns real AppKit document windows. A SwiftUI WindowGroup is intentionally
/// not used for files: its unbound launch scene was the source of the blank
/// window and visible flash reported when Finder opened an image.
@MainActor
final class LumaViewWindowRegistry: ObservableObject {
    static let shared = LumaViewWindowRegistry()

    let updateChecker = UpdateChecker()
    @Published private(set) var activeBrowser: ImageBrowserStore?

    private var controllers: [ObjectIdentifier: LumaViewWindowController] = [:]
    private var activeBrowserObserver: AnyCancellable?

    func openWelcomeWindow() {
        // Reuse even a temporarily hidden/minimised welcome controller. Keeping one
        // owner avoids a later Finder event adopting a different empty window and
        // leaving an unexpected blank window behind.
        if let existing = controllers.values.first(where: { $0.canBecomeDocumentWindow }) {
            existing.showAndFocus()
            return
        }
        makeWindow(documentURL: nil).showAndFocus()
    }

    func openDocumentWindow(for url: URL) {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        // A browser window's current selection is its document identity. Its original
        // Finder URL can be stale after previous/next navigation, so never focus a
        // window merely because it was initially opened for this file.
        if let existing = controllers.values.first(where: { $0.browser.selectedURL == canonicalURL }) {
            existing.showAndFocus()
            return
        }
        if let welcome = controllers.values.first(where: { $0.canBecomeDocumentWindow }) {
            welcome.adopt(documentURL: canonicalURL)
            welcome.showAndFocus()
            return
        }
        makeWindow(documentURL: canonicalURL).showAndFocus()
    }

    func openDocumentWindows(for urls: [URL]) {
        var seen = Set<URL>()
        for url in urls where seen.insert(url.standardizedFileURL.resolvingSymlinksInPath()).inserted {
            openDocumentWindow(for: url)
        }
    }

    func applyWindowPreferences(localization: L10n, appearance: AppAppearance) {
        controllers.values.forEach {
            $0.applyWindowPreferences(localization: localization, appearance: appearance)
        }
    }

    fileprivate func activate(_ browser: ImageBrowserStore) {
        objectWillChange.send()
        guard activeBrowser !== browser else { return }
        activeBrowserObserver?.cancel()
        activeBrowser = browser
        // SwiftUI CommandMenu reads activeBrowser's properties. Forward its changes
        // through the registry so menu validation and keyboard shortcuts follow the
        // focused window immediately after opening, scanning or printing an image.
        activeBrowserObserver = browser.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
    }

    private var commandDocumentController: LumaViewWindowController? {
        // Opening the menu bar can briefly clear `keyWindow` on some macOS
        // releases. Fall back to `mainWindow` only during that interval; an
        // unrelated key window (Settings/About) must not edit a background image.
        // SwiftUI may validate Commands before AppKit has assigned NSApp,
        // especially when XCTest launches the application on a fresh runner.
        guard !hasBlockingModalPresentation, let application = NSApp else { return nil }
        guard let candidate = application.keyWindow ?? application.mainWindow else { return nil }
        return controllers.values.first(where: { $0.acceptsCommands(from: candidate) })
    }

    fileprivate var isFullScreen: Bool {
        commandDocumentController?.window?.styleMask.contains(.fullScreen) == true
    }

    private var hasBlockingModalPresentation: Bool {
        guard let application = NSApp else { return false }
        let candidate = application.keyWindow ?? application.mainWindow
        return application.modalWindow != nil || candidate?.sheetParent != nil || candidate?.attachedSheet != nil
    }

    fileprivate func perform(_ command: ViewerCommand, localization: L10n) {
        guard canPerform(command) else { return }
        if case .open = command, commandDocumentController == nil {
            openWelcomeWindow()
        }
        commandDocumentController?.perform(command, localization: localization)
    }

    fileprivate func canPerform(_ command: ViewerCommand) -> Bool {
        if case .open = command { return !hasBlockingModalPresentation }
        return commandDocumentController?.canPerform(command) ?? false
    }

    fileprivate func remove(_ controller: LumaViewWindowController) {
        let identifier = ObjectIdentifier(controller)
        controllers.removeValue(forKey: identifier)
        if activeBrowser === controller.browser {
            let nextBrowser = controllers.values.first(where: { $0.window?.isKeyWindow == true })?.browser
            activeBrowserObserver?.cancel()
            activeBrowserObserver = nil
            activeBrowser = nil
            if let nextBrowser {
                activate(nextBrowser)
            }
        }
    }

    private func makeWindow(documentURL: URL?) -> LumaViewWindowController {
        let controller = LumaViewWindowController(documentURL: documentURL, updateChecker: updateChecker)
        let identifier = ObjectIdentifier(controller)
        controllers[identifier] = controller
        return controller
    }

}

private enum LumaViewToolbarIdentifier {
    static let previous = NSToolbarItem.Identifier("com.lumaview.toolbar.previous")
    static let next = NSToolbarItem.Identifier("com.lumaview.toolbar.next")
    static let zoomOut = NSToolbarItem.Identifier("com.lumaview.toolbar.zoom-out")
    static let fit = NSToolbarItem.Identifier("com.lumaview.toolbar.fit")
    static let zoomIn = NSToolbarItem.Identifier("com.lumaview.toolbar.zoom-in")
    static let rotateLeft = NSToolbarItem.Identifier("com.lumaview.toolbar.rotate-left")
    static let rotateRight = NSToolbarItem.Identifier("com.lumaview.toolbar.rotate-right")
    static let information = NSToolbarItem.Identifier("com.lumaview.toolbar.information")

    static let defaultItems: [NSToolbarItem.Identifier] = [
        .flexibleSpace,
        previous,
        next,
        .space,
        zoomOut,
        fit,
        zoomIn,
        .space,
        rotateLeft,
        rotateRight,
        .space,
        information
    ]
}

@MainActor
private final class LumaViewWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let browser = ImageBrowserStore()
    private(set) var documentURL: URL?

    private var browserChangeObserver: AnyCancellable?
    private var informationSelectionObserver: AnyCancellable?
    private var pixelSizeObserver: AnyCancellable?
    private var quarterTurnObserver: AnyCancellable?
    private var informationPopover: NSPopover?
    private var informationPopoverDocumentURL: URL?
    private var informationOperation: Operation?
    private var informationRequestedURL: URL?
    /// The current document whose image-led frame has been applied.  This is
    /// intentionally per selection, not per window: browsing from a landscape
    /// to a portrait must reshape the same window before the new canvas draws.
    private var sizedDocumentURL: URL?
    private var sizedDocumentOrientation: Bool?
    private var isFullScreenTransitionInProgress = false
    private let authoredMinimumContentSize = NSSize(width: 560, height: 380)

    init(documentURL: URL?, updateChecker: UpdateChecker) {
        self.documentURL = documentURL

        let contentSize = NSSize(width: 700, height: 480)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            // The image canvas must begin below the unified toolbar. With
            // fullSizeContentView, AppKit counts the titlebar in contentRect
            // while SwiftUI excludes it from its drawable area, producing
            // equal white rails beside square and portrait images.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.minSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: authoredMinimumContentSize)
        ).size
        window.contentViewController = NSHostingController(
            rootView: ContentView(
                browser: browser,
                updateChecker: updateChecker,
                windowAccessibilityIdentifier: documentURL?.lastPathComponent
            )
        )

        super.init(window: window)
        window.delegate = self
        window.toolbar = makeToolbar()
        addBrandTitlebarAccessory(to: window)
        applyWindowPreferences(
            localization: Self.currentLocalization,
            appearance: Self.currentAppearance
        )
        // Assigning a custom toolbar can make AppKit query SwiftUI's temporary
        // fitting size (which is near zero before the canvas is laid out). Reset
        // the authored welcome size after toolbar assembly so a cold launch can
        // never collapse into a narrow vertical window.
        window.setContentSize(contentSize)
        window.center()

        browserChangeObserver = browser.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshTitle()
                self.window?.toolbar?.validateVisibleItems()
            }
        }
        // Observe the emitted selection, not a later objectWillChange callback:
        // rapid A → B → A navigation must still cancel A's pending inspector.
        informationSelectionObserver = browser.$selectedIndex
            .combineLatest(browser.$files)
            .map { index, files -> URL? in
                guard let index, files.indices.contains(index) else { return nil }
                return files[index].url
            }
            .removeDuplicates()
            .sink { [weak self] selectedURL in
                self?.dismissInformationPopover(unlessShowing: selectedURL)
            }
        pixelSizeObserver = browser.$originalPixelSize
            .compactMap { $0 }
            .sink { [weak self] size in
                guard let self, let selectedURL = self.browser.selectedURL else { return }
                self.applyDocumentSize(
                    for: size,
                    documentURL: selectedURL,
                    quarterTurn: self.browser.quarterTurn
                )
            }
        quarterTurnObserver = browser.$quarterTurn
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] quarterTurn in
                guard let self,
                      let pixelSize = self.browser.originalPixelSize,
                      let selectedURL = self.browser.selectedURL else { return }
                self.applyDocumentSize(for: pixelSize, documentURL: selectedURL, quarterTurn: quarterTurn)
            }

        if let documentURL {
            browser.open(url: documentURL, l: Self.currentLocalization)
        }
        refreshTitle()
        // XCTest supplies this flag so UI coverage stays offline, deterministic and
        // independent of GitHub availability. Normal launches retain the update check.
        if ProcessInfo.processInfo.environment["LUMAVIEW_DISABLE_UPDATE_CHECK"] != "1" {
            Task { await updateChecker.checkForUpdate() }
        }
    }

    required init?(coder: NSCoder) { nil }

    func showAndFocus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        browser.resumeCanvasRendering()
        NSApplication.shared.activate(ignoringOtherApps: true)
        LumaViewWindowRegistry.shared.activate(browser)
    }

    var canBecomeDocumentWindow: Bool {
        documentURL == nil && browser.selectedURL == nil
    }

    func adopt(documentURL: URL) {
        guard canBecomeDocumentWindow else { return }
        self.documentURL = documentURL
        sizedDocumentURL = nil
        browser.open(url: documentURL, l: Self.currentLocalization)
    }

    func applyWindowPreferences(localization: L10n, appearance: AppAppearance) {
        window?.appearance = appearance.nsAppearance
        refreshToolbarLocalization(localization)
        if let controller = informationPopover?.contentViewController as? NSHostingController<ImageInformationInspector>,
           controller.rootView.l.language != localization.language {
            controller.rootView = ImageInformationInspector(information: controller.rootView.information, l: localization)
            resizeInformationPopover()
        }
    }

    func acceptsCommands(from candidate: NSWindow) -> Bool {
        guard window?.attachedSheet == nil else { return false }
        return window === candidate || (
            informationPopover?.isShown == true &&
            informationPopover?.contentViewController?.view.window === candidate
        )
    }

    /// The toolbar, its overflow menu, and the main menu all end here. Keeping
    /// the routing on the owning window prevents a background document from
    /// receiving actions when several viewers are open.
    fileprivate func canPerform(_ command: ViewerCommand) -> Bool {
        switch command {
        case .open:
            return window != nil
        case .toggleFullScreen:
            return window != nil && !isFullScreenTransitionInProgress
        case .previous:
            return browser.hasPrevious || browser.isScanning
        case .next:
            return browser.hasNext || browser.isScanning
        case .zoomOut, .fit, .zoomIn, .rotateLeft, .rotateRight,
             .revealInFinder:
            return browser.selectedURL != nil
        case .print:
            return browser.selectedURL != nil && !browser.isPreparingPrint
        }
    }

    fileprivate func perform(_ command: ViewerCommand, localization: L10n) {
        guard canPerform(command) else { return }
        switch command {
        case .open:
            browser.chooseImage(localization)
        case .toggleFullScreen:
            window?.toggleFullScreen(nil)
        case .previous:
            browser.previous()
        case .next:
            browser.next()
        case .zoomOut:
            browser.zoomOut()
        case .fit:
            browser.fitImage()
        case .zoomIn:
            browser.zoomIn()
        case .rotateLeft:
            browser.rotate(by: -90)
        case .rotateRight:
            browser.rotate(by: 90)
        case .revealInFinder:
            browser.revealInFinder()
        case .print:
            browser.printSelectedImage(localization, from: window)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        browser.resumeCanvasRendering()
        LumaViewWindowRegistry.shared.activate(browser)
        MainMenuLocalization.applyToMainMenu(Self.currentLocalization)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        browser.suspendCanvasRendering()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        browser.resumeCanvasRendering()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateCanvasVisibility()
    }

    private func updateCanvasVisibility() {
        guard let window else { return }
        // AppKit temporarily occludes a window while moving it between Spaces.
        // Keep its decoded frame through that animation; actual minimization
        // still releases the canvas immediately.
        if !window.isMiniaturized && (isFullScreenTransitionInProgress || window.occlusionState.contains(.visible)) {
            browser.resumeCanvasRendering()
        } else {
            browser.suspendCanvasRendering()
        }
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        isFullScreenTransitionInProgress = true
        LumaViewWindowRegistry.shared.objectWillChange.send()
        updateCanvasVisibility()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        isFullScreenTransitionInProgress = true
        LumaViewWindowRegistry.shared.objectWillChange.send()
        updateCanvasVisibility()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        finishFullScreenTransition()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        defer { finishFullScreenTransition() }
        guard let pixelSize = browser.originalPixelSize,
              let selectedURL = browser.selectedURL else { return }
        // Full-screen selection/rotation deliberately skips ordinary window
        // sizing. Reapply the current image after AppKit restores the old frame.
        sizedDocumentURL = nil
        applyDocumentSize(for: pixelSize, documentURL: selectedURL, quarterTurn: browser.quarterTurn)
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        finishFullScreenTransition()
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        finishFullScreenTransition()
    }

    private func finishFullScreenTransition() {
        isFullScreenTransitionInProgress = false
        LumaViewWindowRegistry.shared.objectWillChange.send()
        MainMenuLocalization.applyToMainMenu(Self.currentLocalization)
        updateCanvasVisibility()
    }

    func windowWillClose(_ notification: Notification) {
        dismissInformationPopover()
        browser.suspendCanvasRendering()
        LumaViewWindowRegistry.shared.remove(self)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        LumaViewToolbarIdentifier.defaultItems
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        LumaViewToolbarIdentifier.defaultItems
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case LumaViewToolbarIdentifier.previous:
            return toolbarItem(itemIdentifier, kind: .previous, labelKey: "toolbar.previous", action: #selector(previousToolbarAction))
        case LumaViewToolbarIdentifier.next:
            return toolbarItem(itemIdentifier, kind: .next, labelKey: "toolbar.next", action: #selector(nextToolbarAction))
        case LumaViewToolbarIdentifier.zoomOut:
            return toolbarItem(itemIdentifier, kind: .zoomOut, labelKey: "toolbar.zoomOut", action: #selector(zoomOutToolbarAction))
        case LumaViewToolbarIdentifier.fit:
            return toolbarItem(itemIdentifier, kind: .fit, labelKey: "toolbar.fit", action: #selector(fitToolbarAction))
        case LumaViewToolbarIdentifier.zoomIn:
            return toolbarItem(itemIdentifier, kind: .zoomIn, labelKey: "toolbar.zoomIn", action: #selector(zoomInToolbarAction))
        case LumaViewToolbarIdentifier.rotateLeft:
            return toolbarItem(itemIdentifier, kind: .rotateLeft, labelKey: "toolbar.rotateLeft", action: #selector(rotateLeftToolbarAction))
        case LumaViewToolbarIdentifier.rotateRight:
            return toolbarItem(itemIdentifier, kind: .rotateRight, labelKey: "toolbar.rotateRight", action: #selector(rotateRightToolbarAction))
        case LumaViewToolbarIdentifier.information:
            return informationToolbarItem(itemIdentifier)
        default:
            return nil
        }
    }

    private func refreshTitle() {
        window?.title = browser.windowTitle
        // The visual title is deliberately hidden in favour of the branded
        // titlebar accessory. Preserve the current document identity for
        // VoiceOver, Finder-style window switching, and UI automation instead
        // of exposing an anonymous AppKit window.
        window?.setAccessibilityLabel(browser.windowTitle)
        window?.representedURL = browser.selectedURL
    }

    private func makeToolbar() -> NSToolbar {
        // A new identifier intentionally discards the stale SwiftUI-toolbar
        // configuration from pre-1.2.1 builds; that saved layout could contain
        // only an overflow item after the AppKit migration.
        let toolbar = NSToolbar(identifier: "com.lumaview.appkit-toolbar.v4")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    /// Keep identity out of the toolbar item stream.  On macOS 26+, toolbar
    /// items are rendered as glass controls; a titlebar accessory remains plain
    /// titlebar content and therefore has no button-shaped backing.
    private func addBrandTitlebarAccessory(to window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        accessory.automaticallyAdjustsSize = false
        accessory.view = LumaBrandTitlebarView()
        window.addTitlebarAccessoryViewController(accessory)
    }

    private func toolbarItem(
        _ identifier: NSToolbarItem.Identifier,
        kind: LumaIconKind,
        labelKey: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        let l = Self.currentLocalization
        item.label = l.text(labelKey)
        item.paletteLabel = l.text(labelKey)
        item.toolTip = l.text(labelKey)
        let image = NSImage(named: kind.tablerAssetName)
        image?.isTemplate = true
        item.image = image
        item.target = self
        item.action = action
        item.visibilityPriority = .standard
        let overflowItem = NSMenuItem(title: item.label, action: action, keyEquivalent: "")
        overflowItem.target = self
        overflowItem.image = image
        item.menuFormRepresentation = overflowItem
        return item
    }

    /// The standard toolbar image items do not expose their rendered button as
    /// a public anchor. The inspector alone uses a compact native button view so
    /// its transient popover can point at the control the person just clicked.
    private func informationToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        let label = Self.currentLocalization.text("toolbar.info")
        let button = NSButton(
            image: NSImage(named: LumaIconKind.information.tablerAssetName) ?? NSImage(),
            target: self,
            action: #selector(informationToolbarAction)
        )
        button.image?.isTemplate = true
        button.bezelStyle = .toolbar
        button.imagePosition = .imageOnly
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.frame = NSRect(x: 0, y: 0, width: 30, height: 30)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.view = button
        let overflowItem = NSMenuItem(title: label, action: #selector(informationToolbarAction), keyEquivalent: "")
        overflowItem.target = self
        overflowItem.image = button.image
        item.menuFormRepresentation = overflowItem
        return item
    }

    private func refreshToolbarLocalization(_ l: L10n) {
        let labelKeys: [NSToolbarItem.Identifier: String] = [
            LumaViewToolbarIdentifier.previous: "toolbar.previous",
            LumaViewToolbarIdentifier.next: "toolbar.next",
            LumaViewToolbarIdentifier.zoomOut: "toolbar.zoomOut",
            LumaViewToolbarIdentifier.fit: "toolbar.fit",
            LumaViewToolbarIdentifier.zoomIn: "toolbar.zoomIn",
            LumaViewToolbarIdentifier.rotateLeft: "toolbar.rotateLeft",
            LumaViewToolbarIdentifier.rotateRight: "toolbar.rotateRight",
            LumaViewToolbarIdentifier.information: "toolbar.info"
        ]
        for item in window?.toolbar?.items ?? [] {
            guard let key = labelKeys[item.itemIdentifier] else { continue }
            let label = l.text(key)
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            if let button = item.view as? NSButton {
                button.toolTip = label
                button.setAccessibilityLabel(label)
            }
            item.menuFormRepresentation?.title = label
        }
        window?.toolbar?.validateVisibleItems()
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case LumaViewToolbarIdentifier.previous:
            return browser.hasPrevious || browser.isScanning
        case LumaViewToolbarIdentifier.next:
            return browser.hasNext || browser.isScanning
        case LumaViewToolbarIdentifier.zoomOut,
             LumaViewToolbarIdentifier.fit,
             LumaViewToolbarIdentifier.zoomIn,
             LumaViewToolbarIdentifier.rotateLeft,
             LumaViewToolbarIdentifier.rotateRight,
             LumaViewToolbarIdentifier.information:
            return browser.selectedURL != nil
        default:
            return false
        }
    }

    @objc private func previousToolbarAction(_ sender: Any?) { perform(.previous, localization: Self.currentLocalization) }
    @objc private func nextToolbarAction(_ sender: Any?) { perform(.next, localization: Self.currentLocalization) }
    @objc private func zoomOutToolbarAction(_ sender: Any?) { perform(.zoomOut, localization: Self.currentLocalization) }
    @objc private func fitToolbarAction(_ sender: Any?) { perform(.fit, localization: Self.currentLocalization) }
    @objc private func zoomInToolbarAction(_ sender: Any?) { perform(.zoomIn, localization: Self.currentLocalization) }
    @objc private func rotateLeftToolbarAction(_ sender: Any?) { perform(.rotateLeft, localization: Self.currentLocalization) }
    @objc private func rotateRightToolbarAction(_ sender: Any?) { perform(.rotateRight, localization: Self.currentLocalization) }
    @objc private func informationToolbarAction(_ sender: Any?) {
        guard let selectedURL = browser.selectedURL else { return }
        dismissInformationPopover()
        informationRequestedURL = selectedURL
        let anchor = sender as? NSView
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak anchor, weak operation] in
            guard operation?.isCancelled == false else { return }
            let information = autoreleasepool { ImageInformationReader.read(from: selectedURL) }
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async {
                guard let self, self.informationOperation === operation,
                      operation?.isCancelled == false,
                      self.browser.selectedURL == selectedURL,
                      self.window?.isVisible == true else { return }
                self.informationOperation = nil
                self.informationRequestedURL = nil
                self.presentInformationPopover(information, for: selectedURL, anchor: anchor)
            }
        }
        informationOperation = operation
        // Share the bounded header-reading queue rather than creating an
        // unbounded detached reader for every click across every window.
        ImageDecodeQueue.metadata.addOperation(operation)
    }

    private func dismissInformationPopover(unlessShowing selectedURL: URL? = nil) {
        if let selectedURL,
           informationPopoverDocumentURL == selectedURL || informationRequestedURL == selectedURL { return }
        informationOperation?.cancel()
        informationOperation = nil
        informationRequestedURL = nil
        informationPopover?.close()
        informationPopover = nil
        informationPopoverDocumentURL = nil
    }

    private func presentInformationPopover(_ information: ImageInformation, for documentURL: URL, anchor: NSView?) {
        guard let fallbackAnchor = window?.contentView else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let controller = NSHostingController(
            rootView: ImageInformationInspector(information: information, l: Self.currentLocalization)
        )
        popover.contentViewController = controller
        informationPopover = popover
        informationPopoverDocumentURL = documentURL
        resizeInformationPopover()
        if let anchor {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else {
            // A toolbar item moved into the overflow menu sends an NSMenuItem,
            // not its original NSButton. Anchor the same popover to the current
            // window's upper-right content edge so the action stays available.
            let top = fallbackAnchor.isFlipped ? fallbackAnchor.bounds.minY : fallbackAnchor.bounds.maxY - 1
            let edge = NSRect(x: fallbackAnchor.bounds.maxX - 28, y: top, width: 1, height: 1)
            popover.show(relativeTo: edge, of: fallbackAnchor, preferredEdge: .minY)
        }
    }

    private func resizeInformationPopover() {
        guard let popover = informationPopover, let controller = popover.contentViewController else { return }
        controller.view.layoutSubtreeIfNeeded()
        let fittingSize = controller.view.fittingSize
        popover.contentSize = NSSize(
            width: min(fittingSize.width, ImageInformationInspector.maximumPreferredWidth),
            height: max(1, fittingSize.height)
        )
    }
    private func applyDocumentSize(
        for imagePixelSize: CGSize,
        documentURL: URL,
        quarterTurn: QuarterTurn
    ) {
        // The window and canvas use ViewerGeometry's exact right-angle bounds.
        // Without fullSizeContentView, AppKit's content rectangle is the
        // SwiftUI canvas below the toolbar, so one image ratio sizes both.
        let orientation = ImageWindowSizing.orientationKey(for: quarterTurn)
        guard sizedDocumentURL != documentURL || sizedDocumentOrientation != orientation,
              let window,
              !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main,
              let displayedPixelSize = ImageWindowSizing.displayedPixelSize(
                  for: imagePixelSize,
                  quarterTurn: quarterTurn
              ) else { return }

        // Leave a modest safe margin around the frame, then convert that frame
        // to the exact content area available to SwiftUI's canvas. The toolbar
        // is AppKit chrome and must not be mixed into image geometry.
        let maximumFrame = screen.visibleFrame.insetBy(dx: 48, dy: 48)
        let maximumContentSize = window.contentRect(forFrameRect: maximumFrame).size
        guard let preferredContentSize = ImageWindowSizing.initialContentSize(
            for: displayedPixelSize,
            maximumContentSize: maximumContentSize
        ), let contentSize = ImageWindowSizing.aspectPreservingContentSize(
            preferred: preferredContentSize,
            minimum: authoredMinimumContentSize,
            maximum: maximumContentSize
        ) else { return }

        // Extreme aspect ratios cannot simultaneously honour the normal
        // welcome-window floor and remain visible. Lower only this document's
        // floor, in content coordinates, before applying the frame.
        let minimumContentSize = CGSize(
            width: min(authoredMinimumContentSize.width, contentSize.width),
            height: min(authoredMinimumContentSize.height, contentSize.height)
        )
        window.contentAspectRatio = contentSize
        window.minSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: minimumContentSize)
        ).size

        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let frame = ImageWindowSizing.frame(
            with: frameSize,
            centeredAt: center,
            constrainedTo: screen.visibleFrame
        )
        sizedDocumentURL = documentURL
        sizedDocumentOrientation = orientation
        window.setFrame(frame, display: true, animate: false)
    }

    private static var currentLocalization: L10n {
        let rawValue = UserDefaults.standard.string(forKey: "luma.language") ?? AppLanguage.automatic.rawValue
        return L10n(language: AppLanguage(rawValue: rawValue) ?? .automatic)
    }

    private static var currentAppearance: AppAppearance {
        let rawValue = UserDefaults.standard.string(forKey: "luma.appearance") ?? AppAppearance.system.rawValue
        return AppAppearance(rawValue: rawValue) ?? .system
    }
}

/// A passive, transparent titlebar brand.  It deliberately has no button or
/// material backing so the application mark and name remain free of a rounded
/// rectangle control treatment.
@MainActor
private final class LumaBrandTitlebarView: NSView {
    private static let size = NSSize(width: 116, height: 30)

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let mark = NSImageView()
        mark.image = NSImage(named: "LumaLogo")
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.imageAlignment = .alignCenter
        mark.isEditable = false
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        let title = NSTextField(labelWithString: "LumaView")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.isBezeled = false
        title.isBordered = false
        title.drawsBackground = false
        title.lineBreakMode = .byClipping
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        // A left titlebar accessory is stretched to the current titlebar height
        // by AppKit. Center subviews in that allocated height rather than using
        // fixed y coordinates, which would visually drop the wordmark on modern
        // taller unified toolbars.
        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: leadingAnchor),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 18),
            mark.heightAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 7),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityLabel("LumaView")
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize { Self.size }

    override func draw(_ dirtyRect: NSRect) {
        // Intentionally avoid super: no titlebar control background is painted.
    }
}

/// The Settings scene is intentionally small, but it must never be an empty
/// window. These controls mirror the menu choices while giving macOS users a
/// familiar persistent place to change them.
private struct LumaSettingsView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @AppStorage("luma.language") private var languageRaw = AppLanguage.automatic.rawValue
    @AppStorage("luma.appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .automatic }
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var l: L10n { L10n(language: language) }
    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section(l.text("settings.interface")) {
                Picker(l.text("app.appearance"), selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(l.appearanceName(option)).tag(option.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.appearance")

                Picker(l.text("app.language"), selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(l.languageName(option)).tag(option.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.language")
            }

            Section {
                LabeledContent(l.text("settings.currentVersion"), value: installedVersion)

                if let update = updateChecker.availableUpdate {
                    HStack {
                        Text(l.text("update.available", update.version))
                        Spacer()
                        Button(l.text("button.downloadUpdate")) {
                            updateChecker.openDownloadPage()
                        }
                    }
                }

                Button(l.text("update.menu.check")) {
                    Task { await updateChecker.checkForUpdate(force: true, announceResult: true) }
                }
                .accessibilityIdentifier("settings.checkForUpdates")
            } header: {
                Text(l.text("settings.updates"))
            } footer: {
                Text(l.text("settings.updatePrivacy"))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.locale, language.locale)
        .accessibilityIdentifier("settings.root")
        .navigationTitle(l.text("settings.title"))
        .alert(l.text("update.check.title"), isPresented: updateNoticeBinding) {
            Button(l.text("button.ok"), role: .cancel) {
                updateChecker.dismissNotice()
            }
        } message: {
            Text(updateNoticeMessage)
        }
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
}

@main
struct LumaViewApp: App {
    @NSApplicationDelegateAdaptor(LumaViewAppDelegate.self) private var appDelegate
    @ObservedObject private var windowRegistry = LumaViewWindowRegistry.shared
    @AppStorage("luma.language") private var languageRaw = AppLanguage.automatic.rawValue
    @AppStorage("luma.appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .automatic }
    private var l: L10n { L10n(language: language) }
    private var updateChecker: UpdateChecker { windowRegistry.updateChecker }

    var body: some Scene {
        Settings {
            LumaSettingsView(updateChecker: updateChecker)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(l.text("about.menu")) {
                    appDelegate.showAboutPanel(l: l, updateChecker: updateChecker)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(l.text("menu.openImage")) { windowRegistry.perform(.open, localization: l) }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(!windowRegistry.canPerform(.open))
            }

            // Settings is our only SwiftUI scene; the viewer windows belong to
            // AppKit. Keep this command in SwiftUI so menu rebuilds retain it.
            CommandGroup(after: .toolbar) {
                Button(l.text(windowRegistry.isFullScreen ? "system.item.exitFullScreen" : "system.item.enterFullScreen")) {
                    windowRegistry.perform(.toggleFullScreen, localization: l)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
                .disabled(!windowRegistry.canPerform(.toggleFullScreen))
            }

            CommandMenu(l.text("menu.browse")) {
                Button(l.text("command.previous")) { windowRegistry.perform(.previous, localization: l) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!windowRegistry.canPerform(.previous))
                Button(l.text("command.next")) { windowRegistry.perform(.next, localization: l) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!windowRegistry.canPerform(.next))
                Divider()
                Button(l.text("menu.reveal")) { windowRegistry.perform(.revealInFinder, localization: l) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!windowRegistry.canPerform(.revealInFinder))
            }

            // Keep image controls separate from AppKit's standard "View" menu.
            // This avoids a duplicate, differently-localized View entry in the menu bar.
            CommandMenu(l.text("menu.image")) {
                Button(l.text("command.zoomIn")) { windowRegistry.perform(.zoomIn, localization: l) }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(!windowRegistry.canPerform(.zoomIn))
                Button(l.text("command.zoomOut")) { windowRegistry.perform(.zoomOut, localization: l) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!windowRegistry.canPerform(.zoomOut))
                Button(l.text("command.fit")) { windowRegistry.perform(.fit, localization: l) }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(!windowRegistry.canPerform(.fit))
                Divider()
                Button(l.text("command.rotateLeft")) { windowRegistry.perform(.rotateLeft, localization: l) }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!windowRegistry.canPerform(.rotateLeft))
                Button(l.text("command.rotateRight")) { windowRegistry.perform(.rotateRight, localization: l) }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!windowRegistry.canPerform(.rotateRight))
            }

            CommandGroup(replacing: .printItem) {
                Button(l.text("menu.printImage")) { windowRegistry.perform(.print, localization: l) }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(!windowRegistry.canPerform(.print))
            }

            CommandMenu(l.text("app.appearance")) {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        appearanceRaw = option.rawValue
                    } label: {
                        Text((appearanceRaw == option.rawValue ? "✓  " : "    ") + l.appearanceName(option))
                    }
                }
            }

            CommandMenu(l.text("app.language")) {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        languageRaw = option.rawValue
                    } label: {
                        Text((language == option ? "✓  " : "    ") + l.languageName(option))
                    }
                }
            }

            // Preserve macOS Help and its command search; these are extra app links.
            CommandGroup(after: .help) {
                Button(updateChecker.hasUpdate
                       ? l.text("update.menu.available", updateChecker.availableUpdate?.version ?? "")
                       : l.text("update.menu.check")) {
                    if updateChecker.hasUpdate {
                        updateChecker.openDownloadPage()
                    } else {
                        Task { await updateChecker.checkForUpdate(force: true, announceResult: true) }
                    }
                }
                Divider()
                Button(l.text("about.project")) {
                    NSWorkspace.shared.open(LumaViewProjectLinks.repository)
                }
                Button(l.text("about.feedback")) {
                    NSWorkspace.shared.open(LumaViewProjectLinks.issues)
                }
            }
        }
    }
}
