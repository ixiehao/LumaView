import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import LumaView

final class LumaViewCoreTests: XCTestCase {
    private var directory: URL!

    @MainActor
    func testFirstTrashNoticeCanBeCancelledAndCannotDeleteAChangedSelection() async throws {
        let a = directory.appendingPathComponent("a.png"), b = directory.appendingPathComponent("b.png")
        try Data([0]).write(to: a); try Data([0]).write(to: b)
        let store = ImageBrowserStore()
        defer { store.cancelPendingWork() }
        store.open(file: a)
        try await Self.waitForScan(store)
        let window = TrashNoticeTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.browser = store
        let suite = "LumaViewTrashTests-\(UUID().uuidString)"
        window.trashNoticeDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { window.trashNoticeDefaults.removePersistentDomain(forName: suite); window.close() }
        let l = L10n(language: .english)
        window.moveSelectedFileToTrash(l)
        XCTAssertEqual(window.alerts.count, 1)
        XCTAssertTrue(window.alerts[0].informativeText.contains("a.png"))
        window.response?(.alertSecondButtonReturn)
        XCTAssertFalse(window.trashNoticeDefaults.bool(forKey: "luma.trashNoticeAccepted"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))

        window.moveSelectedFileToTrash(l)
        XCTAssertEqual(window.alerts.count, 2, "Cancel must not suppress the first-use notice")
        store.next()
        window.response?(.alertFirstButtonReturn)
        XCTAssertFalse(window.trashNoticeDefaults.bool(forKey: "luma.trashNoticeAccepted"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))

        // Failure must keep both selection and first-use guidance intact.
        window.moveSelectedFileToTrash(l)
        try FileManager.default.removeItem(at: b)
        window.response?(.alertFirstButtonReturn)
        XCTAssertEqual(window.alerts.last?.messageText, l.text("trash.failed"))
        XCTAssertEqual(store.selectedURL, b)
        XCTAssertFalse(window.trashNoticeDefaults.bool(forKey: "luma.trashNoticeAccepted"))
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testTrashMovesRealFilesAndSynchronizesWindows() async throws {
        let urls = (1...3).map { directory.appendingPathComponent("trash-test-\($0)-\(UUID().uuidString).png") }
        for url in urls { try Data([0]).write(to: url) }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("duplicate.png"), withDestinationURL: urls[1])
        var uptime: TimeInterval = 0
        let cooldown = TrashCooldown(now: { uptime })
        let first = ImageBrowserStore(trashCooldown: cooldown), second = ImageBrowserStore(trashCooldown: cooldown)
        defer { first.cancelPendingWork(); second.cancelPendingWork() }
        first.open(file: urls[1]); second.open(file: urls[1])
        try await Self.waitForScan(first)
        try await Self.waitForScan(second)
        var trashed: [URL] = []
        defer { for url in trashed { try? FileManager.default.removeItem(at: url) } }

        let location = try XCTUnwrap(first.moveSelectedFileToTrash())
        trashed.append(location)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[1].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path), "The file must remain recoverable in Trash")
        XCTAssertEqual(first.selectedURL, urls[2])
        XCTAssertEqual(second.selectedURL, urls[2])
        XCTAssertEqual(second.files.map(\.url), [urls[0], urls[2]])

        first.select(index: 0)
        uptime += 1
        trashed.append(try XCTUnwrap(first.moveSelectedFileToTrash()))
        XCTAssertEqual(second.selectedURL, urls[2], "Removing a preceding file must not change another window's selection")
        XCTAssertEqual(second.selectedIndex, 0)
        uptime += 1
        trashed.append(try XCTUnwrap(first.moveSelectedFileToTrash()))
        for store in [first, second] {
            XCTAssertTrue(store.files.isEmpty)
            XCTAssertNil(store.selectedURL)
            XCTAssertNil(store.originalPixelSize)
            XCTAssertFalse(store.canMoveToTrash)
            XCTAssertEqual(store.pdfPageCount, 0)
        }
    }

    @MainActor
    func testRapidTrashRequestsAreIgnoredAcrossWindowsUntilCooldownEnds() async throws {
        let urls = (1...3).map { directory.appendingPathComponent("cooldown-\($0)-\(UUID().uuidString).png") }
        for url in urls { try Data([0]).write(to: url) }
        var uptime: TimeInterval = 0
        let cooldown = TrashCooldown(now: { uptime })
        let first = ImageBrowserStore(trashCooldown: cooldown), second = ImageBrowserStore(trashCooldown: cooldown)
        defer { first.cancelPendingWork(); second.cancelPendingWork() }
        first.open(file: urls[0]); second.open(file: urls[0])
        try await Self.waitForScan(first); try await Self.waitForScan(second)
        var trashed: [URL] = []
        defer { for url in trashed { try? FileManager.default.removeItem(at: url) } }
        trashed.append(try XCTUnwrap(first.moveSelectedFileToTrash()))
        XCTAssertNil(try second.moveSelectedFileToTrash())
        uptime = 0.79
        XCTAssertNil(try first.moveSelectedFileToTrash())
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[1].path))
        XCTAssertEqual(first.selectedURL, urls[1])
        uptime = 0.81
        trashed.append(try XCTUnwrap(second.moveSelectedFileToTrash()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[1].path))
        XCTAssertEqual(first.selectedURL, urls[2])
        uptime = 1.59
        XCTAssertNil(try first.moveSelectedFileToTrash(), "Ignored presses must not queue a later deletion")
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[2].path))
    }

    @MainActor
    func testTrashFailureKeepsSelectionAndFolderIndex() async throws {
        let url = directory.appendingPathComponent("missing-after-open.png")
        try Data([0]).write(to: url)
        let store = ImageBrowserStore()
        defer { store.cancelPendingWork() }
        store.open(file: url)
        XCTAssertFalse(store.canMoveToTrash, "Wait until folder indexing finishes")
        try await Self.waitForScan(store)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try store.moveSelectedFileToTrash())
        XCTAssertEqual(store.selectedURL, url)
        XCTAssertEqual(store.files.count, 1)
    }

    @MainActor
    func testDeleteShortcutIsScopedAndIgnoresKeyRepeatAndTextEditing() async throws {
        let url = directory.appendingPathComponent("keyboard-trash.png")
        try Data([0]).write(to: url)
        let store = ImageBrowserStore()
        defer { store.cancelPendingWork() }
        store.open(file: url)
        try await Self.waitForScan(store)
        let window = TrashKeyboardTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.browser = store
        defer { window.close() }
        func key(_ code: UInt16 = 51, flags: NSEvent.ModifierFlags = [], repeats: Bool = false, number: Int? = nil) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: number ?? window.windowNumber, context: nil,
                characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: repeats, keyCode: code))
        }
        XCTAssertFalse(window.isVisible, "No desktop focus or global key events")
        window.sendEvent(try key())
        XCTAssertEqual(window.trashRequests, 1)
        XCTAssertTrue(window.handleTrashShortcut(try key(repeats: true)))
        XCTAssertEqual(window.trashRequests, 1)
        for flag: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            XCTAssertFalse(window.handleTrashShortcut(try key(flags: flag)))
        }
        XCTAssertFalse(window.handleTrashShortcut(try key(117)), "Forward Delete is not the requested shortcut")
        XCTAssertFalse(window.handleTrashShortcut(try key(number: window.windowNumber + 1)))
        window.receivesTestKeys = false
        XCTAssertFalse(window.handleTrashShortcut(try key()))
        window.receivesTestKeys = true
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        window.contentView = editor
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertFalse(window.handleTrashShortcut(try key()))
        XCTAssertEqual(window.trashRequests, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LumaViewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        ImageMemoryCache.shared.clearAll()
        ImageMetadataCache.shared.clear()
    }

    @MainActor
    func testNativeFullScreenMenuKeepsItsTargetAndShortcutWhenRelocalized() throws {
        let menu = NSMenu()
        for name in ["App", "File", "Edit", "View"] {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: name)
            menu.addItem(item)
        }
        let viewMenu = try XCTUnwrap(menu.items.last?.submenu)
        let action = #selector(NSWindow.toggleFullScreen(_:))
        let installed = NSMenuItem(title: "Enter Full Screen", action: action, keyEquivalent: "f")
        installed.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(installed)
        MainMenuLocalization.apply(L10n(language: .english), to: menu)
        XCTAssertNil(installed.target, "The native responder chain must choose the current window")
        XCTAssertEqual(installed.keyEquivalent, "f")
        XCTAssertEqual(installed.keyEquivalentModifierMask, [.control, .command])

        MainMenuLocalization.apply(L10n(language: .japanese), to: menu)
        XCTAssertEqual(viewMenu.items.filter { $0.action == action }.count, 1)
        XCTAssertTrue(viewMenu.items.contains { $0 === installed })
        let l = L10n(language: .japanese)
        XCTAssertTrue([l.text("system.item.enterFullScreen"), l.text("system.item.exitFullScreen")].contains(installed.title))
    }

    func testAnimatedGIFAndWebPReadFramesAndTiming() async throws {
        let fixtures: [(String, String)] = [
            ("gif", "R0lGODlhQABAAPcfMQAAACQAAEgAAGwAAJAAALQAANgAAPwAAAAkACQkAEgkAGwkAJAkALQkANgkAPwkAABIACRIAEhIAGxIAJBIALRIANhIAPxIAABsACRsAEhsAGxsAJBsALRsANhsAPxsAACQACSQAEiQAGyQAJCQALSQANiQAPyQAAC0ACS0AEi0AGy0AJC0ALS0ANi0APy0AADYACTYAEjYAGzYAJDYALTYANjYAPzYAAD8ACT8AEj8AGz8AJD8ALT8ANj8APz8AAAAVSQAVUgAVWwAVZAAVbQAVdgAVfwAVQAkVSQkVUgkVWwkVZAkVbQkVdgkVfwkVQBIVSRIVUhIVWxIVZBIVbRIVdhIVfxIVQBsVSRsVUhsVWxsVZBsVbRsVdhsVfxsVQCQVSSQVUiQVWyQVZCQVbSQVdiQVfyQVQC0VSS0VUi0VWy0VZC0VbS0Vdi0Vfy0VQDYVSTYVUjYVWzYVZDYVbTYVdjYVfzYVQD8VST8VUj8VWz8VZD8VbT8Vdj8Vfz8VQAAqiQAqkgAqmwAqpAAqrQAqtgAqvwAqgAkqiQkqkgkqmwkqpAkqrQkqtgkqvwkqgBIqiRIqkhIqmxIqpBIqrRIqthIqvxIqgBsqiRsqkhsqmxsqpBsqrRsqthsqvxsqgCQqiSQqkiQqmyQqpCQqrSQqtiQqvyQqgC0qiS0qki0qmy0qpC0qrS0qti0qvy0qgDYqiTYqkjYqmzYqpDYqrTYqtjYqvzYqgD8qiT8qkj8qmz8qpD8qrT8qtj8qvz8qgAA/yQA/0gA/2wA/5AA/7QA/9gA//wA/wAk/yQk/0gk/2wk/5Ak/7Qk/9gk//wk/wBI/yRI/0hI/2xI/5BI/7RI/9hI//xI/wBs/yRs/0hs/2xs/5Bs/7Rs/9hs//xs/wCQ/ySQ/0iQ/2yQ/5CQ/7SQ/9iQ//yQ/wC0/yS0/0i0/2y0/5C0/7S0/9i0//y0/wDY/yTY/0jY/2zY/5DY/7TY/9jY//zY/wD8/yT8/0j8/2z8/5D8/7T8/9j8//z8/yH/C05FVFNDQVBFMi4wAwEAAAAh+QQEMgAfACwAAAAAQABAAAAI/wABCBwo8IDBgwZxKFyo8IfDhw6BSZwo8ZjFixbxadyo8Z/Hjx4JEkSIkCHDHxQnQoSIESNHjiBBihxI8qDJiylVrnTI0OXLjjFDzgRQM6HCljkl7uR589hPoEGHEi2Ko6XFpMCW/jC58Cm+oEJnFsVn9WpSrVwVGvwJ9p/UmhrLHsOKNu3Bl23fItwol+7StDj2bsw79C7Hvmf/2iUJNaben4hz1uU6lrDYp5FTTjZZ9IBlkV4zU9SaI+2DogjASg1dNljinYA7A1A98x9rq35hL64pMKpIj7eRvl4J+DTv3jIJfgyO0bXkpaUpFw0gMEHygcsxl81N3HRR5R/BA//XbtW5ZsXSj2MPOzs75O3DIUY3aZwk9fVukbt/Kdf8aPScffdbfu3tx9Ez8D2303wM1YdQbfkFxdxF/umkG1cOHnSfcvoZyFeC510YoHocFuihRgiWF99DDC6UoUEbYtfheO/htiJTGAr4m4knktXajT+0qNCLB0jFI40vpSicgt3lWFOM4oE0oUUVKgUgQ7JJBZZXSmLEnXzePamlhOS1VGVWV7qoI4QxcQnifwuGad+YMeVTZnNAFrfmgG0+1SVOQAqJA5FGbnknhXnKiRCU+Enp55sWNknfnlH22F+gimpIJ0h2/vSnWUxCpCeJfDpao5mYOjnnUIZ6CqmVIjb/SGmjPX56zJmbyUpqqR51yt+raMap6qK1zWjboyqG+tCoJLFqrJs2KuuQoEQyGmGfp+Ip7VaZGuTsjL4eCCxp3R4AZVjYJvnjtsw+OGCU0C4ZoqS6NisevIdSmeqkYuJn0AMXfHDCCy+s5EMPPPCwww465OAwDnhEjMvEHMETDzrpgIMNNtBAg0wyyiizDDHFFNPSISgfofJBDwD8gcAE3+CQDwcnzHDDCuEBMS54TIzLRvCgA47GHSMjUTDBCDPMMCSbbNEhxxxyhNQrG3RBwDC/ILNDPSC8cMPzRdwzxRuhIzTRHh8tjNLEkGyMMRehTPURLLuc9dY0I6ywDjhD/iy2zz9rFDQ6G2ODzOHAJM1203BHnTLVB9B9wNUXnDCw1g91rTDDD+csMcWBmz00x2knnvTSJb8dd8pVH9Ay1pdv/YPme/ct9thk4zM42kYnvjbTTa/Oeut2xz5zzV937jfuFZ9NOuKKL+12447PXTfsMWeu983R6dwz8xqJzrvai6f+tNwqt371y8Zz7TXn3f8NuuBmF1460uWrfr71RRJEXQCMQdEzBkjAZxjtgMAwWq4WIpjGXEckcPFRtOYlqt3ghTZigYtoIlVB6bAFgxCkyrjSpBCvfGYkVDmKlxLVE6c85YQ0SeFCAMWuhSjJhCBEYU0Ag5JtyQWHQQkIACH5BAUyAAIALAAAAABAAEAAAAj/AAUIHEiwoIAcBhMqDKawocOHECNKnEixosWLCRFizLix40SNHiPmC6nwAUmCIxeePJkyJMiEJju2XGkwpkCbNHPqVCnx5UCcN3dWxJHwQEIAO4F9hJkwwE6GHYEORCC0Z9GqHYnWxLrRJ9edUgU4/WrRqEGkZCuGHbvxWNqqSt9OfJYQakSvAsKGdGswbkStcgvahYhXrl+IgCGypTn4YeGjST2u9chX8E60G+n23bn4YuWvmDFqJtvZ4ufAFkejNu3xsU7VFxNzPW3RdU7YFmVjpV3R9mqSpX9HDC1cYvDiDokjf3h8OWTnEZun9Q1dgO6KJ068uPGj+w8fPXjw/9ChI0cOHOjz4MmTCxcufPDxoUMHDhy2bNCS6VembNkyZtU048wzxxxzyIFHJHjAggc88MAFH3yg3Q3cfddDeDvsUN55OODhIR7uuQcfPPDQZx80yCADDDDBCCPMMMQQU4wxBRp44CEJHsHggxBm98J23YGHoYbmodchiCDi8x4+JNKHDTbQoLhiiy/KOCONNuKIo4INPhDhBz9SGOSFPGi4IXofgijiiPPVB2WKLLY4DIwyYmmggTky2OAFPWr3gndClkkkh0eG+N6SJdoHpZQsukjnlQXeuCWXDkIo4XYVBppheUamGWJ8JZr4poqNVlnMjDXeeMSWO/IpoZ+Zkm25aZFHemhofG0+GaWKwcj5qDE0HpJlngtWGuGEsWJIHq2FJrmkfKKiSCqVv6aKYJ468vgqpmMOeWataj7bpKK7TvkijKcCG6mqXHYZYUFIoeWgTdc0pNS9Mgkwk1oC4VbdvwAHLPDAFPlLUUAAACH5BAUyAAIALAAAAABAAD8AAAj/AAUIHEiwoAAcBhMqXMiwocOHECNKNJiD4LOJGDMSRCjgosaNH0OKHEky4oEHJVOqXJnxAMuXAx+4hPkSJU2WM2+qRKCzp8+GOQsC+CnRZkKeKoHdDKAymMigOpXeRErSaUijPaUS3WoQakmPBa1ydXgsodaxGMWinXh2bUKwBNW6NVjWYNu5eD/CzduwLl+HewXK/euX4F2+gQUM5lt44OG8if/SlQyYcl/LDCNjFtB480DNnkMX7Bw68ePNi/OSPo05NV7TRH/88NGjBw8eO3TkwMEbB57fuHDlwpcvHzx46MBhwwYNGTJgwYQtG8asWTNnzp5de3Tp0ZMj4A+I/z954cKHEydu3JDtg/bt3Lp3+wYeHB8ufPiQg1PO3Dn06MMMQ0wxxRhzzIGHJHgIeEeM90B5570goWyz2YabDrr19hseuHB4H37IJbdcc8CUKIwwAQ5YIILHJMjgAQ2S98F5J7yg3mzuXZghbxsGd9+HIfLX3HPBRCcMMSoaiKCCL570oHno2UhhbbbBl4N8G3r4YX7oiAjNkCUCKCCBSh7S4hELNhjjkxHauF6F72GI5Xw+2gdil0L6Z2SKZB7YootNykijlDhaaKWGwHmIX37w7Deif9ChOOaKf7ooQIzisVmjm7JRucOn8fFI3493ithfmGIm6SeTTT7w4IxR3jYIp47yzTfqovjg+SiRqfbZYqWBalrjegXxhICrZB3D2kT5CNCsaM6WhNVLz0Jr7bUDkeZQQAAAIfkEBTIAAgAsAAAAAEAAQAAACP8ABQgcSLCgwYMIBSZLyLBhwxwOI0qcmBAHxYsYMwoIprGjR4oWP4qcCNHggwMjIwJLmRIfQ44SQyJ88NEly5IJD9BkyRMhyp4ZZTbcCZQiTocAioJUWvQo05RCIyboCTOiU4E/ESZluTLmQaJPBVZ1eDWswa4Ro2It+uzg2IdmWaoVAJblsY9l4wbVK6Ctx7x8l+q9+5ev345zAxtV7DExY6uPNTr2aLMn4MgMJ3fM1xSz2ImazaIlW7Qyz9AZOQO97Pkg6pSHNbLWaHogYcRFVVs2/PH1yNsE3zKcnbE2w9ENfVPUTTB2RuKtByr/CPz5xx07dOjIgaM7nu+4wuP/G48PXjp04bBFg4YMGLBgwYYNI1bMmLFnx5492v+k/4WTB+h0wQcfnPDCCzf8oKAPPfDAQ3Y5cOcdeOHhQh486IADDjbQsOdeMMIIIx999h1zzCEoHnLEikcE+MADAxZ4YII/MNggdtpJ+B14eFhoYXkZbthhe++BOB99xZhoYoosBqgTjAQaiKCCP/TQ4IPbSYjDjhWSByQ62ISJzJjvhThifcaceCKKLLb4ZIxS0ugDgw9mt513W+LSo3jjYaghhx6WKSIxSKa5JpsrohTgBXDOSKWVDkKoJZd89olOhmGy1x58g5Jo6KFtugiljFMqCCmOd25JaaV+ChkoiCIOX1PMrEqmqGKiojZaapVXStqdqnqK9yOGYAJKJKxHornkiUfc6uYBjF5wQpyP3minjqt62aqYZMIn33yzGmprk7lG6aipDV6kpImyCQCRU/pEJ++89NZrb2TQJVQdRgEBADs="),
            ("webp", "UklGRqYCAABXRUJQVlA4WAoAAAACAAAAPwAAPwAAQU5JTQYAAAD/////AABBTk1GPAEAAAAAAAAAAD8AAD8AAPQBAAJWUDhMJAEAAC8/wA8AmQssRPQ/ejPwA3/w//7HADog2bbbtgFX4Gm2l91nmhWomA1Aev0ASJFBJEmNhowE7KEEu1iAD8OmbSRBDoMrD9KzfjpfPoOJCUCRRMhvhDyJkE9xyJMI+Q3IkwjsKZbb/oqQnQBQCK0bjTHEGLqPIcLAOgZbJAK3O09AonMEZHq3gFj3PgHJ3iMg29sC0meT+u3fJW/WLWicNQs6Z4X6pWYW1C9FM6N+qZp4By5lE99/59K1ObwD59I08CLOpWdklJMehut6nF3ZW0MbgG2FezqHuGUKe0Llc0dDJbWf+Mg3IiKFJ4Lw6U9BgXS3McAKs7BZgYKCAdjCAJAKjYkGRBoYfUgwsPqGxLgM7BvBORxbwAcMeC+H2AGQUlyLozdBTk1GYgAAAAAAABgAAD8AAAgAAPQBAABWUDhMSgAAAC8/AAIAuQpE9D92EdH/gNJIkqJxRwgTLuESAuh7PM5MGymV8Bv4VwcbDiAThlgDr/7pvBpE7icZh9FZ6HDlMLygdQo2LBcRge8HQU5NRl4AAAAAAAAYAAA/AAAIAAD0AQAAVlA4TEYAAAAvPwACALkKRPQ/dhHR/4CRSFIuApL+6cDRAMV5nJm2bcygb/mj6zsEM9O2jb8WwvijG4Tti9zHCFeMjBS3oYQcVsInF94PQU5NRmYAAAAAAAAYAAA/AAAIAAD0AQAAVlA4TE4AAAAvPwACALkKRPQ/dhHR/4CSRpKkcrB0/atbegr+O34MTdtG8nYH4dk+3UD438y0bWMI/Tr+6LZvECL7JdsPc9Pi0ZbjYZ69ueQRj4gIvh8="),
        ]
        for (format, encoded) in fixtures {
            let url = directory.appendingPathComponent("animated.\(format)")
            try XCTUnwrap(Data(base64Encoded: encoded)).write(to: url)
            let reader = try XCTUnwrap(AnimatedImageReader(url: url), "\(format) should have multiple frames")
            let count = await reader.count
            let delay = await reader.delay(at: 0)
            XCTAssertEqual(count, 4, format)
            XCTAssertEqual(delay, 0.5, accuracy: 0.02, format)
            let first = await reader.frame(at: 0, maxPixelSize: 64)
            let second = await reader.frame(at: 1, maxPixelSize: 64)
            let a = try XCTUnwrap(first.image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let b = try XCTUnwrap(second.image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertEqual(a.width, 64)
            XCTAssertEqual(b.height, 64)
            XCTAssertNotEqual(a.dataProvider?.data as Data?, b.dataProvider?.data as Data?, format)
        }
    }

    func testFolderScanFiltersAndUsesNaturalOrdering() throws {
        try makeFile("photo-10.jpg")
        try makeFile("photo-2.png")
        try makeFile("photo-1.heic")
        try makeFile("notes.txt")

        let files = try ImageBrowserStore.scanFolder(directory).get()

        XCTAssertEqual(files.map(\.name), ["photo-1.heic", "photo-2.png", "photo-10.jpg"])
        XCTAssertFalse(ImageFile.canOpen(directory.appendingPathComponent("missing.jpg")))
    }

    @MainActor
    func testPDFArrowKeysReachTheOwningNativeWindowWithoutSwiftUIShortcuts() async throws {
        let pdf = directory.appendingPathComponent("keyboard.pdf")
        try makePDF(at: pdf)
        let store = ImageBrowserStore()
        store.open(file: pdf)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        let window = PDFKeyboardTestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.browser = store
        defer { window.close() }
        XCTAssertFalse(window.isVisible, "The test must not take over the desktop")

        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false, number: Int? = nil) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: number ?? window.windowNumber, context: nil,
                characters: code == 126 || code == 116 ? "\u{F700}" : "\u{F701}",
                charactersIgnoringModifiers: code == 126 || code == 116 ? "\u{F700}" : "\u{F701}",
                isARepeat: repeatKey, keyCode: code))
        }

        window.sendEvent(try key(125))
        XCTAssertEqual(store.pdfPageIndex, 1)
        window.sendEvent(try key(125, flags: [.numericPad, .function], repeatKey: true))
        XCTAssertEqual(store.pdfPageIndex, 2)
        XCTAssertTrue(window.handlePDFNavigation(try key(125)))
        XCTAssertEqual(store.pdfPageIndex, 2, "Do not scroll or move to another file at the final page")
        window.sendEvent(try key(116, flags: .function))
        XCTAssertEqual(store.pdfPageIndex, 1)
        window.sendEvent(try key(126))
        XCTAssertEqual(store.pdfPageIndex, 0)
        XCTAssertTrue(window.handlePDFNavigation(try key(126)))
        window.sendEvent(try key(121, flags: .function))
        XCTAssertEqual(store.pdfPageIndex, 1)
        for modifier: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            XCTAssertFalse(window.handlePDFNavigation(try key(125, flags: modifier)))
        }
        XCTAssertFalse(window.handlePDFNavigation(try key(124)), "Right arrow must remain file navigation")
        XCTAssertFalse(window.handlePDFNavigation(try key(125, number: window.windowNumber + 100)))
        window.receivesTestKeys = false
        XCTAssertFalse(window.handlePDFNavigation(try key(125)), "Background documents must not handle keys")
        window.receivesTestKeys = true
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        window.contentView = editor
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertFalse(window.handlePDFNavigation(try key(125)), "Leave text editing to its responder")
        XCTAssertEqual(store.pdfPageIndex, 1)
    }

    @MainActor
    func testDefaultApplicationChangesAreExplicitScopedAndVerified() async throws {
        let handler = TestDefaultApplicationHandler()
        let model = DefaultApplicationsModel(applicationURL: URL(fileURLWithPath: "/Applications/LumaView.app"), handler: handler)
        let jpeg = DefaultImageFormat.common[0], png = DefaultImageFormat.common[1]
        model.refresh()
        XCTAssertTrue(handler.requests.isEmpty)
        await model.apply()
        XCTAssertTrue(handler.requests.isEmpty)
        model.select(jpeg, enabled: true)
        model.select(png, enabled: true)
        model.select(png, enabled: false)
        await model.apply()
        XCTAssertEqual(handler.requests, [jpeg.id])
        XCTAssertTrue(model.isDefault(jpeg))
        XCTAssertFalse(model.isDefault(png))
        XCTAssertEqual(model.result?.appliedCount, 1)
        XCTAssertTrue(model.selected.isEmpty)
        model.selectAllImages()
        XCTAssertFalse(model.selected.contains(UTType.pdf.identifier), "Selecting images must not claim PDFs")
        XCTAssertFalse(model.selected.contains(jpeg.id), "Do not reapply unchanged defaults")
        model.clearSelection()
        XCTAssertTrue(model.selected.isEmpty)
    }

    @MainActor
    func testDefaultApplicationReportsFailureAndStopsWhenConsentIsCancelled() async throws {
        let formats = DefaultImageFormat.common
        let handler = TestDefaultApplicationHandler()
        let model = DefaultApplicationsModel(applicationURL: URL(fileURLWithPath: "/Applications/LumaView.app"), handler: handler)
        handler.errors[formats[0].id] = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        // A callback without an actual default change must not report success.
        handler.ignored.insert(formats[1].id)
        for format in formats.prefix(3) { model.select(format, enabled: true) }
        await model.apply()
        XCTAssertEqual(model.result?.appliedCount, 1)
        XCTAssertEqual(model.result?.failedFormats, [formats[0].name, formats[1].name])
        XCTAssertEqual(model.selected, Set([formats[0].id, formats[1].id]))
        handler.requests.removeAll()
        handler.errors[formats[0].id] = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        await model.apply()
        XCTAssertEqual(handler.requests, [formats[0].id], "Do not keep prompting after the user cancels")
        XCTAssertEqual(model.result?.cancelled, true)
        XCTAssertFalse(model.isApplying)
    }

    @MainActor
    func testDefaultApplicationRejectsTemporaryCopiesAndRefreshesExternalChanges() async throws {
        let handler = TestDefaultApplicationHandler()
        let format = DefaultImageFormat.common[0]
        for path in ["/Volumes/LumaView/LumaView.app", "/tmp/LumaView.app", "/Applications-copy/LumaView.app"] {
            let model = DefaultApplicationsModel(applicationURL: URL(fileURLWithPath: path), handler: handler)
            model.select(format, enabled: true)
            await model.apply()
            XCTAssertFalse(model.isInstalled)
            XCTAssertTrue(handler.requests.isEmpty)
        }
        let url = URL(fileURLWithPath: "/Applications/LumaView.app")
        let model = DefaultApplicationsModel(applicationURL: url, handler: handler)
        model.select(format, enabled: true)
        handler.applications[format.id] = url
        model.refresh()
        XCTAssertTrue(model.isDefault(format))
        XCTAssertTrue(model.selected.isEmpty)
        handler.applications[format.id] = URL(fileURLWithPath: "/System/Applications/Preview.app")
        model.refresh()
        XCTAssertFalse(model.isDefault(format))
        XCTAssertEqual(model.applicationName(for: format), (FileManager.default.displayName(atPath: "/System/Applications/Preview.app") as NSString).deletingPathExtension)
        XCTAssertTrue(DefaultApplicationsModel.isInstalledApplication(
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LumaView.app")))
    }

    @MainActor
    func testSettingsPanesRenderOffscreenInShortAndLongLocalizations() async throws {
        let suite = "LumaViewSettingsRender-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let handler = TestDefaultApplicationHandler()
        for format in DefaultImageFormat.common {
            handler.applications[format.id] = URL(fileURLWithPath: "/System/Applications/Preview.app")
        }
        for language in [AppLanguage.english, .chinese, .russian] {
            preferences.set(language.rawValue, forKey: "luma.language")
            for appearance in [AppAppearance.light, .dark] {
                preferences.set(appearance.rawValue, forKey: "luma.appearance")
                for tab in 0...1 {
                    let model = DefaultApplicationsModel(applicationURL: URL(fileURLWithPath: "/Applications/LumaView.app"), handler: handler)
                    model.refresh()
                    model.select(DefaultImageFormat.common[0], enabled: true)
                    model.select(DefaultImageFormat.common[1], enabled: true)
                    let size = CGSize(width: 560, height: tab == 0 ? 280 : 510)
                    let root = LumaSettingsView(updateChecker: UpdateChecker(defaults: preferences), defaultApplications: model, initialTab: tab)
                        .defaultAppStorage(preferences)
                    let host = NSHostingView(rootView: root)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
                    window.title = L10n(language: language).text("settings.title")
                    window.contentView = host
                    window.setContentSize(size)
                    // Capture the whole local window view, including its titlebar.
                    // This is an offscreen render; it never records the desktop.
                    try await Task.sleep(nanoseconds: 120_000_000)
                    host.layoutSubtreeIfNeeded()
                    XCTAssertFalse(window.isVisible)
                    XCTAssertNil(window.toolbar, "Text navigation must not create an empty icon toolbar")
                    let frameView = try XCTUnwrap(host.superview)
                    let bitmap = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
                    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = "settings-\(tab)-\(language.rawValue)-\(appearance.rawValue)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    window.close()
                }
            }
        }
        XCTAssertTrue(handler.requests.isEmpty, "Rendering settings must not change system defaults")
    }

    func testMissingFolderReportsFailureInsteadOfAnEmptyIndex() async throws {
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(try ImageBrowserStore.scanFolder(missing).get())
        XCTAssertThrowsError(try ImageBrowserStore.scanFolder(missing, isCancelled: { true }).get()) {
            XCTAssertTrue($0 is CancellationError)
        }

        let store = await MainActor.run { ImageBrowserStore() }
        await MainActor.run { store.open(folder: missing, selecting: nil) }
        try await Self.waitForScan(store)
        await MainActor.run {
            XCTAssertTrue(store.files.isEmpty)
            XCTAssertNil(store.selectedURL)
            XCTAssertNotNil(store.folderScanErrorMessage)
            XCTAssertEqual(store.displayStatusMessage(L10n(language: .english)), store.folderScanErrorMessage)
            XCTAssertEqual(store.statusAccessibilityLabel(L10n(language: .english)), store.folderScanErrorMessage)
        }
    }

    func testFolderScanRejectsARegularFile() throws {
        let file = directory.appendingPathComponent("image.png")
        try makePNG(at: file, width: 96, height: 64)
        XCTAssertThrowsError(try ImageBrowserStore.scanFolder(file).get()) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(POSIXErrorCode.ENOTDIR.rawValue))
        }
    }

    func testUnreadableFolderReportsFailureInsteadOfAnEmptyIndex() throws {
        try makePNG(at: directory.appendingPathComponent("image.png"), width: 96, height: 64)
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        guard !FileManager.default.isReadableFile(atPath: directory.path) else {
            throw XCTSkip("The test process can bypass directory read permissions")
        }
        XCTAssertThrowsError(try ImageBrowserStore.scanFolder(directory).get())
    }

    func testUnreadableParentKeepsDirectImageAndWarningAfterDecode() async throws {
        let file = directory.appendingPathComponent("first.png")
        try makePNG(at: file, width: 96, height: 64)
        try makePNG(at: directory.appendingPathComponent("second.png"), width: 96, height: 64)
        // Search permission lets the explicitly chosen image remain readable,
        // while listing its siblings requires directory read permission.
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        guard !FileManager.default.isReadableFile(atPath: directory.path) else {
            throw XCTSkip("The test process can bypass directory read permissions")
        }
        XCTAssertNotNil(ImageDecoder.navigationPreview(for: file))
        let store = await MainActor.run { ImageBrowserStore() }
        await MainActor.run { store.open(file: file) }
        try await Self.waitForScan(store)

        try await MainActor.run {
            let warning = try XCTUnwrap(store.folderScanErrorMessage)
            XCTAssertEqual(store.selectedURL, file.standardizedFileURL.resolvingSymlinksInPath())
            XCTAssertEqual(store.files.count, 1)
            XCTAssertFalse(store.isScanning)
            store.reportImageLoadResult(isAvailable: true)
            XCTAssertEqual(store.displayStatusMessage(L10n(language: .english)), warning)
            XCTAssertTrue(store.statusAccessibilityLabel(L10n(language: .english)).contains(warning))
            XCTAssertTrue(store.statusAccessibilityLabel(L10n(language: .english)).contains(file.lastPathComponent))

            store.status = .preparingPrint
            store.reportImageLoadResult(isAvailable: false)
            store.reportImageLoadResult(isAvailable: true)
            XCTAssertEqual(store.displayStatusMessage(L10n(language: .english)), L10n(language: .english).text("status.preparingPrint"))
            store.status = nil
            XCTAssertEqual(store.displayStatusMessage(L10n(language: .english)), warning)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        await MainActor.run { store.open(file: file) }
        try await Self.waitForScan(store)
        await MainActor.run {
            XCTAssertEqual(store.files.count, 2)
            XCTAssertNil(store.folderScanErrorMessage)
            XCTAssertNil(store.displayStatusMessage(L10n(language: .english)))
        }
    }

    @MainActor
    func testExternalDocumentRouterBuffersLaunchEventsAndDeliversLaterFinderEvents() throws {
        let first = directory.appendingPathComponent("first.png")
        let second = directory.appendingPathComponent("second.png")
        try makePNG(at: first, width: 1, height: 1)
        try makePNG(at: second, width: 1, height: 1)
        let unsupported = directory.appendingPathComponent("unsupported.txt")
        try Data("not an image".utf8).write(to: unsupported)

        final class DeliveryRecorder {
            var batches: [[URL]] = []
        }
        let recorder = DeliveryRecorder()
        let router = ExternalDocumentOpenRouter { recorder.batches.append($0) }

        // `application(_:open:)` may arrive before didFinishLaunching.  The
        // same canonical document sent twice must still create just one window.
        XCTAssertTrue(router.receive([first, unsupported, first]))
        XCTAssertFalse(router.receive([unsupported]))
        XCTAssertTrue(router.finishLaunching(alsoOpening: [second]).count == 2)
        XCTAssertEqual(recorder.batches.count, 1)
        XCTAssertEqual(recorder.batches[0], [
            first.standardizedFileURL.resolvingSymlinksInPath(),
            second.standardizedFileURL.resolvingSymlinksInPath()
        ])

        // Once running, Finder's classic `openFile` / `openFiles` callbacks
        // route directly to the registry; they must not recreate a welcome
        // window or wait for another launch phase.
        XCTAssertTrue(router.receive([first]))
        XCTAssertEqual(recorder.batches.count, 2)
        XCTAssertEqual(recorder.batches[1], [first.standardizedFileURL.resolvingSymlinksInPath()])
        XCTAssertTrue(router.hasAcceptedDocument)
        XCTAssertTrue(router.hasFinishedLaunching)
    }

    func testRenderRequestAndQueuesHaveExplicitLimits() {
        XCTAssertEqual(ImageRenderRequest(url: nil, maxPixelSize: 1).maxPixelSize, 1_024)
        XCTAssertEqual(ImageRenderRequest(url: nil, maxPixelSize: 99_999).maxPixelSize, 5_120)
        XCTAssertEqual(ImageDecodeQueue.metadata.maxConcurrentOperationCount, 2)
        XCTAssertEqual(ImageDecodeQueue.navigationPrefetches.maxConcurrentOperationCount, 1)
        XCTAssertEqual(ImageDecodeQueue.renders.maxConcurrentOperationCount, 2)
        XCTAssertEqual(ImageDecodeQueue.prints.maxConcurrentOperationCount, 1)
        XCTAssertEqual(ImageDecoder.maximumFallbackSourceBytes, 128 * 1024 * 1024)
        XCTAssertEqual(ImageDecoder.maximumFallbackSourcePixels, 48_000_000)
    }

    func testRotationToolbarUsesDistinctOutlineAssets() {
        XCTAssertEqual(LumaIconKind.rotateLeft.tablerAssetName, "TablerRotateCounterclockwise")
        XCTAssertEqual(LumaIconKind.rotateRight.tablerAssetName, "TablerRotateClockwise")
        XCTAssertNotEqual(LumaIconKind.rotateLeft.tablerAssetName, LumaIconKind.rotateRight.tablerAssetName)
        XCTAssertEqual(LumaIconKind.information.tablerAssetName, "TablerInfoCircle")
    }

    func testNewDocumentWindowUsesImageAspectRatioWithinVisibleBounds() throws {
        let maximum = CGSize(width: 1_200, height: 760)
        let landscape = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 6_000, height: 4_000),
            maximumContentSize: maximum
        ))
        let portrait = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 3_000, height: 6_000),
            maximumContentSize: maximum
        ))
        let small = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 320, height: 160),
            maximumContentSize: maximum
        ))

        XCTAssertEqual(landscape.width / landscape.height, 1.5, accuracy: 0.002)
        XCTAssertLessThanOrEqual(landscape.width, maximum.width)
        XCTAssertLessThanOrEqual(landscape.height, maximum.height)
        XCTAssertEqual(portrait.width / portrait.height, 0.5, accuracy: 0.002)
        XCTAssertLessThanOrEqual(portrait.width, maximum.width)
        XCTAssertLessThanOrEqual(portrait.height, maximum.height)

        // Previous/Next uses this same sizing policy.  Changing from a
        // landscape to a portrait must therefore reflow the document canvas
        // rather than leaving the portrait letterboxed in the former window.
        let browsedLandscape = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 1_600, height: 900),
            maximumContentSize: maximum
        ))
        let browsedPortrait = try XCTUnwrap(ImageWindowSizing.initialContentSize(
            for: CGSize(width: 900, height: 1_600),
            maximumContentSize: maximum
        ))
        XCTAssertEqual(browsedLandscape.width / browsedLandscape.height, 16.0 / 9.0, accuracy: 0.002)
        XCTAssertEqual(browsedPortrait.width / browsedPortrait.height, 9.0 / 16.0, accuracy: 0.002)
        XCTAssertLessThan(browsedPortrait.width, browsedLandscape.width)
        XCTAssertGreaterThan(browsedPortrait.height, browsedLandscape.height)
        XCTAssertEqual(small.width, 512, accuracy: 0.1)
        XCTAssertEqual(small.height, 256, accuracy: 0.1)

        let raisedWithoutDistortion = try XCTUnwrap(ImageWindowSizing.aspectPreservingContentSize(
            preferred: small,
            minimum: CGSize(width: 560, height: 335),
            maximum: maximum
        ))
        XCTAssertEqual(raisedWithoutDistortion.width / raisedWithoutDistortion.height, 2, accuracy: 0.002)
        XCTAssertGreaterThanOrEqual(raisedWithoutDistortion.height, 335)

        // A tall document that cannot meet a landscape minimum stays within the
        // available screen and retains its image aspect ratio.
        let extremePortrait = try XCTUnwrap(ImageWindowSizing.aspectPreservingContentSize(
            preferred: CGSize(width: 380, height: 760),
            minimum: CGSize(width: 560, height: 335),
            maximum: maximum
        ))
        XCTAssertEqual(extremePortrait.width / extremePortrait.height, 0.5, accuracy: 0.002)
        XCTAssertLessThanOrEqual(extremePortrait.height, maximum.height)

        let visibleFrame = NSRect(x: 100, y: 80, width: 1_440, height: 900)
        let centered = ImageWindowSizing.centeredFrame(
            for: CGSize(width: 1_200, height: 760),
            in: visibleFrame
        )
        XCTAssertEqual(centered.midX, visibleFrame.midX, accuracy: 0.01)
        XCTAssertEqual(centered.midY, visibleFrame.midY, accuracy: 0.01)
        XCTAssertTrue(visibleFrame.contains(centered))

        let clamped = ImageWindowSizing.centeredFrame(
            for: CGSize(width: 2_000, height: 1_200),
            in: visibleFrame
        )
        XCTAssertEqual(clamped, visibleFrame)

        // Browsing and quarter-turns resize around the current document
        // position rather than recentering it on every image change.
        let preservedPosition = ImageWindowSizing.frame(
            with: CGSize(width: 900, height: 700),
            centeredAt: CGPoint(x: 1_000, y: 450),
            constrainedTo: visibleFrame
        )
        XCTAssertEqual(preservedPosition.midX, 1_000, accuracy: 0.01)
        XCTAssertEqual(preservedPosition.midY, 450, accuracy: 0.01)
        XCTAssertTrue(visibleFrame.contains(preservedPosition))

        let positionNearEdge = ImageWindowSizing.frame(
            with: CGSize(width: 900, height: 700),
            centeredAt: CGPoint(x: 110, y: 90),
            constrainedTo: visibleFrame
        )
        XCTAssertTrue(visibleFrame.contains(positionNearEdge))
        XCTAssertEqual(positionNearEdge.minX, visibleFrame.minX, accuracy: 0.01)
        XCTAssertEqual(positionNearEdge.minY, visibleFrame.minY, accuracy: 0.01)
    }

    func testQuarterTurnsAndViewerGeometryShareExactDisplayBounds() throws {
        let landscape = CGSize(width: 1_600, height: 900)

        let quarterTurn = try XCTUnwrap(ViewerGeometry.displayedSize(for: landscape, rotation: .clockwise))
        XCTAssertEqual(quarterTurn.width, 900, accuracy: 0.001)
        XCTAssertEqual(quarterTurn.height, 1_600, accuracy: 0.001)

        let reverseQuarterTurn = try XCTUnwrap(ViewerGeometry.displayedSize(for: landscape, rotation: .counterClockwise))
        XCTAssertEqual(reverseQuarterTurn.width, 900, accuracy: 0.001)
        XCTAssertEqual(reverseQuarterTurn.height, 1_600, accuracy: 0.001)

        let halfTurn = try XCTUnwrap(ViewerGeometry.displayedSize(for: landscape, rotation: .upsideDown))
        XCTAssertEqual(halfTurn.width, 1_600, accuracy: 0.001)
        XCTAssertEqual(halfTurn.height, 900, accuracy: 0.001)

        var turn = QuarterTurn.zero
        for _ in 0..<4 { turn = turn.rotated(by: 90) }
        XCTAssertEqual(turn, .zero)
        XCTAssertEqual(QuarterTurn.zero.rotated(by: -90), .counterClockwise)
        XCTAssertEqual(QuarterTurn.upsideDown.degrees, 180)
        XCTAssertEqual(QuarterTurn.zero.rotated(by: 45), .zero)

        // Use the same displayed bounds to form the viewport a document window
        // will request. At fit zoom, the canvas then equals the rotated image
        // exactly—there is no secondary trigonometric or aspect-ratio path
        // that can introduce white rails at 90° or 270°.
        for source in [
            landscape,
            CGSize(width: 900, height: 1_600),
            CGSize(width: 1_200, height: 1_200)
        ] {
            for rotation in QuarterTurn.allCases {
                let displayed = try XCTUnwrap(ViewerGeometry.displayedSize(for: source, rotation: rotation))
                let layout = try XCTUnwrap(ViewerGeometry.canvasLayout(
                    imageSize: source,
                    viewportSize: displayed,
                    rotation: rotation,
                    zoom: 1
                ))
                XCTAssertEqual(layout.displayedImageSize.width, displayed.width, accuracy: 0.001)
                XCTAssertEqual(layout.displayedImageSize.height, displayed.height, accuracy: 0.001)
                XCTAssertEqual(layout.canvasSize, displayed)

                let magnified = try XCTUnwrap(ViewerGeometry.canvasLayout(
                    imageSize: source,
                    viewportSize: displayed,
                    rotation: rotation,
                    zoom: 2
                ))
                XCTAssertEqual(magnified.canvasSize.width, displayed.width * 2, accuracy: 0.001)
                XCTAssertEqual(magnified.canvasSize.height, displayed.height * 2, accuracy: 0.001)
            }
        }
    }

    @MainActor
    func testQuarterTurnPublisherDeliversTheAppliedCanvasOrientation() {
        let store = ImageBrowserStore()
        let source = CGSize(width: 1_600, height: 900)
        var renderedTurns: [QuarterTurn] = []
        var renderedCanvasSizes: [CGSize] = []
        var presentationRevisions: [UInt64] = []
        let observation = store.$quarterTurn
            .dropFirst()
            .sink { turn in
                renderedTurns.append(turn)
                guard let displayedSize = ViewerGeometry.displayedSize(for: source, rotation: turn),
                      let layout = ViewerGeometry.canvasLayout(
                          imageSize: source,
                          viewportSize: displayedSize,
                          rotation: turn,
                          zoom: 1
                      ) else { return }
                renderedCanvasSizes.append(layout.canvasSize)
            }
        let revisionObservation = store.$canvasPresentationRevision
            .dropFirst()
            .sink { presentationRevisions.append($0) }

        for _ in 0..<4 { store.rotate(by: 90) }

        // The window receives the quarter-turn publisher immediately. The
        // canvas receives this post-assignment revision only after the store
        // contains the same turn, so it cannot render a previous odd state.
        XCTAssertEqual(
            renderedTurns,
            [.clockwise, .upsideDown, .counterClockwise, .zero]
        )
        XCTAssertEqual(store.quarterTurn, .zero)
        XCTAssertEqual(presentationRevisions, [1, 2, 3, 4])
        XCTAssertEqual(
            renderedCanvasSizes,
            [
                CGSize(width: 900, height: 1_600),
                CGSize(width: 1_600, height: 900),
                CGSize(width: 900, height: 1_600),
                CGSize(width: 1_600, height: 900)
            ],
            "0° → 90° → 180° → 270° → 0° must update the canvas bounds on every turn"
        )
        withExtendedLifetime(observation) {}
        withExtendedLifetime(revisionObservation) {}
    }

    func testViewerGeometryRejectsInvalidImageAndViewportDimensions() {
        let valid = CGSize(width: 800, height: 600)
        let invalidSizes = [
            CGSize.zero,
            CGSize(width: -1, height: 100),
            CGSize(width: 100, height: -1),
            CGSize(width: CGFloat.infinity, height: 100),
            CGSize(width: 100, height: CGFloat.nan)
        ]

        for invalid in invalidSizes {
            XCTAssertNil(ViewerGeometry.displayedSize(for: invalid, rotation: .zero))
            XCTAssertNil(ViewerGeometry.canvasLayout(
                imageSize: invalid,
                viewportSize: valid,
                rotation: .clockwise,
                zoom: 1
            ))
            XCTAssertNil(ViewerGeometry.canvasLayout(
                imageSize: valid,
                viewportSize: invalid,
                rotation: .clockwise,
                zoom: 1
            ))
        }
    }

    func testNavigationPreviewCacheInvalidatesWhenFileChanges() throws {
        let url = directory.appendingPathComponent("replaceable.jpg")
        try Data([0x01]).write(to: url)
        let image = NSImage(size: CGSize(width: 12, height: 12))

        ImageMemoryCache.shared.storeNavigationPreview(image, for: url, pixelSize: 1_024)
        XCTAssertNotNil(ImageMemoryCache.shared.navigationPreview(for: url))

        try Data(repeating: 0x02, count: 64).write(to: url)
        XCTAssertNil(ImageMemoryCache.shared.navigationPreview(for: url))
    }

    func testNavigationPreviewDoesNotCacheOldPixelsAsAnEditedFile() throws {
        let url = directory.appendingPathComponent("edited-during-prefetch.png")
        try makePNG(at: url, width: 96, height: 48)
        let keyBeforeDecode = ImageMemoryCache.cacheKey(for: url)
        let oldImage = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))

        // Reproduce replacement between decoding the old file and inserting its
        // preview. The new file must be decoded rather than served the old image.
        try makePNG(at: url, width: 48, height: 96)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        ImageMemoryCache.shared.storeNavigationPreview(oldImage, for: url, pixelSize: 1_024, cacheKey: keyBeforeDecode)
        XCTAssertNil(ImageMemoryCache.shared.navigationPreview(for: url))
        let newImage = try XCTUnwrap(ImageDecoder.navigationPreview(for: url))
        XCTAssertEqual(ViewerGeometry.decodedSize(for: newImage), CGSize(width: 48, height: 96))
        XCTAssertTrue(newImage === ImageMemoryCache.shared.navigationPreview(for: url))
    }

    func testQuarterTurnsHandleExtremeAndNonfiniteAnglesWithoutOverflow() {
        for turn in QuarterTurn.allCases {
            XCTAssertEqual(turn.rotated(by: .nan), turn)
            XCTAssertEqual(turn.rotated(by: .infinity), turn)
            XCTAssertEqual(turn.rotated(by: -.infinity), turn)
            XCTAssertEqual(turn.rotated(by: Double.greatestFiniteMagnitude), turn)
            XCTAssertEqual(turn.rotated(by: -Double.greatestFiniteMagnitude), turn)
            XCTAssertEqual(turn.rotated(by: 360_000_000_000_000_000), turn)
            XCTAssertEqual(turn.rotated(by: 450), turn.rotated(by: 90))
            XCTAssertEqual(turn.rotated(by: -450), turn.rotated(by: -90))
        }
    }

    func testNavigationPreviewCacheUsesLeastRecentlyUsedEviction() throws {
        let urls = (1...5).map { directory.appendingPathComponent("preview-\($0).jpg") }
        let image = NSImage(size: CGSize(width: 12, height: 12))
        for url in urls {
            try Data([0x01]).write(to: url)
        }

        for url in urls.prefix(4) {
            ImageMemoryCache.shared.storeNavigationPreview(image, for: url, pixelSize: 1_024)
        }
        XCTAssertNotNil(ImageMemoryCache.shared.navigationPreview(for: urls[0]))
        ImageMemoryCache.shared.storeNavigationPreview(image, for: urls[4], pixelSize: 1_024)

        XCTAssertNotNil(ImageMemoryCache.shared.navigationPreview(for: urls[0]))
        XCTAssertNil(ImageMemoryCache.shared.navigationPreview(for: urls[1]))
    }

    func testNavigationPathIndexRemainsBounded() throws {
        let image = NSImage(size: CGSize(width: 12, height: 12))
        for index in 0..<24 {
            let url = directory.appendingPathComponent("path-index-\(index).jpg")
            try Data([0x01]).write(to: url)
            ImageMemoryCache.shared.storeNavigationPreview(image, for: url, pixelSize: 1_024)
        }
        XCTAssertLessThanOrEqual(ImageMemoryCache.shared.navigationIndexCount, 16)
    }

    func testMetadataCacheRemainsBoundedAcrossManyFiles() throws {
        let seed = directory.appendingPathComponent("metadata-seed.png")
        try makePNG(at: seed, width: 1, height: 1)
        for index in 0..<1_040 {
            let url = directory.appendingPathComponent("metadata-\(index).png")
            try FileManager.default.linkItem(at: seed, to: url)
            XCTAssertEqual(ImageMetadataCache.shared.pixelSize(for: url), CGSize(width: 1, height: 1))
        }
        XCTAssertLessThanOrEqual(ImageMetadataCache.shared.entryCount, 1_024)
    }

    func testAdaptiveDecodeProducesNavigationPreview() throws {
        let url = directory.appendingPathComponent("sample.png")
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 96,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 96, height: 64)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)

        let navigationPreview = ImageDecoder.navigationPreview(for: url, maxPixelSize: 48)
        let rendered = ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024))
        let sourceSize = ImageDecoder.pixelSize(for: url)

        XCTAssertNotNil(navigationPreview)
        XCTAssertNotNil(rendered)
        XCTAssertEqual(sourceSize, CGSize(width: 96, height: 64))
        XCTAssertLessThanOrEqual(navigationPreview?.representations.first?.pixelsWide ?? .max, 96)
    }

    func testPDFPageBoundsDriveWindowGeometryAndBoundedPreview() throws {
        let url = directory.appendingPathComponent("landscape.pdf")
        var page = CGRect(x: 0, y: 0, width: 720, height: 300)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &page, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(page)
        context.endPDFPage()
        context.closePDF()

        // Vector representations have no inherent pixels. Their page bounds
        // must still provide an aspect ratio before the first window layout.
        let dimensions = try XCTUnwrap(ImageDecoder.pixelSize(for: url))
        XCTAssertEqual(dimensions, page.size)
        let preview = try XCTUnwrap(ImageDecoder.navigationPreview(for: url, maxPixelSize: 360))
        let previewSize = try XCTUnwrap(ViewerGeometry.decodedSize(for: preview))
        XCTAssertLessThanOrEqual(max(previewSize.width, previewSize.height), 360)
        XCTAssertEqual(previewSize.width / previewSize.height, 2.4, accuracy: 0.01)
        XCTAssertEqual(ViewerGeometry.displayedSize(for: dimensions, rotation: .clockwise),
                       CGSize(width: 300, height: 720))
    }

    func testPDFPagesRenderDistinctPixelsAndUsePageAwareCache() throws {
        let url = directory.appendingPathComponent("pages.pdf")
        try makePDF(at: url)
        let first = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))
        let secondRequest = ImageRenderRequest(url: url, maxPixelSize: 1_024, pageIndex: 1)
        let second = try XCTUnwrap(ImageDecoder.renderedImage(for: secondRequest))
        let last = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024, pageIndex: 2)))
        XCTAssertFalse(first === second)
        XCTAssertTrue(second === ImageDecoder.renderedImage(for: secondRequest))
        XCTAssertTrue(second === ImageDecoder.renderedImage(for: ImageRenderRequest(
            url: url, maxPixelSize: 1_024, selectionGeneration: 42, pageIndex: 1
        )), "Window identity must not duplicate the shared page cache")
        for (image, color, ratio) in [(first, NSColor.red, 1.5), (second, NSColor.green, 1 / 1.5), (last, NSColor.blue, 1.5)] {
            let size = try XCTUnwrap(ViewerGeometry.decodedSize(for: image))
            XCTAssertEqual(size.width / size.height, ratio, accuracy: 0.002)
            XCTAssertLessThanOrEqual(max(size.width, size.height), 1_024)
            try assertPDFColor(image, expected: color)
        }
        XCTAssertEqual(ImageDecoder.documentMetadata(for: url, pageIndex: 1)?.pageCount, 3)
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url, pageIndex: 1)?.pixelSize, CGSize(width: 400, height: 600))
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url)?.pixelSize, CGSize(width: 600, height: 400))
        let printPage = try XCTUnwrap(ImageDecoder.printBitmap(for: url, maxPixelSize: 2_048, pageIndex: 1))
        try assertPDFColor(NSImage(cgImage: printPage, size: .zero), expected: .green)
    }

    func testPDFCropOriginAndIntrinsicQuarterTurnsMatchRenderedPage() throws {
        // A nonzero crop origin and /Rotate must affect both the bitmap and geometry.
        for rotation in [0, 90, 180, 270] {
            let url = directory.appendingPathComponent("crop-\(rotation).pdf")
            try makeCroppedPDF(at: url, rotation: rotation)
            let expected = rotation % 180 == 0 ? CGSize(width: 200, height: 100) : CGSize(width: 100, height: 200)
            XCTAssertEqual(ImageDecoder.documentMetadata(for: url)?.pixelSize, expected)
            let image = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))
            let size = try XCTUnwrap(ViewerGeometry.decodedSize(for: image))
            XCTAssertEqual(size.width / size.height, expected.width / expected.height, accuracy: 0.001)
            // The red media box outside the green crop must never leak into any edge.
            try assertPDFColor(image, expected: .green)
        }
    }

    func testPDFIntrinsicRotationMovesTheActualCornerPixels() throws {
        for rotation in [0, 90, 180, 270] {
            let url = directory.appendingPathComponent("corner-\(rotation).pdf")
            try makeCroppedPDF(at: url, rotation: rotation, markCorner: true)
            let image = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
            // Clockwise positions: top-left, top-right, bottom-right, bottom-left.
            for (index, point) in [(0.25, 0.25), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)].enumerated() {
                let color = try XCTUnwrap(bitmap.colorAt(
                    x: Int(Double(bitmap.pixelsWide) * point.0),
                    y: Int(Double(bitmap.pixelsHigh) * point.1)
                )?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(color.blueComponent, index == rotation / 90 ? 1 : 0, accuracy: 0.03)
                XCTAssertEqual(color.greenComponent, index == rotation / 90 ? 0 : 1, accuracy: 0.03)
            }
        }
    }

    func testPrintedPDFRespectsAllUserRotations() throws {
        let url = directory.appendingPathComponent("print-corners.pdf")
        try makeCroppedPDF(at: url, rotation: 0, markCorner: true)
        for degrees in [0, 90, 180, 270] {
            let turn = QuarterTurn.zero.rotated(by: Double(degrees))
            let cg = try XCTUnwrap(ImageDecoder.printBitmap(for: url, maxPixelSize: 400, rotation: turn))
            XCTAssertEqual(cg.width > cg.height, degrees % 180 == 0)
            let bitmap = NSBitmapImageRep(cgImage: cg)
            for (index, point) in [(0.25, 0.25), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)].enumerated() {
                let color = try XCTUnwrap(bitmap.colorAt(x: Int(Double(cg.width) * point.0), y: Int(Double(cg.height) * point.1))?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(color.blueComponent, index == degrees / 90 ? 1 : 0, accuracy: 0.03)
                XCTAssertEqual(color.greenComponent, index == degrees / 90 ? 0 : 1, accuracy: 0.03)
            }
            XCTAssertNil(ImageDecoder.rotatedPrintBitmap(cg, rotation: turn, isCancelled: { true }))
        }
    }

    @MainActor
    func testPreviewFailuresExplainCauseAndClearOnNavigation() throws {
        let locked = directory.appendingPathComponent("locked.pdf")
        try makePDF(at: locked, locked: true)
        XCTAssertEqual(ImageDecoder.previewFailure(for: locked), .passwordRequired)
        XCTAssertEqual(ImageDecoder.previewFailure(for: directory.appendingPathComponent("missing.png")), .unreadable)
        let broken = directory.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: broken)
        XCTAssertEqual(ImageDecoder.previewFailure(for: broken), .cannotDecode)
        let large = directory.appendingPathComponent("large.pdf")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(ImageDecoder.maximumFallbackSourceBytes + 1))
        try handle.close()
        XCTAssertEqual(ImageDecoder.previewFailure(for: large), .fileTooLarge)
        let browser = ImageBrowserStore()
        browser.reportImageLoadResult(isAvailable: false, failure: .passwordRequired)
        XCTAssertEqual(browser.previewFailure, .passwordRequired)
        browser.open(file: broken)
        XCTAssertNil(browser.previewFailure)
        browser.reportImageLoadResult(isAvailable: true)
        XCTAssertFalse(browser.imageLoadFailed)
        browser.suspendCanvasRendering()
    }

    @MainActor
    func testPDFStatusFadesWithoutCoveringPageAndCanBePinned() async throws {
        try XCTSkipIf(NSWorkspace.shared.isVoiceOverEnabled, "VoiceOver intentionally keeps controls visible")
        let url = directory.appendingPathComponent("hud.pdf")
        try makePDF(at: url)
        let browser = ImageBrowserStore()
        browser.open(file: url)
        try await Self.waitForScan(browser)
        let host = NSHostingView(rootView: ImageCanvasView(browser: browser, l: L10n(language: .english)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close(); browser.suspendCanvasRendering() }
        var uncoveredPageColor: NSColor?
        func sample(_ name: String) throws -> NSColor {
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            uncoveredPageColor = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)
            return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 45)?.usingColorSpace(.deviceRGB))
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        let initial = try sample("PDF-status-visible")
        try await Task.sleep(nanoseconds: 2_400_000_000)
        let hidden = try sample("PDF-status-hidden")
        XCTAssertGreaterThan(initial.greenComponent, hidden.greenComponent + 0.05)
        let page = try XCTUnwrap(uncoveredPageColor)
        XCTAssertEqual(hidden.redComponent, page.redComponent, accuracy: 0.01)
        XCTAssertEqual(hidden.greenComponent, page.greenComponent, accuracy: 0.01)
        XCTAssertEqual(hidden.blueComponent, page.blueComponent, accuracy: 0.01)
        browser.keepsStatusVisible = true
        try await Task.sleep(nanoseconds: 400_000_000)
        let pinned = try sample("PDF-status-pinned")
        XCTAssertGreaterThan(pinned.greenComponent, hidden.greenComponent + 0.05)
        XCTAssertFalse(window.isVisible, "This test must never capture or control the desktop")
    }

    @MainActor
    func testDropCollectsEveryFileInOrderWithoutDuplicates() async throws {
        let first = directory.appendingPathComponent("one.png")
        let second = directory.appendingPathComponent("two.png")
        let urls = await DocumentDrop.fileURLs(from: [
            NSItemProvider(item: first as NSURL, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(item: second.dataRepresentation as NSData, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(item: first as NSURL, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(object: "ignored" as NSString)
        ])
        XCTAssertEqual(urls, [first, second].map { $0.standardizedFileURL.resolvingSymlinksInPath() })
    }

    func testCancelledDropDiscardsAProviderThatCompletesLate() async throws {
        let url = directory.appendingPathComponent("late-drop.png")
        let data = url.dataRepresentation
        let started = expectation(description: "The drop provider started")
        let release = DispatchSemaphore(value: 0)
        let task = Task { @MainActor in
            // Match the UI drop path: create/use the non-Sendable provider on
            // the same actor instead of transferring it from the test task.
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                started.fulfill()
                // Bound the fixture's wait even if the test itself fails.
                _ = release.wait(timeout: .now() + .seconds(3))
                completion(data, nil)
                return nil
            }
            return await DocumentDrop.fileURLs(from: [provider])
        }
        defer { task.cancel(); release.signal() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        release.signal()
        let urls = await task.value
        XCTAssertTrue(urls.isEmpty, "A closed or superseded drop must not open its late result")
    }

    @MainActor
    func testDefaultApplicationsIdentifiesOtherCopyAndShowsVersionAndPath() throws {
        func app(_ name: String, id: String, version: String) throws -> URL {
            let url = directory.appendingPathComponent(name + ".app")
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleName": "LumaView", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
            return url
        }
        let current = try app("current", id: "test.luma", version: "2.0")
        let old = try app("old", id: "test.luma", version: "1.0")
        let handler = TestDefaultApplicationHandler()
        let format = DefaultImageFormat.common[0]
        handler.applications[format.id] = old
        let model = DefaultApplicationsModel(applicationURL: current, handler: handler)
        model.refresh()
        XCTAssertTrue(model.isAnotherCopy(format))
        XCTAssertFalse(model.isDefault(format))
        XCTAssertTrue(model.applicationDetails(for: format)?.contains(old.path) == true)
        XCTAssertTrue(model.applicationDetails(for: format)?.contains("1.0") == true)
        handler.applications[format.id] = current
        model.refresh()
        XCTAssertFalse(model.isAnotherCopy(format))
        XCTAssertTrue(model.isDefault(format))
    }

    func testPDFRejectsInvalidPagesCancellationAndLockedDocuments() throws {
        let url = directory.appendingPathComponent("pages.pdf")
        try makePDF(at: url)
        for page in [-1, 3, Int.max] {
            XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024, pageIndex: page)))
            XCTAssertNil(ImageDecoder.printBitmap(for: url, maxPixelSize: 2_048, pageIndex: page))
        }
        XCTAssertNil(ImageDecoder.documentMetadata(for: url, isCancelled: { true }))
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024), isCancelled: { true }))
        let broken = directory.appendingPathComponent("broken.pdf")
        try Data("not a PDF".utf8).write(to: broken)
        XCTAssertNil(ImageDecoder.documentMetadata(for: broken))
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: broken, maxPixelSize: 1_024)))
        let locked = directory.appendingPathComponent("locked.pdf")
        try makePDF(at: locked, locked: true)
        XCTAssertFalse(try XCTUnwrap(CGPDFDocument(locked as CFURL)).isUnlocked)
        XCTAssertNil(ImageDecoder.documentMetadata(for: locked))
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: locked, maxPixelSize: 1_024)))
    }

    func testPDFInformationUsesSelectedPageAndPointDimensions() throws {
        let url = directory.appendingPathComponent("pages.pdf")
        try makePDF(at: url)
        let info = ImageInformationReader.read(from: url, pageIndex: 1)
        XCTAssertEqual(info.fileFormat, "PDF")
        XCTAssertEqual(info.pdfPageNumber, 2)
        XCTAssertEqual(info.pdfPageCount, 3)
        XCTAssertEqual(info.pdfPageSize, CGSize(width: 400, height: 600))
        XCTAssertNil(info.dimensions, "PDF page points must not be labelled as image pixels")
        XCTAssertFalse(info.hasEXIF)
    }

    @MainActor
    func testPDFNavigationPreservesViewportAndKeepsWindowsIndependent() async throws {
        let url = directory.appendingPathComponent("01-pages.pdf")
        let next = directory.appendingPathComponent("02-next.png")
        try makePDF(at: url)
        try makePNG(at: next, width: 120, height: 80)
        let first = ImageBrowserStore(), second = ImageBrowserStore()
        first.open(url: url)
        second.open(url: url)
        try await Self.waitForScan(first)
        try await Self.waitForScan(second)
        try await waitForPageSize(first, CGSize(width: 600, height: 400))
        try await waitForPageSize(second, CGSize(width: 600, height: 400))
        XCTAssertEqual(first.pdfPageCount, 3)
        XCTAssertFalse(first.hasPreviousPage)
        first.previousPage()
        first.selectPDFPage(3)
        XCTAssertEqual(first.pdfPageIndex, 0)
        first.zoomIn()
        first.rotate(by: 90)
        let zoom = first.zoom
        let rotation = first.quarterTurn
        let generation = first.selectionGeneration
        first.nextPage()
        XCTAssertGreaterThan(first.selectionGeneration, generation)
        XCTAssertEqual(first.zoom, zoom)
        XCTAssertEqual(first.quarterTurn, rotation)
        try await waitForPageSize(first, CGSize(width: 400, height: 600))
        XCTAssertEqual(second.pdfPageIndex, 0)
        first.nextPage()
        first.nextPage()
        XCTAssertEqual(first.pdfPageIndex, 2)
        XCTAssertFalse(first.hasNextPage)
        // Burst page changes then file navigation must discard all stale page metadata.
        first.previousPage()
        first.previousPage()
        first.nextPage()
        first.next()
        try await waitForPageSize(first, CGSize(width: 120, height: 80))
        XCTAssertEqual(first.selectedURL, next)
        XCTAssertEqual(first.zoom, 1)
        XCTAssertEqual(first.quarterTurn, .zero)
        XCTAssertEqual(first.pdfPageIndex, 0)
        XCTAssertEqual(first.pdfPageCount, 0)
        XCTAssertFalse(first.hasMultiplePDFPages)
        first.previous()
        try await waitForPageSize(first, CGSize(width: 400, height: 600))
        XCTAssertEqual(first.pdfPageIndex, 1)
        XCTAssertEqual(first.pdfPageCount, 3)
        XCTAssertEqual(second.pdfPageIndex, 0)
    }

    @MainActor
    func testPDFResumesPage37AfterImmediateFileRoundTrip() async throws {
        let url = directory.appendingPathComponent("01-manual.pdf")
        let image = directory.appendingPathComponent("02-image.png")
        try makePDF(at: url, pageCount: 225)
        try makePNG(at: image, width: 120, height: 80)
        let store = ImageBrowserStore()
        store.open(file: url)
        try await Self.waitForScan(store)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageCount, 225)
        store.selectPDFPage(36)
        store.zoomIn()
        store.rotate(by: 90)
        // No wait: a cancelled metadata read must not discard the bookmark.
        store.next()
        XCTAssertEqual(store.selectedURL, image)
        store.previous()
        XCTAssertEqual(store.selectedURL, url)
        XCTAssertEqual(store.pdfPageIndex, 36)
        XCTAssertEqual(store.zoom, 1)
        XCTAssertEqual(store.quarterTurn, .zero)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageCount, 225)
        let decoded = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(
            url: store.selectedURL, maxPixelSize: 1_024, pageIndex: store.pdfPageIndex
        )))
        try assertPDFColor(decoded, expected: .red)
        XCTAssertEqual(ImageInformationReader.read(from: url, pageIndex: store.pdfPageIndex).pdfPageNumber, 37)
    }

    @MainActor
    func testPDFReadingPositionsUseFullPathsAndStayWindowLocal() async throws {
        let a = directory.appendingPathComponent("manual.pdf")
        let otherFolder = directory.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        let b = otherFolder.appendingPathComponent("manual.pdf")
        try makePDF(at: a)
        try makePDF(at: b)
        let store = ImageBrowserStore()
        store.open(file: a)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        store.selectPDFPage(1)
        store.open(file: b)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageIndex, 0)
        store.selectPDFPage(2)
        store.open(file: a)
        try await waitForPageSize(store, CGSize(width: 400, height: 600))
        XCTAssertEqual(store.pdfPageIndex, 1)
        store.open(file: b)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageIndex, 2)
        let otherWindow = ImageBrowserStore()
        otherWindow.open(file: b)
        try await waitForPageSize(otherWindow, CGSize(width: 600, height: 400))
        XCTAssertEqual(otherWindow.pdfPageIndex, 0)
        // Intentionally returning to the first page replaces the old bookmark.
        store.selectPDFPage(0)
        store.open(file: a)
        store.open(file: b)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageIndex, 0)
    }

    @MainActor
    func testPDFReadingPositionClampsWhenPagesAreRemoved() async throws {
        let url = directory.appendingPathComponent("01-edited.pdf")
        let image = directory.appendingPathComponent("02-image.png")
        try makePDF(at: url)
        try makePNG(at: image, width: 120, height: 80)
        let store = ImageBrowserStore()
        store.open(file: url)
        try await Self.waitForScan(store)
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        store.selectPDFPage(2)
        store.next()
        try makeCroppedPDF(at: url, rotation: 90)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        store.previous()
        try await waitForPageSize(store, CGSize(width: 100, height: 200))
        XCTAssertEqual(store.pdfPageCount, 1)
        XCTAssertEqual(store.pdfPageIndex, 0)
        XCTAssertFalse(store.hasMultiplePDFPages)
        XCTAssertFalse(store.imageLoadFailed)
        store.next()
        try makePDF(at: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(4)], ofItemAtPath: url.path)
        store.previous()
        try await waitForPageSize(store, CGSize(width: 600, height: 400))
        XCTAssertEqual(store.pdfPageIndex, 0, "Restoring pages must not revive the obsolete bookmark")
        XCTAssertEqual(store.pdfPageCount, 3)
    }

    func testPDFReadingHistoryIsBoundedAndKeepsRecentlyUsedPositions() {
        var history = PDFReadingHistory()
        let urls = (0...PDFReadingHistory.capacity).map {
            directory.appendingPathComponent("\($0).pdf")
        }
        for url in urls.dropLast() { history.remember(pageIndex: 36, for: url) }
        XCTAssertEqual(history.pageIndex(for: urls[0]), 36)
        history.remember(pageIndex: 9, for: urls.last!)
        XCTAssertEqual(history.pageIndex(for: urls[1]), 0, "Evict the least recently read document")
        XCTAssertEqual(history.pageIndex(for: urls[0]), 36)
        XCTAssertEqual(history.pageIndex(for: urls.last!), 9)
        history.remember(pageIndex: 0, for: urls[0])
        XCTAssertEqual(history.pageIndex(for: urls[0]), 0)
    }

    func testPDFReplacingFileInvalidatesEveryPageCache() throws {
        let url = directory.appendingPathComponent("updated.pdf")
        try makePDF(at: url)
        let request = ImageRenderRequest(url: url, maxPixelSize: 1_024, pageIndex: 1)
        let before = try XCTUnwrap(ImageDecoder.renderedImage(for: request))
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url, pageIndex: 1)?.pageCount, 3)
        try makeCroppedPDF(at: url, rotation: 90)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        XCTAssertNil(ImageDecoder.renderedImage(for: request), "The removed second page must not survive in cache")
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url)?.pageCount, 1)
        let after = try XCTUnwrap(ImageDecoder.renderedImage(for: ImageRenderRequest(url: url, maxPixelSize: 1_024)))
        XCTAssertFalse(before === after)
        XCTAssertEqual(ImageMetadataCache.shared.metadata(for: url)?.pixelSize, CGSize(width: 100, height: 200))
    }

    private func makePDF(at url: URL, locked: Bool = false, pageCount: Int = 3) throws {
        var box = CGRect(x: 0, y: 0, width: 600, height: 400)
        let options: [CFString: Any] = locked ? [kCGPDFContextUserPassword: "fixture", kCGPDFContextOwnerPassword: "owner"] : [:]
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, options as CFDictionary))
        let pages = [(CGSize(width: 600, height: 400), NSColor.red), (CGSize(width: 400, height: 600), NSColor.green), (CGSize(width: 600, height: 400), NSColor.blue)]
        for index in 0..<pageCount {
            let (size, color) = pages[index % pages.count]
            var page = CGRect(origin: .zero, size: size)
            let boxData = Data(bytes: &page, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            context.setFillColor(color.cgColor)
            context.fill(page)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func makeCroppedPDF(at url: URL, rotation: Int, markCorner: Bool = false) throws {
        let content = "1 0 0 rg 0 0 300 200 re f\n0 1 0 rg 50 30 200 100 re f\n"
            + (markCorner ? "0 0 1 rg 50 80 100 50 re f\n" : "")
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /CropBox [50 30 250 130] /Rotate \(rotation) /Resources << >> /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream"
        ]
        var text = "%PDF-1.4\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        try Data(text.utf8).write(to: url)
    }

    private func assertPDFColor(_ image: NSImage, expected: NSColor, file: StaticString = #filePath, line: UInt = #line) throws {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let expected = try XCTUnwrap(expected.usingColorSpace(.deviceRGB))
        for point in [(1, 1), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2), (bitmap.pixelsWide / 2, bitmap.pixelsHigh / 2)] {
            let color = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, expected.redComponent, accuracy: 0.03, file: file, line: line)
            XCTAssertEqual(color.greenComponent, expected.greenComponent, accuracy: 0.03, file: file, line: line)
            XCTAssertEqual(color.blueComponent, expected.blueComponent, accuracy: 0.03, file: file, line: line)
        }
    }

    @MainActor
    private func waitForPageSize(_ store: ImageBrowserStore, _ size: CGSize) async throws {
        for _ in 0..<200 {
            if store.originalPixelSize == size { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected page size \(size), got \(String(describing: store.originalPixelSize))")
    }

    func testImageInformationReadsEXIFOnDemand() throws {
        let url = directory.appendingPathComponent("camera.jpg")
        try makeJPEGWithEXIF(at: url)

        let information = ImageInformationReader.read(from: url)

        XCTAssertEqual(information.fileName, "camera.jpg")
        XCTAssertEqual(information.fileFormat, "JPEG")
        XCTAssertEqual(information.dimensions, "320 × 240")
        XCTAssertGreaterThan(information.fileSize ?? 0, 0)
        XCTAssertEqual(information.capturedAt, "2026-10-17 12:34:56")
        XCTAssertEqual(information.camera, "Luma Labs LumaCam 1")
        XCTAssertEqual(information.lens, "Luma 50mm f/1.8")
        XCTAssertEqual(information.exposure, "1/125 s")
        XCTAssertEqual(information.aperture, "f/2.8")
        XCTAssertEqual(information.iso, "200")
        XCTAssertEqual(information.focalLength, "50 mm")
        XCTAssertTrue(information.hasEXIF)
    }

    func testEXIFOrientationAgreesWithTheDecodedImageDimensions() throws {
        // The window uses the header dimensions, while ImageIO applies EXIF
        // orientation when decoding. A disagreement introduces white rails or
        // crops the portrait photograph before the user rotates it even once.
        for orientation in 1...8 {
            let url = directory.appendingPathComponent("orientation-\(orientation).jpg")
            try makeJPEGWithEXIF(at: url, orientation: orientation)
            let expectedSize = orientation >= 5
                ? CGSize(width: 240, height: 320)
                : CGSize(width: 320, height: 240)
            let preview = try XCTUnwrap(ImageDecoder.navigationPreview(for: url, maxPixelSize: 1_024))
            let rendered = try XCTUnwrap(ImageDecoder.renderedImage(
                for: ImageRenderRequest(url: url, maxPixelSize: 1_024)
            ))

            XCTAssertEqual(ImageDecoder.pixelSize(for: url), expectedSize, "EXIF orientation \(orientation)")
            XCTAssertEqual(ViewerGeometry.decodedSize(for: preview), expectedSize, "EXIF orientation \(orientation)")
            XCTAssertEqual(ViewerGeometry.decodedSize(for: rendered), expectedSize, "EXIF orientation \(orientation)")
            XCTAssertEqual(ImageInformationReader.read(from: url).dimensions,
                           "\(Int(expectedSize.width)) × \(Int(expectedSize.height))")
        }
    }

    func testExtremeEXIFNumbersDoNotOverflowOrProduceAnInfiniteExposure() throws {
        for seconds in [Double.leastNonzeroMagnitude, 1e-30, Double.greatestFiniteMagnitude] {
            let exposure = try XCTUnwrap(ImageInformationReader.formattedExposure(seconds))
            XCTAssertTrue(exposure.hasSuffix(" s"))
            XCTAssertFalse(exposure.lowercased().contains("inf"))
            XCTAssertFalse(exposure.lowercased().contains("nan"))
        }
        for seconds in [0, -1, Double.infinity, Double.nan] {
            XCTAssertNil(ImageInformationReader.formattedExposure(seconds))
        }
        XCTAssertEqual(ImageInformationReader.formattedExposure(1.0 / 125), "1/125 s")
        XCTAssertEqual(ImageInformationReader.formattedExposure(0.8), "0.8 s")
        XCTAssertEqual(ImageInformationReader.formattedExposure(0.3), "0.3 s")
        XCTAssertEqual(ImageInformationReader.formattedExposure(1.0 / 3), "1/3 s")
        XCTAssertEqual(ImageInformationReader.formattedDecimal(50), "50")
        XCTAssertEqual(ImageInformationReader.formattedDecimal(2.8), "2.8")
    }

    @MainActor
    func testImageInformationInspectorFitsCompleteEXIFWithoutInternalScrolling() {
        let information = ImageInformation(
            fileName: "camera-with-complete-metadata.jpg",
            fileFormat: "JPEG",
            fileSize: 12_345_678,
            pixelWidth: 6_000,
            pixelHeight: 4_000,
            capturedAt: "2026-10-17 12:34:56",
            camera: "Luma Labs LumaCam One",
            lens: "Luma Prime 50mm f/1.8",
            exposure: "1/125 s",
            aperture: "f/2.8",
            iso: "200",
            focalLength: "50 mm"
        )
        let controller = NSHostingController(
            rootView: ImageInformationInspector(information: information, l: L10n(language: .english))
        )

        controller.view.layoutSubtreeIfNeeded()
        let fittedSize = controller.view.fittingSize

        // The inspector has no fixed short height or inner scroll view: a
        // complete file + EXIF record must determine its own popover height.
        XCTAssertGreaterThan(fittedSize.height, 260)
        XCTAssertLessThanOrEqual(fittedSize.width, ImageInformationInspector.maximumPreferredWidth)

        let compactController = NSHostingController(
            rootView: ImageInformationInspector(
                information: ImageInformation(
                    fileName: "image.png",
                    fileFormat: "PNG",
                    fileSize: 1_024,
                    pixelWidth: 32,
                    pixelHeight: 32,
                    capturedAt: nil,
                    camera: nil,
                    lens: nil,
                    exposure: nil,
                    aperture: nil,
                    iso: nil,
                    focalLength: nil
                ),
                l: L10n(language: .english)
            )
        )
        compactController.view.layoutSubtreeIfNeeded()
        XCTAssertLessThan(
            compactController.view.fittingSize.width,
            ImageInformationInspector.maximumPreferredWidth,
            "A compact record should not inherit the width of a full EXIF record."
        )
    }

    func testSketchDocumentUsesBundledPreviewForAllImageOperations() throws {
        let previewDirectory = directory.appendingPathComponent("previews")
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let previewURL = previewDirectory.appendingPathComponent("preview.png")
        try makePNG(at: previewURL, width: 144, height: 96)

        let documentURL = directory.appendingPathComponent("sample.sketch")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", documentURL.path, "previews"]
        zip.currentDirectoryURL = directory
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        XCTAssertTrue(ImageFile.canOpen(documentURL))
        XCTAssertEqual(ImageDecoder.pixelSize(for: documentURL), CGSize(width: 144, height: 96))
        XCTAssertNotNil(ImageDecoder.navigationPreview(for: documentURL, maxPixelSize: 48))
        XCTAssertNotNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: documentURL, maxPixelSize: 1_024)))
        XCTAssertNotNil(ImageDecoder.sourceImage(for: documentURL))

        let packageURL = directory.appendingPathComponent("package.sketch")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: previewDirectory, to: packageURL.appendingPathComponent("previews"))
        XCTAssertTrue(ImageFile.canOpen(packageURL))
        XCTAssertEqual(ImageDecoder.pixelSize(for: packageURL), CGSize(width: 144, height: 96))
    }

    func testSketchArchiveStopsAtPreviewByteLimit() throws {
        let previewDirectory = directory.appendingPathComponent("previews")
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let oversizedPreview = previewDirectory.appendingPathComponent("preview.png")
        try Data(repeating: 0x00, count: 64 * 1024 * 1024 + 1).write(to: oversizedPreview)

        let documentURL = directory.appendingPathComponent("oversized.sketch")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", documentURL.path, "previews"]
        zip.currentDirectoryURL = directory
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        XCTAssertNil(ImageDecoder.pixelSize(for: documentURL))
    }

    func testCancelledSketchDecodeReturnsWithoutStartingPreviewWork() throws {
        let documentURL = directory.appendingPathComponent("cancelled.sketch")
        try Data("not a sketch archive".utf8).write(to: documentURL)
        XCTAssertNil(ImageDecoder.pixelSize(for: documentURL, isCancelled: { true }))
        XCTAssertNil(ImageDecoder.renderedImage(
            for: ImageRenderRequest(url: documentURL, maxPixelSize: 1_024),
            isCancelled: { true }
        ))
    }

    func testSketchExtractionEnforcesOutputLimitAndHandlesLaunchFailure() {
        func run(_ command: String, limit: Int) -> Data? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let result = SketchPreviewExtractor.boundedOutput(
                from: process, byteLimit: limit, deadline: .now() + .seconds(2)
            )
            XCTAssertFalse(process.isRunning, "An extraction must not leave its subprocess running")
            return result
        }
        XCTAssertEqual(run("printf 12345678", limit: 8), Data("12345678".utf8))
        XCTAssertNil(run("printf 123456789", limit: 8))
        XCTAssertNil(run("printf partial; exit 1", limit: 64))

        let missing = Process()
        missing.executableURL = directory.appendingPathComponent("missing-unzip")
        XCTAssertNil(SketchPreviewExtractor.boundedOutput(
            from: missing, byteLimit: 64, deadline: .now() + .seconds(2)
        ))
    }

    func testSketchExtractionTimeoutAndCancellationTerminateAStalledProcess() {
        for cancel in [false, true] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            // No descendant process: SIGTERM is deliberately ignored to verify
            // the extractor's bounded escalation also reaps the child.
            process.arguments = ["-c", "trap '' TERM; printf partial; while :; do :; done"]
            let cancellationTime = DispatchTime.now() + .milliseconds(150)
            let result = SketchPreviewExtractor.boundedOutput(
                from: process,
                byteLimit: 64,
                deadline: .now() + .milliseconds(cancel ? 2_000 : 150),
                isCancelled: { cancel && DispatchTime.now() >= cancellationTime }
            )
            XCTAssertNil(result)
            XCTAssertFalse(process.isRunning)
        }
    }

    func testSketchPackagePreviewReplacementInvalidatesCachedDimensionsAndPixels() throws {
        let package = directory.appendingPathComponent("replaced.sketch", isDirectory: true)
        let previews = package.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        let preview = previews.appendingPathComponent("preview.png")
        try makePNG(at: preview, width: 144, height: 96)
        let packageDate = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: package.path)[.modificationDate] as? Date
        )
        let oldKey = ImageMemoryCache.cacheKey(for: package)
        XCTAssertEqual(ImageMetadataCache.shared.pixelSize(for: package), CGSize(width: 144, height: 96))
        XCTAssertNotNil(ImageDecoder.navigationPreview(for: package))

        try makePNG(at: preview, width: 300, height: 200)
        try FileManager.default.setAttributes([.modificationDate: packageDate], ofItemAtPath: package.path)
        XCTAssertNotEqual(ImageMemoryCache.cacheKey(for: package), oldKey)
        XCTAssertEqual(ImageMetadataCache.shared.pixelSize(for: package), CGSize(width: 300, height: 200))
        let replaced = try XCTUnwrap(ImageDecoder.navigationPreview(for: package))
        XCTAssertEqual(ViewerGeometry.decodedSize(for: replaced), CGSize(width: 300, height: 200))
    }

    func testSketchPackageOpensAsADocumentAndNavigatesItsParentFolder() async throws {
        let package = directory.appendingPathComponent("01-design.sketch", isDirectory: true)
        let previews = package.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        try makePNG(at: previews.appendingPathComponent("preview.png"), width: 144, height: 96)
        let next = directory.appendingPathComponent("02-photo.png")
        try makePNG(at: next, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(url: package) }
        let immediateURL = await MainActor.run { store.selectedURL }
        XCTAssertEqual(immediateURL, package.standardizedFileURL.resolvingSymlinksInPath())
        try await Self.waitForScan(store)
        let state = await MainActor.run { (store.folderURL, store.files.map(\.name), store.selectedURL) }
        XCTAssertEqual(state.0, directory.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(state.1, ["01-design.sketch", "02-photo.png"])
        XCTAssertEqual(state.2, package.standardizedFileURL.resolvingSymlinksInPath())

        await MainActor.run { store.next() }
        let nextURL = await MainActor.run { store.selectedURL }
        XCTAssertEqual(nextURL, next.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testReplacingAnInFlightFolderOpenKeepsTheLatestDocument() async throws {
        let firstFolder = directory.appendingPathComponent("first", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let first = firstFolder.appendingPathComponent("first.png")
        let second = secondFolder.appendingPathComponent("second.png")
        try makePNG(at: first, width: 120, height: 80)
        try makePNG(at: second, width: 80, height: 120)
        let store = await MainActor.run { ImageBrowserStore() }

        // The first scan cannot publish its result until this actor turn yields.
        await MainActor.run {
            store.open(url: first)
            store.next()
            store.open(url: second)
        }
        try await Self.waitForScan(store)
        let state = await MainActor.run { (store.folderURL, store.files.map(\.name), store.selectedURL, store.isScanning) }
        XCTAssertEqual(state.0, secondFolder.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(state.1, ["second.png"])
        XCTAssertEqual(state.2, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertFalse(state.3)
    }

    func testEveryUserSelectableLanguageHasAllRequiredTranslations() {
        XCTAssertEqual(AppLanguage.allCases.first, .english)
        for language in AppLanguage.allCases where language != .automatic {
            let l = L10n(language: language)
            for key in AppLanguage.requiredLocalizationKeys {
                XCTAssertNotEqual(l.text(key), key, "\(language.rawValue) is missing \(key)")
            }
        }
        XCTAssertEqual(L10n(language: .english).text("system.menu.file"), "File")
        XCTAssertEqual(L10n(language: .english).text("system.menu.help"), "Help")
        XCTAssertEqual(L10n(language: .chinese).text("system.menu.edit"), "编辑")
        XCTAssertEqual(L10n(language: .chinese).text("system.menu.window"), "窗口")
        XCTAssertEqual(L10n(language: .english).text("toolbar.print"), "Print image (⌘P)")
        XCTAssertEqual(L10n(language: .english).text("toolbar.info"), "Image information")
        XCTAssertEqual(L10n(language: .chinese).text("toolbar.next"), "下一张（→）")
        XCTAssertEqual(L10n(language: .chinese).text("toolbar.info"), "图片信息")
        XCTAssertEqual(L10n(language: .chinese).text("toolbar.rotateLeft"), "向左旋转")
        XCTAssertEqual(L10n(language: .japanese).text("system.menu.file"), "ファイル")
        XCTAssertEqual(L10n(language: .japanese).text("toolbar.next"), "次の画像（→）")
        XCTAssertEqual(L10n(language: .japanese).text("toolbar.rotateLeft"), "左に回転")
        XCTAssertEqual(L10n(language: .japanese).text("toolbar.info"), "画像情報")
        XCTAssertEqual(L10n(language: .french).text("system.menu.file"), "Fichier")
        XCTAssertEqual(L10n(language: .russian).text("system.menu.file"), "Файл")
        XCTAssertEqual(L10n(language: .spanish).text("system.menu.file"), "Archivo")
        XCTAssertEqual(L10n(language: .korean).text("system.menu.file"), "파일")
    }

    func testAutomaticLanguageRespectsSupportedPreferenceOrderAndRegions() {
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["de-DE", "fr-CA", "en"]), .french)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["ru_RU"]), .russian)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["es-MX"]), .spanish)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["ko-KR"]), .korean)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["zh-Hant-TW"]), .chinese)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["ja-JP", "en"]), .japanese)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: ["ar", "de"]), .english)
        XCTAssertEqual(AppLanguage.preferredLanguage(in: []), .english)
    }

    func testLanguageMenusAndLocalizedWebsiteUseTheSameSupportedChoices() {
        XCTAssertEqual(AppLanguage.menuOrder, [.automatic, .english, .chinese, .french, .russian, .spanish, .japanese, .korean])
        let routes: [(AppLanguage, String)] = [(.english, ""), (.chinese, "zh/"), (.french, "fr/"),
            (.russian, "ru/"), (.spanish, "es/"), (.japanese, "ja/"), (.korean, "ko/")]
        for (language, route) in routes {
            XCTAssertEqual(LumaViewProjectLinks.website(for: language).absoluteString, "https://ixiehao.github.io/LumaView/" + route)
            let l = L10n(language: language)
            XCTAssertEqual(l.languageName(.automatic), l.text("language.followSystem"))
            XCTAssertEqual(l.languageName(.chinese), "简体中文")
        }
        XCTAssertEqual(LumaViewProjectLinks.website(for: .automatic),
            LumaViewProjectLinks.website(for: AppLanguage.automatic.resolvedLanguage))
    }

    @MainActor
    func testNativeMenuTitlesCanSwitchBetweenEverySupportedLanguage() {
        let menu = NSMenu()
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        menu.addItem(services)
        for language in AppLanguage.allCases where language != .automatic {
            let l = L10n(language: language)
            MainMenuLocalization.apply(l, to: menu)
            XCTAssertEqual(services.title, l.text("system.item.services"))
        }
        MainMenuLocalization.apply(L10n(language: .english), to: menu)
        XCTAssertEqual(services.title, "Services")
    }

    func testAppearanceModesHaveExplicitSwiftUIAndAppKitRepresentations() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertNil(AppAppearance.system.nsAppearance)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, NSAppearance.Name.aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, NSAppearance.Name.darkAqua)
    }

    @MainActor
    func testDropAndFinderOpenShareUnsupportedFormatFeedback() throws {
        let unsupported = directory.appendingPathComponent("not-an-image.jpg")
        try Data("not a decodable image".utf8).write(to: unsupported)
        let store = ImageBrowserStore()
        let localization = L10n(language: .english)

        // The extension is deliberately accepted by Finder/drop routing, but
        // ImageIO cannot decode it. Keep the selected document state so the
        // canvas shows its explicit unavailable state rather than welcome UI.
        store.open(url: unsupported)
        XCTAssertEqual(store.selectedURL, unsupported.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertNil(ImageDecoder.renderedImage(for: ImageRenderRequest(url: unsupported, maxPixelSize: 1_024)))

        let rejected = directory.appendingPathComponent("not-an-image.txt")
        try Data("not an image".utf8).write(to: rejected)
        store.open(url: rejected)
        XCTAssertEqual(store.displayStatusMessage(localization), localization.text("error.unsupportedFormat"))
    }

    @MainActor
    func testPrintWithoutSelectionReportsLocalizedFeedbackInsteadOfPresentingAPanel() {
        let store = ImageBrowserStore()
        let localization = L10n(language: .english)
        store.printSelectedImage()
        XCTAssertEqual(store.displayStatusMessage(localization), localization.text("error.noPrintSelection"))
    }

    @MainActor
    func testExistingFeedbackUsesCurrentLanguageWithoutRepeatingOperations() async throws {
        let store = ImageBrowserStore()
        let english = L10n(language: .english)
        let french = L10n(language: .french)
        let unsupported = directory.appendingPathComponent("notes.txt")
        try Data("text".utf8).write(to: unsupported)
        store.open(file: unsupported)
        XCTAssertEqual(store.displayStatusMessage(english), "Unsupported image format.")
        XCTAssertEqual(store.displayStatusMessage(french), "Format d’image non pris en charge.")

        store.printSelectedImage()
        XCTAssertEqual(store.displayStatusMessage(french), french.text("error.noPrintSelection"))
        try FileManager.default.removeItem(at: unsupported)
        store.open(folder: directory, selecting: nil)
        try await Self.waitForScan(store)
        XCTAssertEqual(store.displayStatusMessage(french), french.text("error.emptyFolder"))

        let file = directory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: file)
        store.open(file: file)
        try await Self.waitForScan(store)
        store.reportImageLoadResult(isAvailable: false)
        for language in AppLanguage.allCases where language != .automatic {
            let l = L10n(language: language)
            XCTAssertEqual(store.displayStatusMessage(l), l.text("preview.cannotDecode"))
            XCTAssertTrue(store.statusAccessibilityLabel(l).contains(l.text("preview.cannotDecode")))
            XCTAssertEqual(store.selectedURL, file)
        }
        store.reportImageLoadResult(isAvailable: true)
        XCTAssertNil(store.displayStatusMessage(french))
    }

    @MainActor
    func testPrintOutputUsesThePrintablePaperArea() throws {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        // Simulate the large default document margins that shrank photo prints.
        info.leftMargin = 72
        info.rightMargin = 72
        info.topMargin = 72
        info.bottomMargin = 72
        let output = try renderPrintedImage(size: NSSize(width: 300, height: 400), info: info)
        let area = output.info.imageablePageBounds.intersection(output.paper)
        let scale = min(area.width / 300, area.height / 400)
        XCTAssertEqual(output.ink.width, 300 * scale, accuracy: 3)
        XCTAssertEqual(output.ink.height, 400 * scale, accuracy: 3)
        XCTAssertEqual(output.ink.midX, area.midX, accuracy: 2)
        XCTAssertEqual(output.ink.midY, area.midY, accuracy: 2)
    }

    @MainActor
    func testPrintLayoutReflowsWhenPaperOrOrientationChanges() throws {
        for (size, paper, orientation) in [
            (NSSize(width: 400, height: 300), NSSize(width: 595, height: 842), NSPrintInfo.PaperOrientation.landscape),
            (NSSize(width: 400, height: 300), NSSize(width: 612, height: 792), .portrait),
            (NSSize(width: 300, height: 400), NSSize(width: 842, height: 1191), .portrait),
            (NSSize(width: 40, height: 60), NSSize(width: 288, height: 432), .portrait)
        ] {
            let info = NSPrintInfo()
            info.paperSize = NSSize(width: 595, height: 842)
            let output = try renderPrintedImage(size: size, info: info) { settings in
                settings.paperSize = paper
                settings.orientation = orientation
            }
            XCTAssertEqual(output.paper.width, output.info.paperSize.width, accuracy: 0.2)
            XCTAssertEqual(output.paper.height, output.info.paperSize.height, accuracy: 0.2)
            let area = output.info.imageablePageBounds.intersection(output.paper)
            let scale = min(area.width / size.width, area.height / size.height)
            XCTAssertEqual(output.ink.width, size.width * scale, accuracy: 3)
            XCTAssertEqual(output.ink.height, size.height * scale, accuracy: 3)
            XCTAssertEqual(output.ink.midX, area.midX, accuracy: 2)
            XCTAssertEqual(output.ink.midY, area.midY, accuracy: 2)
        }
    }

    @MainActor
    func testPrintUsesFitScalingWithoutChangingSharedSettings() throws {
        let info = NSPrintInfo()
        info.scalingFactor = 0.45
        info.leftMargin = 72
        let output = try renderPrintedImage(size: NSSize(width: 60, height: 60), info: info)
        XCTAssertEqual(output.info.scalingFactor, 1)
        XCTAssertEqual(info.scalingFactor, 0.45)
        XCTAssertEqual(info.leftMargin, 72)
        let area = output.info.imageablePageBounds.intersection(output.paper)
        XCTAssertEqual(output.ink.width, min(area.width, area.height), accuracy: 3)
        XCTAssertEqual(output.ink.height, output.ink.width, accuracy: 1)
    }

    @MainActor
    func testPrintGeometryHandlesAsymmetricMarginsAndBorderlessPaper() {
        let paper = NSRect(x: 0, y: 0, width: 600, height: 800)
        let area = NSRect(x: 10, y: 30, width: 570, height: 720)
        let fitted = PrintableImageView.imageRect(imageSize: NSSize(width: 200, height: 400),
                                                  paperBounds: paper, imageableBounds: area)
        XCTAssertEqual(fitted, NSRect(x: 115, y: 30, width: 360, height: 720))
        for reported in [paper.insetBy(dx: -4, dy: -4), .zero] {
            let full = PrintableImageView.imageRect(imageSize: paper.size, paperBounds: paper, imageableBounds: reported)
            XCTAssertEqual(full, paper)
        }
        XCTAssertEqual(PrintableImageView.imageRect(imageSize: .zero, paperBounds: paper, imageableBounds: area), .zero)
    }

    @MainActor
    func testPrintedPagePreservesAllFourRotationsAndImageEdges() throws {
        let file = directory.appendingPathComponent("printed-rotation.pdf")
        try makeCroppedPDF(at: file, rotation: 0, markCorner: true)
        for turn in QuarterTurn.allCases {
            let cg = try XCTUnwrap(ImageDecoder.printBitmap(for: file, maxPixelSize: 400, rotation: turn))
            let image = NSImage(cgImage: cg, size: .zero)
            let info = NSPrintInfo()
            info.orientation = turn.swapsAxes ? .portrait : .landscape
            let output = try renderPrintedImage(size: image.size, info: info, image: image)
            XCTAssertEqual(output.ink.width / output.ink.height, CGFloat(cg.width) / CGFloat(cg.height), accuracy: 0.01)
            let area = output.info.imageablePageBounds.intersection(output.paper)
            XCTAssertTrue(abs(output.ink.width - area.width) <= 3 || abs(output.ink.height - area.height) <= 3)
            for (index, point) in [(0.25, 0.25), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)].enumerated() {
                let x = Int(output.ink.minX + output.ink.width * point.0)
                let y = Int(CGFloat(output.bitmap.pixelsHigh) - output.ink.maxY + output.ink.height * point.1)
                let color = try XCTUnwrap(output.bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                // The print pipeline color-manages RGB. Verify the corner's hue
                // and position without requiring the source's exact RGB values.
                let blueOverGreen = color.blueComponent - color.greenComponent
                if index == turn.rawValue {
                    XCTAssertGreaterThan(blueOverGreen, 0.5)
                } else {
                    XCTAssertLessThan(blueOverGreen, -0.5)
                }
            }
        }
    }

    @MainActor
    private func renderPrintedImage(size: NSSize, info: NSPrintInfo, image source: NSImage? = nil,
                                    changeSettings: ((NSPrintInfo) -> Void)? = nil) throws
        -> (ink: NSRect, paper: NSRect, info: NSPrintInfo, bitmap: NSBitmapImageRep) {
        // Use the actual print operation's Save-to-PDF path, never a printer or screenshot.
        let image = source ?? NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        let operation = PrintableImageView.operation(image: image, printInfo: info)
        XCTAssertTrue(operation.printPanel.options.contains([.showsPaperSize, .showsOrientation]))
        changeSettings?(operation.printInfo)
        let url = directory.appendingPathComponent("print-\(UUID().uuidString).pdf")
        operation.printInfo.jobDisposition = .save
        operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        XCTAssertTrue(operation.run())
        let attachment = XCTAttachment(data: try Data(contentsOf: url), uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Printed page"
        add(attachment)
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 1)
        let page = try XCTUnwrap(document.page(at: 1))
        let paper = page.getBoxRect(.mediaBox)
        let width = Int(paper.width.rounded(.up)), height = Int(paper.height.rounded(.up))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard pixels[offset] < 240 || pixels[offset + 1] < 240 || pixels[offset + 2] < 240 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThan(maxX, minX)
        // Bitmap rows are top-down; print/page coordinates are bottom-up.
        let ink = NSRect(x: minX, y: height - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        return (ink, paper, operation.printInfo, bitmap)
    }

    @MainActor
    func testClosingStoreCancelsQueuedPrintAndMetadataWithoutDeallocation() async throws {
        let url = directory.appendingPathComponent("closing.png")
        // Invalid pixels keep a failing implementation from opening a print
        // panel; its late failure would still overwrite the cleared state.
        try Data([0x01]).write(to: url)
        let store = ImageBrowserStore()
        ImageDecodeQueue.prints.isSuspended = true
        defer { ImageDecodeQueue.prints.isSuspended = false }
        store.open(file: url)
        store.printSelectedImage()
        XCTAssertTrue(store.isPreparingPrint)
        store.cancelPendingWork()
        XCTAssertFalse(store.isPreparingPrint)
        XCTAssertFalse(store.isScanning)
        XCTAssertNil(store.status)
        ImageDecodeQueue.prints.isSuspended = false
        for _ in 0..<200 where ImageDecodeQueue.prints.operationCount > 0 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(ImageDecodeQueue.prints.operationCount, 0)
        XCTAssertNil(store.status, "Closing must invalidate a retained store's late print callback")
        XCTAssertNil(store.originalPixelSize)
    }

    func testPrintBitmapRemainsBoundedAndHonorsCancellation() throws {
        let file = directory.appendingPathComponent("print.png")
        try makePNG(at: file, width: 2_400, height: 1_200)
        let bitmap = try XCTUnwrap(ImageDecoder.printBitmap(for: file, maxPixelSize: 2_048))
        XCTAssertEqual(bitmap.width, 2_048)
        XCTAssertEqual(bitmap.height, 1_024)
        XCTAssertNil(ImageDecoder.printBitmap(for: file, maxPixelSize: 2_048, isCancelled: { true }))
    }

    func testReleaseUpdateOnlyAcceptsNewStableVersionsFromLumaViewRepository() throws {
        let installed = try XCTUnwrap(ReleaseVersion(tag: "1.2.1"))
        let release = GitHubRelease(
            tagName: "v1.3.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/ixiehao/LumaView/releases/tag/v1.3.0")),
            draft: false,
            prerelease: false
        )

        XCTAssertEqual(release.update(newerThan: installed, expectedRepositoryPath: "ixiehao/LumaView")?.version, "v1.3.0")
        XCTAssertNil(GitHubRelease(
            tagName: "v9.0.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/other/LumaView/releases/tag/v9.0.0")),
            draft: false,
            prerelease: false
        ).update(newerThan: installed, expectedRepositoryPath: "ixiehao/LumaView"))
        XCTAssertNil(GitHubRelease(
            tagName: "v1.4.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/ixiehao/LumaView/releases/tag/v1.4.0")),
            draft: false,
            prerelease: true
        ).update(newerThan: installed, expectedRepositoryPath: "ixiehao/LumaView"))
        XCTAssertNil(GitHubRelease(
            tagName: "1.2.1",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/ixiehao/LumaView/releases/tag/v1.2.1")),
            draft: false,
            prerelease: false
        ).update(newerThan: installed, expectedRepositoryPath: "ixiehao/LumaView"))
    }

    @MainActor
    func testUpdateFallsBackToOfficialLatestReleaseWhenAPIIsUnavailable() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateFallbackURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let suite = "LumaViewTests.update-fallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(currentVersion: ReleaseVersion(tag: "1.0.0"), session: session, defaults: defaults)
        await checker.checkForUpdate(force: true, announceResult: true)
        XCTAssertEqual(checker.notice, .available)
        XCTAssertEqual(checker.availableUpdate?.version, "v1.3.2")
        XCTAssertEqual(checker.availableUpdate?.downloadURL.absoluteString, "https://github.com/ixiehao/LumaView/releases/tag/v1.3.2")
    }

    @MainActor
    func testDownloadAndQuitRequiresAnUpdateAndSuccessfulBrowserHandoff() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateFallbackURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let suite = "LumaViewTests.download-quit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var events: [String] = []
        var acceptsURL = false
        let checker = UpdateChecker(currentVersion: ReleaseVersion(tag: "1.0.0"), session: session,
            defaults: defaults, openURL: { url in
                XCTAssertEqual(url.absoluteString, "https://github.com/ixiehao/LumaView/releases/tag/v1.3.2")
                events.append("open")
                return acceptsURL
            }, quitApplication: { events.append("quit") })
        XCTAssertFalse(checker.openDownloadAndQuit())
        XCTAssertTrue(events.isEmpty)
        await checker.checkForUpdate(force: true)
        XCTAssertFalse(checker.openDownloadAndQuit())
        XCTAssertEqual(events, ["open"], "Failed handoff must preserve all viewer windows")
        XCTAssertEqual(checker.notice, .downloadUnavailable)
        acceptsURL = true
        events.removeAll()
        XCTAssertTrue(checker.openDownloadPage())
        XCTAssertEqual(events, ["open"], "Viewing a release must preserve all viewer windows")
        events.removeAll()
        XCTAssertTrue(checker.openDownloadAndQuit())
        XCTAssertEqual(events, ["open", "quit"], "Quit normally only after the browser accepts the page")
    }

    @MainActor
    func testUpdateFallbackRejectsUnexpectedRedirect() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnsafeUpdateFallbackURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let suite = "LumaViewTests.update-unsafe.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(currentVersion: ReleaseVersion(tag: "1.0.0"), session: session, defaults: defaults)
        await checker.checkForUpdate(force: true, announceResult: true)
        XCTAssertEqual(checker.notice, .unavailable)
        XCTAssertNil(checker.availableUpdate)
    }

    @MainActor
    func testUpdateIntervalPersistsAcrossCheckerInstances() async throws {
        let suiteName = "LumaViewTests.update-interval.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        UpdateCheckURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let referenceDate = Date(timeIntervalSinceReferenceDate: 123_456)
        let key = "last-checked"

        let first = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.2.1"),
            session: session,
            defaults: defaults,
            lastCheckedDefaultsKey: key,
            now: { referenceDate }
        )
        await first.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1)
        XCTAssertEqual(defaults.object(forKey: key) as? Date, referenceDate)

        let second = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.2.1"),
            session: session,
            defaults: defaults,
            lastCheckedDefaultsKey: key,
            now: { referenceDate.addingTimeInterval(60) }
        )
        await second.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1, "A relaunch inside the interval must not call GitHub again")

        let due = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.2.1"),
            session: session,
            defaults: defaults,
            lastCheckedDefaultsKey: key,
            now: { referenceDate.addingTimeInterval(12 * 60 * 60) }
        )
        await due.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 2)
    }

    @MainActor
    func testManualUpdateJoinsAutomaticCheckAndDismissesBanner() async throws {
        let suite = "LumaViewTests.updates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        UpdateCheckURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let checker = UpdateChecker(currentVersion: ReleaseVersion(tag: "1.0.0"), session: session, defaults: defaults)
        var notices: [UpdateCheckNotice] = []
        checker.noticeHandler = { notices.append($0) }
        let automatic = Task { await checker.checkForUpdate() }
        for _ in 0..<100 where !checker.isChecking { await Task.yield() }
        XCTAssertTrue(checker.isChecking)
        await checker.checkForUpdate(force: true, announceResult: true)
        await automatic.value
        XCTAssertFalse(checker.isChecking)
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1)
        XCTAssertEqual(notices, [.available])
        XCTAssertTrue(checker.showsUpdateBanner)
        checker.dismissBanner()
        XCTAssertFalse(checker.showsUpdateBanner)
        XCTAssertTrue(checker.hasUpdate, "Dismissal must not remove the settings/help download action")
        await checker.checkForUpdate(force: true)
        XCTAssertFalse(checker.showsUpdateBanner, "The same version must stay dismissed")
        let current = UpdateChecker(currentVersion: ReleaseVersion(tag: "1.2.1"), session: session, defaults: defaults)
        await current.checkForUpdate(force: true, announceResult: true)
        XCTAssertEqual(current.notice, .upToDate)
        let failure = UpdateChecker(session: session, releaseURL: URL(string: "https://example.invalid/fail")!, defaults: defaults)
        await failure.checkForUpdate(force: true, announceResult: true)
        XCTAssertEqual(failure.notice, .unavailable)
        XCTAssertFalse(failure.isChecking)
    }

    @MainActor
    func testUpdateCheckRecoversWhenTheSystemClockMovesBackwards() async throws {
        let suiteName = "LumaViewTests.update-clock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let referenceDate = Date(timeIntervalSinceReferenceDate: 123_456)
        let key = "last-checked"
        defaults.set(referenceDate.addingTimeInterval(24 * 60 * 60), forKey: key)

        UpdateCheckURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let checker = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.2.1"),
            session: session,
            defaults: defaults,
            lastCheckedDefaultsKey: key,
            now: { referenceDate }
        )

        await checker.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1,
                       "A future persisted timestamp must not suppress update checks")
        XCTAssertEqual(defaults.object(forKey: key) as? Date, referenceDate)
        await checker.checkForUpdate()
        XCTAssertEqual(UpdateCheckURLProtocol.requestCount, 1,
                       "A successful check must restore the normal throttle")
    }

    @MainActor
    func testReopeningChangedFileRefreshesDimensionsAndRenderRequest() async throws {
        let url = directory.appendingPathComponent("edited.png")
        try makePNG(at: url, width: 240, height: 120)
        let browser = ImageBrowserStore()
        browser.open(url: url)
        for _ in 0..<200 {
            if browser.originalPixelSize != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(browser.originalPixelSize, CGSize(width: 240, height: 120))
        let firstRequest = ImageRenderRequest(
            url: browser.selectedURL, maxPixelSize: 1_024, selectionGeneration: browser.selectionGeneration
        )
        let firstImage = try XCTUnwrap(ImageDecoder.renderedImage(for: firstRequest))
        XCTAssertEqual(ViewerGeometry.decodedSize(for: firstImage), CGSize(width: 240, height: 120))

        try makePNG(at: url, width: 120, height: 240)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        browser.open(url: url)
        let reopenedRequest = ImageRenderRequest(
            url: browser.selectedURL, maxPixelSize: 1_024, selectionGeneration: browser.selectionGeneration
        )
        XCTAssertNotEqual(firstRequest, reopenedRequest, "A same-path reopen must restart the canvas task")
        for _ in 0..<200 {
            if browser.originalPixelSize != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(browser.originalPixelSize, CGSize(width: 120, height: 240))
        let reopenedImage = try XCTUnwrap(ImageDecoder.renderedImage(for: reopenedRequest))
        XCTAssertEqual(ViewerGeometry.decodedSize(for: reopenedImage), CGSize(width: 120, height: 240))
        // Selection identity must not fragment the shared file-fingerprint cache.
        let anotherWindowRequest = ImageRenderRequest(url: url, maxPixelSize: 1_024)
        XCTAssertTrue(reopenedImage === ImageDecoder.renderedImage(for: anotherWindowRequest))
    }

    func testStoreNavigationZoomAndRotationStayBounded() async throws {
        try makePNG(at: directory.appendingPathComponent("photo-1.png"), width: 96, height: 64)
        try makePNG(at: directory.appendingPathComponent("photo-2.png"), width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        let folder = directory!
        await MainActor.run { store.open(folder: folder, selecting: nil) }
        try await Self.waitForScan(store)
        let nextURL = try await MainActor.run { try XCTUnwrap(store.files.dropFirst().first?.url) }
        try await Self.waitForNavigationPreview(at: nextURL)

        let result = await MainActor.run { () -> (Int, Int?, CGFloat, QuarterTurn) in
            for _ in 0..<10 { store.next() }
            for _ in 0..<10 { store.previous() }
            for _ in 0..<160 { store.zoomIn() }
            for _ in 0..<320 { store.zoomOut() }
            for _ in 0..<4 { store.rotate(by: 90) }
            return (store.files.count, store.selectedIndex, store.zoom, store.quarterTurn)
        }

        XCTAssertEqual(result.0, 2)
        XCTAssertEqual(result.1, 0)
        XCTAssertEqual(result.2, 0.15)
        XCTAssertEqual(result.3, .zero)

        let leftThenRight = await MainActor.run { () -> QuarterTurn in
            store.rotate(by: -90)
            XCTAssertEqual(store.quarterTurn, .counterClockwise)
            store.rotate(by: 90)
            return store.quarterTurn
        }
        XCTAssertEqual(leftThenRight, .zero)
    }

    @MainActor
    func testCanvasRenderingSuspensionKeepsDocumentStateButReleasesVisibleFrameIntent() {
        let browser = ImageBrowserStore()
        XCTAssertFalse(browser.isCanvasRenderingSuspended)
        browser.suspendCanvasRendering()
        XCTAssertTrue(browser.isCanvasRenderingSuspended)
        browser.resumeCanvasRendering()
        XCTAssertFalse(browser.isCanvasRenderingSuspended)
    }

    @MainActor
    func testFullScreenOcclusionKeepsCanvasWhileMinimizationStillSuspendsIt() async throws {
        let pdf = directory.appendingPathComponent("fullscreen-visibility.pdf")
        try makePDF(at: pdf)
        let browser = ImageBrowserStore()
        defer { browser.cancelPendingWork(); browser.suspendCanvasRendering() }
        browser.open(file: pdf)
        try await waitForPageSize(browser, CGSize(width: 600, height: 400))
        browser.nextPage()
        try await waitForPageSize(browser, CGSize(width: 400, height: 600))
        browser.rotate(by: 90)
        browser.zoom = 1.75
        let selection = browser.selectedURL
        let generation = browser.selectionGeneration
        let rotation = browser.quarterTurn
        XCTAssertEqual(browser.pdfPageIndex, 1)

        func visibility(_ name: String, minimized: Bool = false, fullScreen: Bool = false,
                        transitioning: Bool = false, occluded: Bool, suspended: Bool) {
            browser.updateCanvasVisibility(isMiniaturized: minimized, isFullScreen: fullScreen,
                isTransitioning: transitioning, isOccluded: occluded)
            XCTAssertEqual(browser.isCanvasRenderingSuspended, suspended, name)
            XCTAssertEqual(browser.selectedURL, selection, "\(name): retain the selected document")
            XCTAssertEqual(browser.selectionGeneration, generation, "\(name): visibility must not reload the document")
            XCTAssertEqual(browser.pdfPageIndex, 1, "\(name): retain the reading position")
            XCTAssertEqual(browser.quarterTurn, rotation, "\(name): retain rotation")
            XCTAssertEqual(browser.zoom, 1.75, "\(name): retain zoom")
        }

        // Reproduce the late occlusion notification after the full-screen
        // transition, without creating a Space or taking over the desktop.
        visibility("Ordinary visible window", occluded: false, suspended: false)
        visibility("Entering full screen", transitioning: true, occluded: true, suspended: false)
        visibility("Full-screen transition completed", fullScreen: true, occluded: true, suspended: false)
        visibility("Late full-screen occlusion", fullScreen: true, occluded: true, suspended: false)
        visibility("Minimization wins over full screen", minimized: true, fullScreen: true,
                   transitioning: true, occluded: true, suspended: true)
        visibility("Restored full-screen window", fullScreen: true, occluded: true, suspended: false)
        visibility("Exiting full screen", transitioning: true, occluded: true, suspended: false)
        visibility("Ordinary occluded window", occluded: true, suspended: true)
        visibility("Ordinary window revealed", occluded: false, suspended: false)
    }

    func testOpeningAFinderFileSelectsItAndKeepsFolderNavigation() async throws {
        try makePNG(at: directory.appendingPathComponent("photo-1.png"), width: 96, height: 64)
        let second = directory.appendingPathComponent("photo-2.png")
        try makePNG(at: second, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(url: second) }
        try await Self.waitForScan(store)

        let state = await MainActor.run { (store.selectedFile?.url, store.files.count, store.hasNext) }
        XCTAssertEqual(state.0, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(state.1, 2)
        XCTAssertFalse(state.2)
    }

    func testFinderFileIsSelectedBeforeItsFolderIndexCompletes() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(url: second) }
        let immediateSelection = await MainActor.run { store.selectedURL }
        XCTAssertEqual(immediateSelection, second.standardizedFileURL.resolvingSymlinksInPath())

        try await Self.waitForScan(store)
        let indexedState = await MainActor.run { (store.files.count, store.selectedURL, store.positionText) }
        XCTAssertEqual(indexedState.0, 2)
        XCTAssertEqual(indexedState.1, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(indexedState.2, "2 / 2")
    }

    func testExplicitlyOpenedHiddenImageSurvivesIndexingAndCanNavigate() async throws {
        let hidden = directory.appendingPathComponent(".selected.png")
        let visible = directory.appendingPathComponent("visible.png")
        try makePNG(at: hidden, width: 96, height: 64)
        try makePNG(at: visible, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        await MainActor.run { store.open(url: hidden) }
        try await Self.waitForScan(store)
        let selected = await MainActor.run { store.selectedURL }
        XCTAssertEqual(selected, hidden.standardizedFileURL.resolvingSymlinksInPath())
        let names = await MainActor.run { store.files.map(\.name) }
        XCTAssertEqual(Set(names), Set([hidden.lastPathComponent, visible.lastPathComponent]))
        await MainActor.run {
            if store.hasNext { store.next() } else { store.previous() }
        }
        let navigated = await MainActor.run { store.selectedURL }
        XCTAssertEqual(navigated, visible.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testNavigationPressedDuringFolderScanIsAppliedAfterIndexing() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        let store = await MainActor.run { ImageBrowserStore() }

        // Execute both actions in one main-actor turn. The folder index cannot complete
        // until that turn yields, which is the real Finder/Open File edge case.
        await MainActor.run {
            store.open(url: first)
            store.next()
        }
        try await Self.waitForScan(store)

        let selected = await MainActor.run { store.selectedURL }
        XCTAssertEqual(selected, second.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testOpeningAnotherWindowDoesNotClearExistingNavigationPreview() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        XCTAssertNotNil(ImageDecoder.navigationPreview(for: first))

        let otherWindow = await MainActor.run { ImageBrowserStore() }
        await MainActor.run { otherWindow.open(url: second) }
        XCTAssertNotNil(ImageMemoryCache.shared.navigationPreview(for: first))
    }

    func testSeparateWindowStoresKeepTheirOwnOpenedImage() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        let third = directory.appendingPathComponent("photo-3.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        try makePNG(at: third, width: 96, height: 64)
        let firstWindow = await MainActor.run { ImageBrowserStore() }
        let secondWindow = await MainActor.run { ImageBrowserStore() }

        await MainActor.run {
            firstWindow.open(url: first)
            secondWindow.open(url: second)
        }
        try await Self.waitForScan(firstWindow)
        try await Self.waitForScan(secondWindow)

        let selections = await MainActor.run { (firstWindow.selectedURL, secondWindow.selectedURL) }
        XCTAssertEqual(selections.0, first.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(selections.1, second.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testNavigatingOneWindowNeverChangesAnotherWindowSelection() async throws {
        let first = directory.appendingPathComponent("photo-1.png")
        let second = directory.appendingPathComponent("photo-2.png")
        let third = directory.appendingPathComponent("photo-3.png")
        try makePNG(at: first, width: 96, height: 64)
        try makePNG(at: second, width: 96, height: 64)
        try makePNG(at: third, width: 96, height: 64)
        let firstWindow = await MainActor.run { ImageBrowserStore() }
        let secondWindow = await MainActor.run { ImageBrowserStore() }

        await MainActor.run {
            firstWindow.open(url: first)
            secondWindow.open(url: third)
        }
        try await Self.waitForScan(firstWindow)
        try await Self.waitForScan(secondWindow)

        await MainActor.run { firstWindow.next() }
        let selections = await MainActor.run { (firstWindow.selectedURL, secondWindow.selectedURL) }
        XCTAssertEqual(selections.0, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(selections.1, third.standardizedFileURL.resolvingSymlinksInPath())
    }

    private func makeFile(_ name: String) throws {
        try Data("fixture".utf8).write(to: directory.appendingPathComponent(name))
    }

    private func makeJPEGWithEXIF(at url: URL, orientation: Int = 1) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 320,
            pixelsHigh: 240,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let image = try XCTUnwrap(bitmap.cgImage)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Luma Labs",
                kCGImagePropertyTIFFModel: "LumaCam 1"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:17 12:34:56",
                kCGImagePropertyExifLensModel: "Luma 50mm f/1.8",
                kCGImagePropertyExifExposureTime: 1.0 / 125.0,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifISOSpeedRatings: [200],
                kCGImagePropertyExifFocalLength: 50.0
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makePNG(at url: URL, width: Int, height: Int) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private static func waitForScan(_ store: ImageBrowserStore) async throws {
        for _ in 0..<200 {
            if await MainActor.run(body: { !store.isScanning }) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for the folder scan")
    }

    private static func waitForNavigationPreview(at url: URL) async throws {
        for _ in 0..<200 {
            if ImageMemoryCache.shared.navigationPreview(for: url) != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for adjacent-image prefetch")
    }
}

private class UpdateFallbackURLProtocol: URLProtocol {
    class var resultURL: URL { URL(string: "https://github.com/ixiehao/LumaView/releases/tag/v1.3.2")! }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let isAPI = request.url?.host == "api.github.com"
        let response = HTTPURLResponse(url: isAPI ? request.url! : type(of: self).resultURL,
                                       statusCode: isAPI ? 403 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class UnsafeUpdateFallbackURLProtocol: UpdateFallbackURLProtocol {
    override class var resultURL: URL { URL(string: "https://example.com/ixiehao/LumaView/releases/tag/v9.0.0")! }
}

private final class UpdateCheckURLProtocol: URLProtocol {
    private static let counter = TestRequestCounter()

    static var requestCount: Int { counter.value }
    static func reset() { counter.reset() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.counter.increment()

        let body = Data(#"{"tag_name":"v1.2.1","html_url":"https://github.com/ixiehao/LumaView/releases/tag/v1.2.1","draft":false,"prerelease":false}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: request.url?.path == "/fail" ? 503 : 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        // URLSession already invokes this on its protocol-loading thread.
        // A short deterministic delay lets concurrent update checks join; keep
        // the callback on that thread instead of sending URLProtocol across queues.
        Thread.sleep(forTimeInterval: 0.05)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// These windows are never ordered on screen. Only the receiver under test
/// considers itself key; no macOS event is posted and system focus is unchanged.
@MainActor
private final class PDFKeyboardTestWindow: LumaDocumentWindow {
    var receivesTestKeys = true
    override var isKeyWindow: Bool { receivesTestKeys }
}

@MainActor
private final class TrashKeyboardTestWindow: LumaDocumentWindow {
    var receivesTestKeys = true
    var trashRequests = 0
    override var isKeyWindow: Bool { receivesTestKeys }
    override func moveSelectedFileToTrash(_ l: L10n) { trashRequests += 1 }
}

@MainActor
private final class TrashNoticeTestWindow: LumaDocumentWindow {
    var alerts: [NSAlert] = []
    var response: ((NSApplication.ModalResponse) -> Void)?
    override func presentTrashAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        alerts.append(alert)
        response = completion
    }
}

@MainActor
private final class TestDefaultApplicationHandler: DefaultApplicationHandling {
    var applications: [String: URL] = [:]
    var requests: [String] = []
    var errors: [String: Error] = [:]
    var ignored: Set<String> = []

    func applicationURL(for type: UTType) -> URL? { applications[type.identifier] }
    func setApplication(at url: URL, for type: UTType) async throws {
        requests.append(type.identifier)
        await Task.yield()
        if let error = errors[type.identifier] { throw error }
        if !ignored.contains(type.identifier) { applications[type.identifier] = url }
    }
}

// The URLProtocol callbacks and test assertions use different threads.
private final class TestRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        count = 0
    }
}
