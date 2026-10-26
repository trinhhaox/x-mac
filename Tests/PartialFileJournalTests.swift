import Foundation
import Testing
@testable import Xmac

@Suite struct PartialFileJournalTests {
    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func recognisesOnlyPartialNames() {
        func partial(_ name: String) -> Bool { PartialFileJournal.isPartial(URL(fileURLWithPath: "/x/\(name)")) }
        #expect(partial(".a.xmac-partial.pdf"))
        #expect(partial(".a.xmac-partial"))
        #expect(!partial("a.xmac-partial.pdf"))
        #expect(!partial(".hidden.pdf"))
        #expect(!partial("report.pdf"))
    }

    @Test func nextSessionRemovesLeftoversAndKeepsLookalikes() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("journal.json")
        let leftover = dir.appendingPathComponent(".a.xmac-partial.pdf")
        let finished = dir.appendingPathComponent(".b.xmac-partial.pdf")
        try Data("x".utf8).write(to: leftover)
        let crashed = PartialFileJournal(storeURL: store)
        crashed.record(leftover)
        crashed.record(finished)
        crashed.remove(finished)

        // A journal edited to point at a user file must not delete it.
        let precious = dir.appendingPathComponent("precious.pdf")
        try Data("keep".utf8).write(to: precious)
        let forged = try JSONEncoder().encode([precious.path: "old-session", leftover.path: "old-session"])
        try forged.write(to: store)

        let relaunched = PartialFileJournal(storeURL: store)
        #expect(relaunched.sweep() == 1)
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: precious.path))
        #expect(relaunched.sweep() == 0)
    }

    @Test func sweepSparesCurrentSessionEntries() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let live = dir.appendingPathComponent(".live.xmac-partial.mp4")
        try Data("x".utf8).write(to: live)
        let journal = PartialFileJournal(storeURL: dir.appendingPathComponent("journal.json"))
        journal.record(live)
        #expect(journal.sweep() == 0)
        #expect(FileManager.default.fileExists(atPath: live.path))
    }

    @Test func recordIgnoresNonPartialPaths() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("journal.json")
        PartialFileJournal(storeURL: store).record(dir.appendingPathComponent("report.pdf"))
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test func corruptJournalIsIgnored() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("journal.json")
        try Data("not json".utf8).write(to: store)
        #expect(PartialFileJournal(storeURL: store).sweep() == 0)
    }

    @Test func queueRecordsPartialAndClearsItAfterJob() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("journal.json")
        let journal = PartialFileJournal(storeURL: store)
        let source = dir.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: source)
        let log = EventLog()
        let converter = FakeConverter()
        let queue = ConversionQueue(registry: ConverterRegistry(converters: [converter], locator: BinaryLocator()), journal: journal) { log.record($0, $1) }
        let target = try #require(converter.targets(for: source).first)
        let id = UUID()
        await queue.enqueue(id: id, inputs: [source], target: target, preset: ConversionPreset())
        #expect(await log.wait { log.outcome(id) != nil })
        let saved = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: store))
        #expect(saved.isEmpty)
    }
}
