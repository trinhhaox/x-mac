import Testing
import Foundation
@testable import Xmac

@Suite struct OutputPathReserverTests {
    @Test func concurrentReservesAreDistinct() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reserver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reserver = OutputPathReserver()

        let urls = await withTaskGroup(of: URL.self) { group in
            for _ in 0..<20 { group.addTask { await reserver.reserve(fileName: "out.mp4", in: dir) } }
            var all: [URL] = []
            for await url in group { all.append(url) }
            return all
        }
        #expect(Set(urls.map(\.path)).count == 20)
        #expect(urls.allSatisfy { $0.pathExtension == "mp4" })
    }

    @Test func avoidsExistingFilesAndReusesAfterRelease() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reserver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appendingPathComponent("a.txt"))
        let reserver = OutputPathReserver()

        let first = await reserver.reserve(fileName: "a.txt", in: dir)
        #expect(first.lastPathComponent == "a 1.txt")
        await reserver.release(first)
        let again = await reserver.reserve(fileName: "a.txt", in: dir)
        #expect(again == first)
    }

    @Test func sanitizesUnsafeNames() async {
        let dir = FileManager.default.temporaryDirectory
        let url = await OutputPathReserver().reserve(fileName: "../evil/x:y.png", in: dir)
        #expect(url.deletingLastPathComponent().path == dir.path)
    }
}
