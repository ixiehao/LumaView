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
        appendBody("\(l.text("about.developer")) · LumaView contributors\n")
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
/// leaving a Chinese macOS menu mixed with English application menus.
@MainActor
enum MainMenuLocalization {
    private static let leadingSystemMenus: [(index: Int, key: String)] = [
        (1, "system.menu.file"),
        (2, "system.menu.edit"),
        (3, "system.menu.view")
    ]

    private static let trailingSystemMenus: [(titles: Set<String>, key: String)] = [
        (["Window", "窗口"], "system.menu.window"),
        (["Help", "帮助"], "system.menu.help")
    ]

    // When macOS itself uses a third language, the AppKit-generated titles do
    // not match either LumaView translation.  Selectors are stable across system
    // languages, so use them as the primary identity and keep titles as a legacy
    // fallback for menu items without actions.
    private static let standardItemActionKeys: [String: String] = [
        "orderFrontStandardAboutPanel:": "system.item.about",
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
        "toggleFullScreen:": "system.item.enterFullScreen",
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
    // items too so selecting English/Chinese never leaves a mixed menu hierarchy.
    private static let standardItems: [(titles: Set<String>, key: String)] = [
        (["About LumaView", "关于 LumaView"], "system.item.about"),
        (["Services", "服务"], "system.item.services"),
        (["Hide LumaView", "隐藏 LumaView"], "system.item.hideApp"),
        (["Hide Others", "隐藏其他"], "system.item.hideOthers"),
        (["Show All", "显示全部"], "system.item.showAll"),
        (["Quit LumaView", "退出 LumaView"], "system.item.quit"),
        (["Close", "关闭"], "system.item.close"),
        (["Save", "存储"], "system.item.save"),
        (["Duplicate", "复制"], "system.item.duplicate"),
        (["Rename…", "重命名…"], "system.item.rename"),
        (["Move To…", "移动到…"], "system.item.moveTo"),
        (["Export as PDF…", "导出为 PDF…"], "system.item.exportPDF"),
        (["Print…", "打印…"], "system.item.print"),
        (["Undo", "撤销"], "system.item.undo"),
        (["Redo", "重做"], "system.item.redo"),
        (["Cut", "剪切"], "system.item.cut"),
        (["Copy", "拷贝"], "system.item.copy"),
        (["Paste", "粘贴"], "system.item.paste"),
        (["Paste and Match Style", "粘贴并匹配样式"], "system.item.pasteMatch"),
        (["Delete", "删除"], "system.item.delete"),
        (["Select All", "全选"], "system.item.selectAll"),
        (["Start Dictation…", "开始听写…"], "system.item.dictation"),
        (["Emoji & Symbols", "表情与符号"], "system.item.emoji"),
        (["Enter Full Screen", "进入全屏幕"], "system.item.enterFullScreen"),
        (["Exit Full Screen", "退出全屏幕"], "system.item.exitFullScreen"),
        (["Show Toolbar", "显示工具栏"], "system.item.showToolbar"),
        (["Hide Toolbar", "隐藏工具栏"], "system.item.hideToolbar"),
        (["Customize Toolbar…", "自定工具栏…"], "system.item.customizeToolbar"),
        (["Minimize", "最小化"], "system.item.minimize"),
        (["Zoom", "缩放"], "system.item.zoom"),
        (["Bring All to Front", "全部置于最前"], "system.item.bringAllToFront"),
        (["LumaView Help", "LumaView 帮助"], "system.item.help")
    ]

    static func applyToMainMenu(_ l: L10n) {
        guard let menu = NSApp.mainMenu else { return }
        apply(l, to: menu)
    }

    static func apply(_ l: L10n, to menu: NSMenu) {

        // The first four menus are always application, File, Edit and the
        // system View menu. Indexing them prevents the application's separate
        // image View menu from being renamed as the system menu during a
        // Chinese/English switch.
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
        item.title = title
        item.submenu?.title = title
    }

    private static func localizeStandardItems(in menu: NSMenu, localization: L10n) {
        for item in menu.items {
            let titleKey = standardItems.first(where: { $0.titles.contains(item.title) })?.key
            let actionKey = item.action.flatMap { standardItemActionKeys[NSStringFromSelector($0)] }
            if let key = actionKey ?? titleKey {
                item.title = localization.text(key)
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
        // AppKit's standard menus and SwiftUI CommandMenus are assembled on
        // adjacent main-run-loop turns at launch. Reapply through that small
        // construction window so the final visible menu is never mixed-language.
        for delay in [0.0, 0.15, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainMenuLocalization.applyToMainMenu(l)
            }
        }
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

    /// Test-only document input. The unit-separator payload lets UI tests use the
    /// exact Finder/window-registry route for a real 1/4/8-window stress run without
    /// relying on developer-specific paths or automating an open panel.
    private func uiTestDocumentURLs() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        var paths: [String] = []
        if let path = environment["LUMAVIEW_UI_TEST_OPEN_FILE"] {
            paths.append(path)
        }
        if let packedPaths = environment["LUMAVIEW_UI_TEST_OPEN_FILES"] {
            paths.append(contentsOf: packedPaths.split(separator: "\u{1F}").map(String.init))
        }
        return paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath() }
            .filter(ImageFile.canOpen)
    }
}

/// Determines a comfortable, image-led content size without allowing a large
/// source file to cover menu-bar or Dock space. The result always preserves the
/// image aspect ratio, so a portrait opens as a portrait window and a panorama
/// opens wide instead of inheriting a fixed application rectangle.
enum ImageWindowSizing {
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
        arrangeUIStressWindowsIfNeeded()
    }

