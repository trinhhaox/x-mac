import Foundation

/// Size and modification time (millisecond precision) of a regular file.
struct FileSnapshot: Equatable {
    let size: UInt64
    let modifiedMillis: Int64

    static func read(_ url: URL) -> FileSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return FileSnapshot(size: size.uint64Value, modifiedMillis: Int64(modified.timeIntervalSince1970 * 1000))
    }
}

/// Files Xmac already produced or already handled, so nothing is converted twice (or back and forth
/// between opposite rules). Outputs are keyed by path + size + mtime; handled inputs by rule + path only, so
/// an atomic save or rename of an original never re-converts it ("new arrivals only"). Paths are normalized
/// (symlinks resolved) on both sides; oldest entries drop past the limit.
struct WatchProcessedSet: Codable, Equatable {
    static let limit = 500
    private(set) var keys: [String] = []

    func isOutput(_ path: String, _ snapshot: FileSnapshot) -> Bool {
        keys.contains(Self.key("out", path, snapshot))
    }

    func wasHandled(by rule: UUID, _ path: String) -> Bool {
        keys.contains(Self.key("in:\(rule.uuidString)", path))
    }

    mutating func markOutput(_ path: String, _ snapshot: FileSnapshot) {
        insert(Self.key("out", path, snapshot))
    }

    mutating func markHandled(by rule: UUID, _ path: String) {
        insert(Self.key("in:\(rule.uuidString)", path))
    }

    private mutating func insert(_ key: String) {
        guard !keys.contains(key) else { return }
        keys.append(key)
        if keys.count > Self.limit { keys.removeFirst(keys.count - Self.limit) }
    }

    private static func key(_ kind: String, _ path: String, _ snapshot: FileSnapshot? = nil) -> String {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return snapshot.map { "\(kind)|\(normalized)|\($0.size)|\($0.modifiedMillis)" } ?? "\(kind)|\(normalized)"
    }
}

enum WatchStability {
    /// The file's snapshot once two checks `interval` seconds apart agree and it is not empty;
    /// nil when it vanishes, is cancelled, or is still changing after `maxWait` seconds.
    static func waitUntilStable(
        _ url: URL,
        interval: TimeInterval = 2,
        maxWait: TimeInterval = 600,
        stat: (URL) -> FileSnapshot? = FileSnapshot.read,
        sleep: (TimeInterval) async throws -> Void
    ) async -> FileSnapshot? {
        guard var previous = stat(url) else { return nil }
        var waited: TimeInterval = 0
        while waited < maxWait {
            do { try await sleep(interval) } catch { return nil }
            waited += interval
            guard let current = stat(url) else { return nil }
            if current == previous, current.size > 0 { return current }
            previous = current
        }
        return nil
    }
}
