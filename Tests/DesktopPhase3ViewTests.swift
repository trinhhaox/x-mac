import AppKit
import SwiftUI
import Testing
@testable import Xmac

@Suite struct DesktopPhase3ViewTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_DESKTOP_UI"] == "1"))
    func folderWatcherRefreshesPreviewWithoutMovingFiles() async throws {
        let name = "XmacWatchTest.\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: name)!
        let organizer = DownloadsOrganizer(root: root, store: root.appendingPathComponent(".journal/undo.json"), defaults: defaults)
        defer {
            organizer.stopWatching(); defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        organizer.startWatching()
        for _ in 0..<100 {
            if organizer.message.hasPrefix("Xem trước:") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try #require(organizer.preview.isEmpty)
        try #require(organizer.message.hasPrefix("Xem trước:"))
        let file = root.appendingPathComponent("new.pdf")
        try Data("watch".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10)], ofItemAtPath: file.path)
        for _ in 0..<400 {
            if organizer.preview.contains(where: { $0.source.lastPathComponent == "new.pdf" }) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(organizer.preview.contains { $0.source.lastPathComponent == "new.pdf" })
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(organizer.undoCount == 0)
    }

    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_DESKTOP_UI"] == "1"))
    func renderNewViewsUsingOnlyIsolatedSampleData() async throws {
        _ = NSApplication.shared
        let originalTab = AppState.shared.selectedTab
        let originalLanguage = LocalizationManager.shared.language
        let name = "XmacDesktopViewTest.\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: name)!
        let board = NSPasteboard.withUniqueName()
        let history = ClipboardHistory(defaults: defaults, store: root.appendingPathComponent("clipboard/history.json"), board: board, onCopy: {})
        let organizer = DownloadsOrganizer(root: root, store: root.appendingPathComponent("organizer/undo.json"), defaults: defaults)
        defer {
            organizer.stopWatching(); history.stop(); board.releaseGlobally()
            AppState.shared.selectedTab = originalTab
            LocalizationManager.shared.language = originalLanguage
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        history.enabled = true
        board.clearContents(); board.setString("Xin chào Xmac — nội dung mẫu", forType: .string)
        history.poll(source: "vn.xmac.sample")
        try Data("sample".utf8).write(to: root.appendingPathComponent("bao-cao.pdf"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10)], ofItemAtPath: root.appendingPathComponent("bao-cao.pdf").path)
        organizer.refresh()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(history.items.count == 1)
        #expect(organizer.preview.count == 1)
        @MainActor func render<V: View>(_ view: V, path: String) async throws {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 30, y: 30, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.orderOut(nil); window.contentView = nil }
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            try await Task.sleep(nanoseconds: 600_000_000)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
        try await render(ClipboardHistoryView(history: history), path: "/tmp/xmac-clipboard-phase3.png")
        try await render(DownloadsOrganizerView(organizer: organizer), path: "/tmp/xmac-organizer-phase3.png")
        try await render(SettingsView(), path: "/tmp/xmac-settings-phase2.png")
        try await render(VietnameseIMEView(), path: "/tmp/xmac-ime-phase2.png")
        AppState.shared.selectedTab = .overview
        try await render(MainView(), path: "/tmp/xmac-main-phase3.png")
        LocalizationManager.shared.language = .english
        try await render(SettingsView(), path: "/tmp/xmac-settings-english.png")
        try await render(MainView(), path: "/tmp/xmac-main-english.png")
        organizer.requestApply()
        try Data("not part of the confirmed preview".utf8).write(to: root.appendingPathComponent("second.pdf"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10)], ofItemAtPath: root.appendingPathComponent("second.pdf").path)
        organizer.refresh()
        for _ in 0..<100 {
            if organizer.preview.count == 2 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(organizer.preview.count == 2)
        organizer.apply()
        for _ in 0..<100 {
            if !organizer.busy { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(organizer.undoCount == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("second.pdf").path))
        try await render(DownloadsOrganizerView(organizer: organizer), path: "/tmp/xmac-organizer-undo-phase3.png")
        organizer.undo()
        for _ in 0..<100 {
            if !organizer.busy { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(organizer.undoCount == 0)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("bao-cao.pdf").path))
    }
}