    func applyWindowPreferences(localization: L10n, appearance: AppAppearance) {
        controllers.values.forEach {
            $0.applyWindowPreferences(localization: localization, appearance: appearance)
        }
    }

    fileprivate func activate(_ browser: ImageBrowserStore) {
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

    /// Production launches preserve the image-led centred-window policy. This is
    /// enabled only by the UI stress suite, which needs every document visible at once
    /// in order to exercise the real render queue rather than a synthetic decoder.
    private func arrangeUIStressWindowsIfNeeded() {
        guard ProcessInfo.processInfo.environment["LUMAVIEW_UI_TEST_TILE_WINDOWS"] == "1",
              let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let windows = controllers.values
            .filter { $0.browser.selectedURL != nil }
            .sorted { ($0.browser.selectedURL?.path ?? "") < ($1.browser.selectedURL?.path ?? "") }
        guard !windows.isEmpty else { return }

        let columns = Int(ceil(sqrt(Double(windows.count))))
        let rows = Int(ceil(Double(windows.count) / Double(columns)))
        let gap: CGFloat = 10
        let width = max(260, floor((visibleFrame.width - gap * CGFloat(columns - 1)) / CGFloat(columns)))
        let height = max(190, floor((visibleFrame.height - gap * CGFloat(rows - 1)) / CGFloat(rows)))

        for (index, controller) in windows.enumerated() {
            let column = index % columns
            let row = index / columns
            let frame = NSRect(
                x: visibleFrame.minX + CGFloat(column) * (width + gap),
                y: visibleFrame.maxY - CGFloat(row + 1) * height - CGFloat(row) * gap,
                width: width,
                height: height
            )
            controller.applyUIStressFrame(frame)
        }
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
    static let print = NSToolbarItem.Identifier("com.lumaview.toolbar.print")

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
        print
    ]
}

@MainActor
private final class LumaViewWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let browser = ImageBrowserStore()
    private(set) var documentURL: URL?

    private var browserChangeObserver: AnyCancellable?
    private var pixelSizeObserver: AnyCancellable?
    private var keyEventMonitor: Any?
    private var hasAppliedInitialDocumentSize = false
    private let authoredMinimumFrameSize = NSSize(width: 560, height: 380)
    private var uiStressFrame: NSRect?

