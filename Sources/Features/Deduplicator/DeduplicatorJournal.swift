import Foundation

/// Journal storing clone history so operations can be cleanly inspected and undone.
public final class DeduplicatorJournal: @unchecked Sendable {
    public static let shared = DeduplicatorJournal()

    private let journalURL: URL
    private let lock = NSRecursiveLock()

    public init(journalURL: URL? = nil) {
        if let customURL = journalURL {
            self.journalURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("Xmac", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.journalURL = dir.appendingPathComponent("dedup_journal.jsonl")
        }
    }

    public struct Entry: Codable, Sendable {
        public let timestamp: Date
        public let path: String
        public let keeper: String
        public let size: Int64

        public init(timestamp: Date = Date(), path: String, keeper: String, size: Int64) {
            self.timestamp = timestamp
            self.path = path
            self.keeper = keeper
            self.size = size
        }
    }

    public func record(path: String, keeper: String, size: Int64) {
        lock.lock()
        defer { lock.unlock() }

        let entry = Entry(path: path, keeper: keeper, size: size)
        guard var data = try? JSONEncoder().encode(entry) else { return }
        data.append(0x0A) // newline

        if let handle = try? FileHandle(forWritingTo: journalURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: journalURL)
        }
    }

    public func readEntries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }

        guard let text = try? String(contentsOf: journalURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            try? JSONDecoder().decode(Entry.self, from: Data(line.utf8))
        }
    }

    /// Undoes all recorded clone operations, turning CoW clones back into separate blocks.
    public func undoAll() -> (successCount: Int, failedCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        let entries = readEntries()
        guard !entries.isEmpty else { return (0, 0) }

        var success = 0
        var failed = 0
        var remaining: [Entry] = []

        for entry in entries {
            if APFSCloneEngine.unfold(path: entry.path) {
                success += 1
            } else {
                failed += 1
                remaining.append(entry)
            }
        }

        // Rewrite remaining
        var newData = Data()
        for r in remaining {
            if let line = try? JSONEncoder().encode(r) {
                newData.append(line)
                newData.append(0x0A)
            }
        }
        try? newData.write(to: journalURL, options: .atomic)

        return (success, failed)
    }
}
