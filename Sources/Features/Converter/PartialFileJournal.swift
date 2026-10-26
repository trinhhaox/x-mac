import Foundation

/// Remembers the hidden `.xmac-partial` files of running jobs, so a crash or force-quit mid-conversion
/// does not leave them behind: the next launch deletes whatever an earlier session still lists.
public final class PartialFileJournal: @unchecked Sendable {
    public static let shared = PartialFileJournal(storeURL: defaultStoreURL)

    private let storeURL: URL
    private let lock = NSLock()
    /// Entries of this session belong to live jobs, so a sweep racing a fresh job never deletes them.
    private let session = UUID().uuidString

    init(storeURL: URL) {
        self.storeURL = storeURL
    }

    private static var defaultStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Xmac", isDirectory: true).appendingPathComponent("converter-partials.json")
    }

    /// Only hidden files named like `ConversionQueue.partialURL` produces are ever touched.
    static func isPartial(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") && name.contains(".xmac-partial")
    }

    func record(_ url: URL) {
        guard Self.isPartial(url) else { return }
        update { $0[url.path] = session }
    }

    func remove(_ url: URL) {
        update { $0[url.path] = nil }
    }

    /// Deletes files listed by earlier sessions that still exist and still look like partials.
    @discardableResult
    func sweep() -> Int {
        lock.lock()
        defer { lock.unlock() }
        var removed = 0
        var kept = load()
        for (path, owner) in kept where owner != session {
            kept[path] = nil
            let url = URL(fileURLWithPath: path)
            guard Self.isPartial(url), FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                NSLog("Converter: could not remove leftover partial \(path): \(error)")
            }
        }
        save(kept)
        return removed
    }

    private func update(_ change: (inout [String: String]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var entries = load()
        change(&entries)
        save(entries)
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL) else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            NSLog("Converter: unreadable partial journal, ignoring: \(error)")
            return [:]
        }
    }

    private func save(_ entries: [String: String]) {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: storeURL, options: .atomic)
        } catch {
            NSLog("Converter: could not write partial journal: \(error)")
        }
    }
}
