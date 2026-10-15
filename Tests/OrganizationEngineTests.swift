import Foundation
import Testing
@testable import Xmac

@Suite struct OrganizationEngineTests {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("XmacOrganizationTest-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent(".journal/undo.json"))
    }
    private func plan(_ root: URL) throws -> [OrganizationPreview] {
        try OrganizationEngine.preview(root: root, rules: OrganizationRule.defaults, now: Date().addingTimeInterval(10))
    }

    @Test func previewDoesNotMoveAndApplyAvoidsOverwriteThenUndoes() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try Data("original".utf8).write(to: root.appendingPathComponent("report.pdf"))
        let folder = root.appendingPathComponent("Tài liệu")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("existing".utf8).write(to: folder.appendingPathComponent("report.pdf"))
        let preview = try plan(root)
        #expect(preview.count == 1)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("report.pdf").path))
        let errors = try OrganizationEngine.apply(root: root, preview: preview, store: store)
        #expect(errors.isEmpty, "\(errors)")
        #expect(try String(contentsOf: folder.appendingPathComponent("report.pdf")) == "existing")
        #expect(try String(contentsOf: folder.appendingPathComponent("report 1.pdf")) == "original")
        #expect(try OrganizationEngine.load(store)?.moves.count == 1)
        let undoErrors = try OrganizationEngine.undo(store: store)
        #expect(undoErrors.isEmpty, "\(undoErrors)")
        #expect(try String(contentsOf: root.appendingPathComponent("report.pdf")) == "original")
        #expect(try OrganizationEngine.load(store)?.moves.isEmpty == true)
    }

    @Test func changedFilesAndSymbolicLinkTargetsAreNotMoved() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("report.pdf")
        try Data("before".utf8).write(to: file)
        let preview = try plan(root)
        try Data("after-change".utf8).write(to: file)
        #expect(try OrganizationEngine.apply(root: root, preview: preview, store: store).count == 1)
        let fresh = try plan(root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Tài liệu"), withDestinationURL: root)
        #expect(try OrganizationEngine.apply(root: root, preview: fresh, store: store).count == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func undoPreservesEditedFileAndExistingOriginal() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.pdf")
        try Data("before".utf8).write(to: source)
        _ = try OrganizationEngine.apply(root: root, preview: plan(root), store: store)
        let moved = try #require(OrganizationEngine.load(store)?.moves.first?.destination)
        try Data("edited".utf8).write(to: moved)
        #expect(try OrganizationEngine.undo(store: store).count == 1)
        #expect(try String(contentsOf: moved) == "edited")
        #expect(try OrganizationEngine.load(store)?.moves.count == 1)
    }

    @Test func traversalUnfinishedFilesAndSymlinkSourcesAreExcluded() throws {
        let (root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("part".utf8).write(to: root.appendingPathComponent("a.pdf.part"))
        try Data("fresh".utf8).write(to: root.appendingPathComponent("a.pdf"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("b.pdf"), withDestinationURL: root.appendingPathComponent("a.pdf"))
        #expect(try OrganizationEngine.preview(root: root, rules: OrganizationRule.defaults).isEmpty)
        #expect(try plan(root).count == 1)
        #expect(!OrganizationEngine.validFolder("../outside"))
        #expect(!OrganizationEngine.validFolder(".."))
        #expect(!OrganizationEngine.validFolder("/tmp"))
    }

    @Test func journalRecoversAnInterruptedMoveAndUndoDoesNotOverwriteOriginal() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.pdf")
        try Data("original".utf8).write(to: source)
        let identity = try OrganizationIdentity.read(source)
        let destination = root.appendingPathComponent("Tài liệu/a.pdf")
        try OrganizationEngine.save(.init(root: root, moves: [.init(source: source, destination: destination, identity: identity)]), to: store)
        #expect(try OrganizationEngine.undo(store: store).isEmpty)
        #expect(try String(contentsOf: source) == "original")
        _ = try OrganizationEngine.apply(root: root, preview: plan(root), store: store)
        try Data("new original".utf8).write(to: source)
        #expect(try OrganizationEngine.undo(store: store).count == 1)
        #expect(try String(contentsOf: source) == "new original")
        #expect(try String(contentsOf: destination) == "original")
    }
}
