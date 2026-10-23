import Foundation

/// Paths the user asked the cleaner never to touch
/// (~/Library/Application Support/Xmac/cleaner-whitelist.json).
///
/// A missing file means "nothing protected". A file that exists but cannot be read means
/// the protection list is unknown, so cleaning must stop instead of running without it.
public final class CleanerWhitelist: ObservableObject {
    public static let shared = CleanerWhitelist(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Xmac/cleaner-whitelist.json")
    )

    public struct UnreadableError: Error {}

    /// Last successfully loaded list, for display.
    @Published public private(set) var paths: [String] = []
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        paths = (try? load()) ?? []
    }

    public func load() throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            NSLog("Xmac cleaner whitelist unreadable: \(error)")
            throw UnreadableError()
        }
    }

    public func add(_ path: String) throws {
        var current = try load()
        guard !current.contains(path) else { return }
        current.append(path)
        try save(current)
    }

    public func remove(_ path: String) throws {
        try save(try load().filter { $0 != path })
    }

    /// The path, one of its parents, or something inside it is protected
    /// (moving a folder would carry a protected child along).
    static func isProtected(_ path: String, by protectedPaths: [String]) -> Bool {
        let item = HomePathGuard.resolve(path)
        return protectedPaths.contains { protected in
            let root = HomePathGuard.resolve(protected)
            return item.path == root.path
                || HomePathGuard.isStrictDescendant(item, of: root)
                || HomePathGuard.isStrictDescendant(root, of: item)
        }
    }

    private func save(_ list: [String]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(list).write(to: fileURL, options: .atomic)
        let publish = { self.paths = list }
        Thread.isMainThread ? publish() : DispatchQueue.main.async(execute: publish)
    }
}
