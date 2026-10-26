import AppKit
import Foundation
import Testing
@testable import Xmac

@Suite struct ConverterServiceProviderTests {
    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("xmac-test-\(UUID().uuidString)"))
    }

    @Test func readsModernFileURLs() {
        let board = privatePasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        let urls = [URL(fileURLWithPath: "/tmp/one.png"), URL(fileURLWithPath: "/tmp/two.pdf")]
        #expect(board.writeObjects(urls as [NSURL]))
        #expect(ConverterServiceProvider.fileURLs(from: board).map(\.path) == ["/tmp/one.png", "/tmp/two.pdf"])
    }

    @Test func readsLegacyFilenamesList() {
        let board = privatePasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        let type = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        board.setPropertyList(["/tmp/legacy one.txt", "/tmp/two.txt"], forType: type)
        #expect(ConverterServiceProvider.fileURLs(from: board).map(\.path) == ["/tmp/legacy one.txt", "/tmp/two.txt"])
    }

    @Test func mergesBothFormatsWithoutDuplicates() {
        let board = privatePasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.txt")] as [NSURL])
        board.setPropertyList(["/tmp/a.txt", "/tmp/b.txt"], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        #expect(ConverterServiceProvider.fileURLs(from: board).map(\.path) == ["/tmp/a.txt", "/tmp/b.txt"])
    }

    @Test func ignoresPlainTextAndEmptyBoards() {
        let board = privatePasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("hello", forType: .string)
        #expect(ConverterServiceProvider.fileURLs(from: board).isEmpty)
    }
}
