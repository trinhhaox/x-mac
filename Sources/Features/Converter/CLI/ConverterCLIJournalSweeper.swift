import Foundation

/// CLI jobs keep a per-process journal (`xmac-cli-partials-<pid>.json`). A CLI killed hard (SIGKILL, crash)
/// leaves it behind; the next CLI run deletes the partials it lists once the owning process is gone.
enum ConverterCLIJournalSweeper {
    private static let prefix = "xmac-cli-partials-"

    static func journalURL(pid: Int32, in directory: URL) -> URL {
        directory.appendingPathComponent("\(prefix)\(pid).json")
    }

    static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }

    /// Returns the number of leftover partial files deleted.
    @discardableResult
    static func sweep(
        in directory: URL, ownPID: Int32 = getpid(), isAlive: (Int32) -> Bool = isProcessAlive,
        fileManager: FileManager = .default
    ) -> Int {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        var removed = 0
        for name in names {
            guard name.hasPrefix(prefix), name.hasSuffix(".json"),
                  let pid = Int32(name.dropFirst(prefix.count).dropLast(".json".count)),
                  pid != ownPID, !isAlive(pid) else { continue }
            let journal = directory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: journal), let entries = try? JSONDecoder().decode([String: String].self, from: data) {
                for path in entries.keys where PartialFileJournal.isPartial(URL(fileURLWithPath: path)) {
                    if (try? fileManager.removeItem(atPath: path)) != nil { removed += 1 }
                }
            }
            try? fileManager.removeItem(at: journal)
        }
        return removed
    }
}
