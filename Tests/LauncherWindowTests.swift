import AppKit
import Carbon
import Testing
@testable import Xmac

@Suite(.serialized) struct LauncherWindowTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_LAUNCHER_UI"] == "1"))
    func shortcutCollisionKeepsOldRegistration() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "Launcher.Shortcut")
        let owner = QuickLauncher.shared
        defer {
            owner.stop()
            if let saved { defaults.set(saved, forKey: "Launcher.Shortcut") }
            else { defaults.removeObject(forKey: "Launcher.Shortcut") }
        }
        owner.start()
        try #require(owner.shortcutMessage.hasPrefix("Mở nhanh bằng"))
        let original = owner.shortcut
        let other = try #require(LauncherShortcut.allCases.first { $0 != original })
        var reserved: EventHotKeyRef?
        let status = RegisterEventHotKey(other.keyCode, other.modifiers,
            EventHotKeyID(signature: 0x584D5453, id: 1), GetApplicationEventTarget(), 0, &reserved)
        try #require(status == noErr)
        defer { if let reserved { UnregisterEventHotKey(reserved) } }
        owner.setShortcut(other)
        #expect(owner.shortcut == original)
        #expect(owner.shortcutMessage.hasPrefix("Không thể dùng"))
        if let key = reserved { UnregisterEventHotKey(key); reserved = nil }
        owner.setShortcut(other)
        #expect(owner.shortcut == other)
        #expect(owner.shortcutMessage.hasPrefix("Mở nhanh bằng"))
    }

    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_LAUNCHER_UI"] == "1"))
    func panelSearchAndEscapeWorkInADesktopSession() async throws {
        _ = NSApplication.shared
        QuickLauncher.shared.show()
        defer { QuickLauncher.shared.hide() }
        let panel = try #require(NSApp.windows.first { $0.title == "Mở nhanh Xmac" })
        #expect(panel.isVisible)
        #expect(!panel.canBecomeMain)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(try #require(panel.contentView))
        let search = try #require(views.compactMap { $0 as? NSSearchField }.first)
        let table = try #require(views.compactMap { $0 as? NSTableView }.first)
        search.stringValue = "o dia"
        QuickLauncher.shared.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        #expect(table.numberOfRows >= 1)
        #expect(table.selectedRow == 0)
        // Render the actual AppKit hierarchy for local visual inspection.
        if let content = panel.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: "/tmp/xmac-launcher-preview.png"))
            }
        }
        panel.cancelOperation(nil)
        #expect(!panel.isVisible)
        QuickLauncher.shared.show()
        #expect(panel.isVisible)
    }
}
