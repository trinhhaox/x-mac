import AppKit
import Testing
@testable import Xmac

@MainActor @Suite(.serialized) struct ClipboardHistoryTests {
    private func fixture(onCopy: @escaping () -> Void = {}) -> (ClipboardHistory, NSPasteboard, URL, UserDefaults, String) {
        let name = "XmacClipboardTest.\(UUID().uuidString)"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let board = NSPasteboard.withUniqueName()
        let defaults = UserDefaults(suiteName: name)!
        return (ClipboardHistory(defaults: defaults, store: folder.appendingPathComponent("history.json"), board: board, onCopy: onCopy), board, folder, defaults, name)
    }
    private func cleanup(_ history: ClipboardHistory, _ board: NSPasteboard, _ folder: URL, _ defaults: UserDefaults, _ name: String) {
        history.stop(); board.releaseGlobally(); defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: folder)
    }
    private func write(_ text: String, to board: NSPasteboard) { board.clearContents(); board.setString(text, forType: .string) }

    @Test func consentSkipsOldContentAndDisabledCopies() {
        let (history, board, folder, defaults, name) = fixture()
        defer { cleanup(history, board, folder, defaults, name) }
        write("before consent", to: board)
        history.poll(source: "test")
        #expect(history.items.isEmpty)
        history.enabled = true
        history.poll(source: "test")
        #expect(history.items.isEmpty)
        write("allowed", to: board); history.poll(source: "test")
        #expect(history.items.first?.text == "allowed")
        history.enabled = false
        write("disabled", to: board)
        history.enabled = true; history.poll(source: "test")
        #expect(history.items.count == 1)
    }

    @Test func concealedSourcesAndSecureInputAreSkipped() {
        let (history, board, folder, defaults, name) = fixture()
        defer { cleanup(history, board, folder, defaults, name) }
        history.enabled = true
        write("secret", to: board)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        history.poll(source: "test")
        write("secure", to: board); history.poll(source: "test", secureInput: true)
        write("password manager", to: board); history.poll(source: "com.bitwarden.desktop")
        #expect(history.items.isEmpty)
        write("safe", to: board); history.poll(source: "test")
        #expect(history.items.count == 1)
    }

    @Test func richTextCanBeCopiedAsPlainTextWithoutRecapture() throws {
        let (history, board, folder, defaults, name) = fixture()
        defer { cleanup(history, board, folder, defaults, name) }
        history.enabled = true
        write("hello", to: board); board.setData(Data("<b>hello</b>".utf8), forType: .html)
        history.poll(source: "test")
        let item = try #require(history.items.first)
        #expect(item.html != nil)
        history.copy(item, plainText: true)
        #expect(board.string(forType: .string) == "hello")
        #expect(board.data(forType: .html) == nil)
        history.poll(source: "test")
        #expect(history.items.count == 1)
        history.clear(); history.flush()
        #expect(board.string(forType: .string) == "hello")
        #expect(history.items.isEmpty)
        #expect(try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: folder.appendingPathComponent("history.json"))).isEmpty)
    }

    @Test func retentionAndPinsSurviveRelaunch() throws {
        let (history, board, folder, defaults, name) = fixture()
        defer { cleanup(history, board, folder, defaults, name) }
        history.enabled = true
        let past = Date().addingTimeInterval(-8 * 86400)
        write("keep", to: board); history.poll(source: "test", now: past)
        let id = try #require(history.items.first?.id)
        history.togglePin(id)
        // Unpinned content older than seven days expires on restore.
        write("expire", to: board); history.poll(source: "test", now: past)
        history.flush()
        let restored = ClipboardHistory(defaults: defaults, store: folder.appendingPathComponent("history.json"), board: board)
        defer { restored.stop() }
        #expect(restored.items.count == 1)
        #expect(restored.items.first?.text == "keep")
        #expect(restored.items.first?.pinned == true)
        let attrs = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("history.json").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func duplicatesAndOversizedItemsAreNotStored() {
        let (history, board, folder, defaults, name) = fixture()
        defer { cleanup(history, board, folder, defaults, name) }
        history.enabled = true
        write("same", to: board); history.poll(source: "test")
        write("same", to: board); history.poll(source: "test")
        write(String(repeating: "x", count: ClipboardHistory.maxItemBytes + 1), to: board); history.poll(source: "test")
        #expect(history.items.count == 1)
    }

    @Test func expiredItemsArePrunedEvenWhenCaptureIsDisabled() {
        let (history, board, folder, defaults, name) = fixture()
        defer { cleanup(history, board, folder, defaults, name) }
        history.enabled = true
        write("old", to: board)
        history.poll(source: "test", now: Date().addingTimeInterval(-8 * 86400))
        #expect(history.items.count == 1)
        history.enabled = false
        history.poll(source: "test")
        #expect(history.items.isEmpty)
    }

    @Test func onlySuccessfulHistoryCopiesInvalidatePendingFinderCut() throws {
        var cancellations = 0
        let (history, board, folder, defaults, name) = fixture(onCopy: { cancellations += 1 })
        defer { cleanup(history, board, folder, defaults, name) }
        history.enabled = true
        write("history", to: board); history.poll(source: "test")
        #expect(cancellations == 0)
        history.copy(try #require(history.items.first))
        #expect(cancellations == 1)
        history.poll(source: "test"); history.clear()
        #expect(cancellations == 1)
    }

    @Test func imageAndFileListsCanBeCopiedWithoutReadingFileContents() throws {
        let (history, board, folder, defaults, name) = fixture()
        defer { cleanup(history, board, folder, defaults, name) }
        history.enabled = true
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        board.clearContents(); board.setData(png, forType: .png)
        history.poll(source: "test")
        let image = try #require(history.items.first)
        #expect(image.kind == .image)
        history.copy(image)
        #expect(board.data(forType: .png) == png)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("one.txt")
        try Data("file".utf8).write(to: file)
        board.clearContents(); board.writeObjects([file as NSURL])
        history.poll(source: "test")
        let files = try #require(history.items.first)
        #expect(files.kind == .files)
        #expect(files.paths == [file.path])
        try FileManager.default.removeItem(at: file)
        write("unchanged", to: board)
        history.copy(files)
        #expect(board.string(forType: .string) == "unchanged")
    }
}
