import Foundation
import Testing
@testable import Xmac

@Suite struct ConverterCLIJournalSweeperTests {
    private func write(_ paths: [String], pid: Int32, in dir: URL) throws -> URL {
        let url = ConverterCLIJournalSweeper.journalURL(pid: pid, in: dir)
        try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: paths.map { ($0, "s") })).write(to: url)
        return url
    }

    @Test func deadProcessJournalDeletesItsPartialsAndItself() throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let partial = dir.appendingPathComponent(".a.png.xmac-partial.png")
        let innocent = dir.appendingPathComponent("keep.png")
        FileManager.default.createFile(atPath: partial.path, contents: Data("x".utf8))
        FileManager.default.createFile(atPath: innocent.path, contents: Data("y".utf8))
        let journal = try write([partial.path, innocent.path], pid: 4242, in: dir)

        #expect(ConverterCLIJournalSweeper.sweep(in: dir, ownPID: 1, isAlive: { _ in false }) == 1)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        #expect(FileManager.default.fileExists(atPath: innocent.path))
        #expect(!FileManager.default.fileExists(atPath: journal.path))
    }

    @Test func liveAndOwnJournalsAreLeftAlone() throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let partial = dir.appendingPathComponent(".b.png.xmac-partial.png")
        FileManager.default.createFile(atPath: partial.path, contents: Data("x".utf8))
        let live = try write([partial.path], pid: 100, in: dir)
        let own = try write([partial.path], pid: 200, in: dir)

        #expect(ConverterCLIJournalSweeper.sweep(in: dir, ownPID: 200, isAlive: { $0 == 100 }) == 0)
        #expect(FileManager.default.fileExists(atPath: partial.path))
        #expect(FileManager.default.fileExists(atPath: live.path) && FileManager.default.fileExists(atPath: own.path))
    }

    @Test func corruptJournalIsDeletedWithoutCrash() throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = ConverterCLIJournalSweeper.journalURL(pid: 7, in: dir)
        try Data("not json".utf8).write(to: url)
        #expect(ConverterCLIJournalSweeper.sweep(in: dir, ownPID: 1, isAlive: { _ in false }) == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func realLivenessCheckKnowsSelfAndNonexistentPID() {
        #expect(ConverterCLIJournalSweeper.isProcessAlive(getpid()))
        #expect(!ConverterCLIJournalSweeper.isProcessAlive(Int32.max))
    }
}
