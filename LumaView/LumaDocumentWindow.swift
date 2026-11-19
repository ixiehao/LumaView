import AppKit

/// Page keys belong to this document, not to a SwiftUI scene or a global
/// event monitor. Monterey does not reliably register shortcuts on the HUD.
class LumaDocumentWindow: NSWindow {
    weak var browser: ImageBrowserStore?
    var trashNoticeDefaults: UserDefaults = .standard

    override func sendEvent(_ event: NSEvent) {
        if handleTrashShortcut(event) { return }
        if handlePDFNavigation(event) { return }
        super.sendEvent(event)
    }

    @discardableResult
    func handleTrashShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 51,
              isKeyWindow, event.windowNumber == windowNumber,
              attachedSheet == nil, NSApp?.modalWindow == nil,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              !(firstResponder is NSTextView), !(firstResponder is NSControl),
              browser?.canMoveToTrash == true else { return false }
        // Holding Delete must never remove the next image by key repeat.
        if !event.isARepeat {
            let raw = UserDefaults.standard.string(forKey: "luma.language") ?? "automatic"
            moveSelectedFileToTrash(L10n(language: AppLanguage(rawValue: raw) ?? .automatic))
        }
        return true
    }

    func moveSelectedFileToTrash(_ l: L10n) {
        guard attachedSheet == nil, browser?.canMoveToTrash == true,
              let url = browser?.selectedURL else { return }
        if trashNoticeDefaults.bool(forKey: "luma.trashNoticeAccepted") {
            trashFile(url, localization: l)
            return
        }
        let alert = NSAlert()
        alert.messageText = l.text("trash.confirmTitle")
        alert.informativeText = l.text("trash.confirmMessage", url.lastPathComponent)
        alert.addButton(withTitle: l.text("menu.moveToTrash"))
        alert.addButton(withTitle: l.text("button.cancel"))
        presentTrashAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.trashFile(url, localization: l)
        }
    }

    func presentTrashAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        alert.beginSheetModal(for: self, completionHandler: completion)
    }

    private func trashFile(_ url: URL, localization l: L10n) {
        // A sheet can outlive its original selection or document window.
        guard browser?.selectedURL == url, browser?.canMoveToTrash == true else { return }
        do {
            try browser?.moveSelectedFileToTrash()
            trashNoticeDefaults.set(true, forKey: "luma.trashNoticeAccepted")
        } catch {
            let alert = NSAlert()
            alert.messageText = l.text("trash.failed")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: l.text("button.ok"))
            presentTrashAlert(alert) { _ in }
        }
    }

    @discardableResult
    func handlePDFNavigation(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, isKeyWindow,
              event.windowNumber == windowNumber,
              attachedSheet == nil, NSApp?.modalWindow == nil,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              !(firstResponder is NSTextView), !(firstResponder is NSControl),
              let browser, browser.hasMultiplePDFPages else { return false }

        // Physical arrow/page key codes are independent of the input method.
        // Consume boundary presses as well, so the scroll view cannot pan.
        switch event.keyCode {
        case 126, 116: browser.previousPage() // Up, Page Up (Fn-Up)
        case 125, 121: browser.nextPage()     // Down, Page Down (Fn-Down)
        default: return false
        }
        return true
    }
}
