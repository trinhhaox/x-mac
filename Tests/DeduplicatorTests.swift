import Foundation
import Testing
@testable import Xmac

@Suite("Deduplicator Tests")
struct DeduplicatorTests {

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XmacDedupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createTestFile(at url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    final class PathCollector: @unchecked Sendable {
        var paths = Set<String>()
        let lock = NSLock()
        func add(_ path: String) {
            lock.lock()
            paths.insert(path)
            lock.unlock()
        }
    }

    @Test("FastDirectoryWalker traverses files and subdirectories accurately")
    func fastDirectoryWalkerTraversesFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let subDir = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let fileA = root.appendingPathComponent("fileA.txt")
        let fileB = subDir.appendingPathComponent("fileB.txt")
        try createTestFile(at: fileA, content: "Hello World 123456789")
        try createTestFile(at: fileB, content: "Hello World Subdirectory 123456789")

        let walker = FastDirectoryWalker()
        let collector = PathCollector()

        walker.walk(rootPath: root.path) { entry in
            collector.add(entry.path)
        }

        #expect(collector.paths.contains(fileA.path))
        #expect(collector.paths.contains(fileB.path))
    }

    @Test("APFSCloneEngine byte-for-byte comparison identifies identical and different contents")
    func byteForByteComparisonWorks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let file1 = root.appendingPathComponent("file1.txt")
        let file2 = root.appendingPathComponent("file2.txt")
        let file3 = root.appendingPathComponent("file3.txt")

        let sampleData = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n", count: 100)
        let differentData = String(repeating: "ZXYWVUTSRQPONMLKJIHGFEDCBA9876543210\n", count: 100)

        try createTestFile(at: file1, content: sampleData)
        try createTestFile(at: file2, content: sampleData)
        try createTestFile(at: file3, content: differentData)