    init(documentURL: URL?, updateChecker: UpdateChecker) {
        self.documentURL = documentURL

        let contentSize = NSSize(width: 700, height: 480)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.minSize = authoredMinimumFrameSize
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
                self?.refreshTitle()
                self?.window?.toolbar?.validateVisibleItems()
            }
        }
        pixelSizeObserver = browser.$originalPixelSize
            .compactMap { $0 }
            .sink { [weak self] size in
                self?.applyInitialDocumentSize(for: size)
            }

        // AppKit toolbar actions and SwiftUI command shortcuts both express the
        // same intent, but an arrow event can arrive while a newly-created
        // document window is still becoming key. Handle bare left/right arrows
        // at the owning window as well, so Finder-opened images can always move
        // through their parent folder without waiting for command-menu focus.
        // Do not intercept modified arrows: they remain available to macOS and
        // assistive technologies.
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.browser.selectedURL != nil,
                  event.modifierFlags.intersection([.command, .option, .control, .function]).isEmpty else {
                return event
            }
            switch event.keyCode {
            case 123 where self.browser.hasPrevious || self.browser.isScanning:
                self.browser.previous()
                return nil
            case 124 where self.browser.hasNext || self.browser.isScanning:
                self.browser.next()
                return nil
            default:
                return event
            }
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

    deinit {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

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
        hasAppliedInitialDocumentSize = false
        browser.open(url: documentURL, l: Self.currentLocalization)
    }

    func applyWindowPreferences(localization: L10n, appearance: AppAppearance) {
        window?.appearance = appearance.nsAppearance
        refreshToolbarLocalization(localization)
    }

    func applyUIStressFrame(_ frame: NSRect) {
        uiStressFrame = frame
        window?.minSize = NSSize(width: 260, height: 190)
        window?.setFrame(frame, display: true, animate: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        browser.resumeCanvasRendering()
        LumaViewWindowRegistry.shared.activate(browser)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        browser.suspendCanvasRendering()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        browser.resumeCanvasRendering()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        if window.occlusionState.contains(.visible) {
            browser.resumeCanvasRendering()
        } else {
            browser.suspendCanvasRendering()
        }
    }

    func windowWillClose(_ notification: Notification) {
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
        case LumaViewToolbarIdentifier.print:
            return toolbarItem(itemIdentifier, kind: .print, labelKey: "toolbar.print", action: #selector(printToolbarAction))
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
            LumaViewToolbarIdentifier.print: "toolbar.print"
        ]
        for item in window?.toolbar?.items ?? [] {
            guard let key = labelKeys[item.itemIdentifier] else { continue }
            let label = l.text(key)
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
        }
        window?.toolbar?.validateVisibleItems()
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case LumaViewToolbarIdentifier.previous:
            return browser.hasPrevious || browser.isScanning
        case LumaViewToolbarIdentifier.next:
            return browser.hasNext || browser.isScanning
        case LumaViewToolbarIdentifier.print:
            return browser.selectedURL != nil && !browser.isPreparingPrint
        case LumaViewToolbarIdentifier.zoomOut,
             LumaViewToolbarIdentifier.fit,
             LumaViewToolbarIdentifier.zoomIn,
             LumaViewToolbarIdentifier.rotateLeft,
             LumaViewToolbarIdentifier.rotateRight:
            return browser.selectedURL != nil
        default:
            return false
        }
    }

    @objc private func previousToolbarAction(_ sender: Any?) { browser.previous() }
    @objc private func nextToolbarAction(_ sender: Any?) { browser.next() }
    @objc private func zoomOutToolbarAction(_ sender: Any?) { browser.zoomOut() }
    @objc private func fitToolbarAction(_ sender: Any?) { browser.fitImage() }
    @objc private func zoomInToolbarAction(_ sender: Any?) { browser.zoomIn() }
    @objc private func rotateLeftToolbarAction(_ sender: Any?) { browser.rotate(by: -90) }
    @objc private func rotateRightToolbarAction(_ sender: Any?) { browser.rotate(by: 90) }
    @objc private func printToolbarAction(_ sender: Any?) {
        browser.printSelectedImage(Self.currentLocalization, from: window)
    }

    private func applyInitialDocumentSize(for imagePixelSize: CGSize) {
        // The welcome window becomes a document viewer when its Open File
        // button is used. Apply the same first-image sizing policy there as we
        // do for Finder-launched documents; otherwise a landscape image stays
        // constrained inside the small welcome canvas instead of using the
        // available viewer area.
        guard !hasAppliedInitialDocumentSize,
              let window,
              !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main else { return }

        if let uiStressFrame {
            hasAppliedInitialDocumentSize = true
            window.setFrame(uiStressFrame, display: true, animate: false)
            return
        }

        let chromeHeight = max(window.frame.height - window.contentLayoutRect.height, 44)
        let maximumContentSize = CGSize(
            width: max(screen.visibleFrame.width - 96, 320),
            height: max(screen.visibleFrame.height - chromeHeight - 96, 260)
        )
        guard let contentSize = ImageWindowSizing.initialContentSize(
            for: imagePixelSize,
            maximumContentSize: maximumContentSize
        ) else { return }

        // NSWindow.minSize is a frame-size constraint.  Convert it to content
        // coordinates before centering so small or extreme-aspect images are
        // not silently enlarged by AppKit after their frame has been placed.
        let minimumContentSize = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: window.minSize)
        ).size
        guard let constrainedContentSize = ImageWindowSizing.aspectPreservingContentSize(
            preferred: contentSize,
            minimum: minimumContentSize,
            maximum: maximumContentSize
        ) else { return }
        let proposedFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: constrainedContentSize))
        // AppKit applies minSize after setFrame. For an extreme portrait/panorama
        // the normal 560×380 floor cannot coexist with the image ratio on screen;
        // lower just that window's floor before centering rather than letting AppKit
        // silently distort its final frame or offset its centre.
        window.minSize = NSSize(
            width: min(authoredMinimumFrameSize.width, proposedFrame.width),
            height: min(authoredMinimumFrameSize.height, proposedFrame.height)
        )
        let centeredFrame = ImageWindowSizing.centeredFrame(
            for: proposedFrame.size,
            in: screen.visibleFrame
        )
        hasAppliedInitialDocumentSize = true
        window.setFrame(centeredFrame, display: true, animate: false)
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
        .accessibilityIdentifier("settings.root")
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
    private var browser: ImageBrowserStore? { windowRegistry.activeBrowser }
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
                Button(l.text("menu.openImage")) { browser?.chooseImage(l) }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(browser == nil)
            }

            CommandMenu(l.text("menu.browse")) {
                Button(l.text("command.previous")) { browser?.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(browser == nil || (browser?.hasPrevious == false && browser?.isScanning == false))
                Button(l.text("command.next")) { browser?.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(browser == nil || (browser?.hasNext == false && browser?.isScanning == false))
                Divider()
                Button(l.text("menu.reveal")) { browser?.revealInFinder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(browser?.selectedURL == nil)
            }

            // Keep image controls separate from AppKit's standard "View" menu.
            // This avoids a duplicate, differently-localized View entry in the menu bar.
            CommandMenu(l.text("menu.image")) {
                Button(l.text("command.zoomIn")) { browser?.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(browser?.selectedURL == nil)
                Button(l.text("command.zoomOut")) { browser?.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(browser?.selectedURL == nil)
                Button(l.text("command.fit")) { browser?.fitImage() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(browser?.selectedURL == nil)
                Divider()
                Button(l.text("command.rotateLeft")) { browser?.rotate(by: -90) }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(browser?.selectedURL == nil)
                Button(l.text("command.rotateRight")) { browser?.rotate(by: 90) }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(browser?.selectedURL == nil)
            }

            CommandGroup(replacing: .printItem) {
                Button(l.text("menu.printImage")) { browser?.printSelectedImage(l, from: NSApp.keyWindow) }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(browser?.selectedURL == nil || browser?.isPreparingPrint == true)
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
