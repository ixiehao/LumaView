import AppKit

/// Page keys belong to this document, not to a SwiftUI scene or a global
/// event monitor. Monterey does not reliably register shortcuts on the HUD.
class LumaDocumentWindow: NSWindow {
    weak var browser: ImageBrowserStore?

    override func sendEvent(_ event: NSEvent) {
        if handlePDFNavigation(event) { return }
        super.sendEvent(event)
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