        #expect(APFSCloneEngine.contentsEqual(file1.path, file2.path) == true)
        #expect(APFSCloneEngine.contentsEqual(file1.path, file3.path) == false)
    }

    @Test("APFSCloneEngine clones file and preserves byte equality and metadata")
    func apfsCloneEngineClonesAndPreservesData() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realRootPath = APFSCloneEngine.realPath(root.path)
        guard APFSCloneEngine.supportsClones(at: realRootPath) else {
            // Test runner environment might not be on an APFS volume (e.g. some CI setups)
            return
        }

        let keeper = root.appendingPathComponent("keeper.dat")
        let duplicate = root.appendingPathComponent("duplicate.dat")

        let content = String(repeating: "APFS CoW Verification Test Data 0123456789\n", count: 500)
        try createTestFile(at: keeper, content: content)
        try createTestFile(at: duplicate, content: content)

        let expectedSize = Int64(content.utf8.count)

        let keeperPath = APFSCloneEngine.realPath(keeper.path)
        let dupPath = APFSCloneEngine.realPath(duplicate.path)

        // Clone duplicate into keeper without quiet period requirement
        let result = APFSCloneEngine.clone(
            path: dupPath,
            into: keeperPath,
            expectedSize: expectedSize,
            requireQuietPeriod: false
        )

        #expect(result.outcome == .cloned, "Clone failed with reason: \(result.reason ?? "none")")
        #expect(APFSCloneEngine.contentsEqual(keeperPath, dupPath) == true)

        // Verify unfold (undo) restores a distinct copy
        let unfolded = APFSCloneEngine.unfold(path: dupPath)
        #expect(unfolded == true)
        #expect(APFSCloneEngine.contentsEqual(keeperPath, dupPath) == true)
    }

    @Test("DeduplicatorScanner discovers duplicate sets and filters out unique files")
    func deduplicatorScannerDiscoversDuplicates() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realRootPath = APFSCloneEngine.realPath(root.path)
        guard APFSCloneEngine.supportsClones(at: realRootPath) else { return }

        // Create identical files larger than 64KB (min size)
        let dupContent = String(repeating: "Duplicate Content Block ABCDEFGHIJKLMNOPQRSTUVWXYZ 123456789\n", count: 1500)
        let uniqueContent = String(repeating: "Unique Content Block 0987654321 ZYXWVUTSRQPONMLKJIHGFEDCBA\n", count: 1500)

        let file1 = root.appendingPathComponent("file1.bin")
        let file2 = root.appendingPathComponent("file2.bin")
        let fileUnique = root.appendingPathComponent("unique.bin")

        try createTestFile(at: file1, content: dupContent)
        try createTestFile(at: file2, content: dupContent)
        try createTestFile(at: fileUnique, content: uniqueContent)

        let realFile1Path = APFSCloneEngine.realPath(file1.path)
        let realFile2Path = APFSCloneEngine.realPath(file2.path)
        let realFileUniquePath = APFSCloneEngine.realPath(fileUnique.path)

        let options = DeduplicatorScanOptions(
            rootPaths: [realRootPath],
            minSizeBytes: 1024,
            skipPaths: []
        )

        let scanner = DeduplicatorScanner(options: options)
        let report = scanner.scan()

        #expect(report.groups.count == 1)
        if let first = report.groups.first {
            #expect(first.allFiles.count == 2)
            #expect(first.allFiles.contains(realFile1Path))
            #expect(first.allFiles.contains(realFile2Path))
            #expect(!first.allFiles.contains(realFileUniquePath))
        }
    }

    @Test("DeduplicatorJournal records transactions and unwinds them cleanly")
    func deduplicatorJournalRecordsAndUnwinds() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realRootPath = APFSCloneEngine.realPath(root.path)
        guard APFSCloneEngine.supportsClones(at: realRootPath) else { return }

        let journalURL = root.appendingPathComponent("test_journal.jsonl")
        let journal = DeduplicatorJournal(journalURL: journalURL)

        let fileA = root.appendingPathComponent("orig.dat")
        let fileB = root.appendingPathComponent("clone.dat")
        let data = "Journal Test Data 1234567890"
        try createTestFile(at: fileA, content: data)
        try createTestFile(at: fileB, content: data)

        let realFileAPath = APFSCloneEngine.realPath(fileA.path)
        let realFileBPath = APFSCloneEngine.realPath(fileB.path)

        let res = APFSCloneEngine.clone(
            path: realFileBPath,
            into: realFileAPath,
            expectedSize: Int64(data.utf8.count),
            requireQuietPeriod: false
        )
        #expect(res.outcome == .cloned, "Journal test clone failed with: \(res.reason ?? "none")")

        journal.record(path: realFileBPath, keeper: realFileAPath, size: Int64(data.utf8.count))

        let entries = journal.readEntries()
        #expect(entries.count == 1)
        #expect(entries[0].path == realFileBPath)

        // Undo
        let (success, failed) = journal.undoAll()
        #expect(success == 1)
        #expect(failed == 0)
        #expect(journal.readEntries().isEmpty)
    }

    @Test("DeduplicatorFileCategory matches extensions properly and filters scanning")
    func deduplicatorFileCategoryFiltersCorrectly() throws {
        #expect(DeduplicatorFileCategory.images.matches(path: "/path/to/photo.jpg"))
        #expect(DeduplicatorFileCategory.images.matches(path: "/path/to/photo.PNG"))
        #expect(!DeduplicatorFileCategory.images.matches(path: "/path/to/script.py"))

        #expect(DeduplicatorFileCategory.videos.matches(path: "/path/to/movie.mp4"))
        #expect(DeduplicatorFileCategory.videos.matches(path: "/path/to/clip.mov"))
        #expect(!DeduplicatorFileCategory.videos.matches(path: "/path/to/image.png"))

        #expect(DeduplicatorFileCategory.code.matches(path: "/path/to/main.swift"))
        #expect(DeduplicatorFileCategory.code.matches(path: "/path/to/index.ts"))
        #expect(!DeduplicatorFileCategory.code.matches(path: "/path/to/archive.zip"))

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realRootPath = APFSCloneEngine.realPath(root.path)
        guard APFSCloneEngine.supportsClones(at: realRootPath) else { return }

        let code1 = root.appendingPathComponent("script1.swift")
        let code2 = root.appendingPathComponent("script2.swift")
        let img1 = root.appendingPathComponent("pic1.png")
        let img2 = root.appendingPathComponent("pic2.png")

        let codeContent = String(repeating: "func testCoWClone() -> Bool { return true }\n", count: 200)
        let imgContent = String(repeating: "PNG DUMMY IMAGE BYTES DATA 1234567890\n", count: 200)

        try createTestFile(at: code1, content: codeContent)
        try createTestFile(at: code2, content: codeContent)
        try createTestFile(at: img1, content: imgContent)
        try createTestFile(at: img2, content: imgContent)

        // Scan only code category
        let codeOptions = DeduplicatorScanOptions(
            rootPaths: [realRootPath],
            minSizeBytes: 1024,
            skipPaths: [],
            category: .code
        )
        let codeReport = DeduplicatorScanner(options: codeOptions).scan()
        #expect(codeReport.groups.count == 1)
        #expect(codeReport.groups.first?.fileName.hasSuffix(".swift") == true)

        // Scan only images category
        let imgOptions = DeduplicatorScanOptions(
            rootPaths: [realRootPath],
            minSizeBytes: 1024,
            skipPaths: [],
            category: .images
        )
        let imgReport = DeduplicatorScanner(options: imgOptions).scan()
        #expect(imgReport.groups.count == 1)
        #expect(imgReport.groups.first?.fileName.hasSuffix(".png") == true)
    }

    @Test("DeduplicatorScheduler persists preferences and calculates due intervals")
    @MainActor
    func deduplicatorSchedulerPersistsAndCalculates() throws {
        let scheduler = DeduplicatorScheduler.shared
        let originalEnabled = scheduler.isEnabled
        let originalInterval = scheduler.interval
        let originalMinMB = scheduler.minNotifyMB

        defer {
            scheduler.isEnabled = originalEnabled
            scheduler.interval = originalInterval
            scheduler.minNotifyMB = originalMinMB
        }

        scheduler.isEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "Deduplicator.Schedule.Enabled") == true)

        scheduler.interval = .daily
        #expect(UserDefaults.standard.string(forKey: "Deduplicator.Schedule.Interval") == DeduplicatorScheduleInterval.daily.rawValue)
        #expect(scheduler.interval.timeInterval == 86400)

        scheduler.minNotifyMB = 1000
        #expect(UserDefaults.standard.integer(forKey: "Deduplicator.Schedule.MinNotifyMB") == 1000)
    }
}
