import Foundation

/// One line of the cleanup journal (~/Library/Logs/Xmac/operations.log, JSON Lines).
public struct CleanupLogEntry: Codable, Identifiable, Equatable {
    public enum Action: String, Codable { case clean, uninstall }
    public enum Outcome: String, Codable { case trashed, deleted, skipped, failed }

    public var id: UUID = UUID()
    public let date: Date
    public let action: Action
    public let path: String
    public let bytes: Int64
    public let outcome: Outcome
    public var reason: String? = nil
}

/// Append-only record of what the cleaner and uninstaller moved, so "where did my file go?"
/// has an answer. Lines that fail to decode are skipped rather than hiding the whole history.
public final class CleanupOperationLog {
    public static let shared = CleanupOperationLog(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Xmac/operations.log")
    )

    static let maxFileBytes = 5 * 1024 * 1024
    let fileURL: URL
    private let queue = DispatchQueue(label: "xmac.cleanup-log")

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ entries: [CleanupLogEntry]) {
        guard !entries.isEmpty else { return }
        queue.sync {
            do {
                try writeLines(entries)
            } catch {
                NSLog("Xmac cleanup log write error: \(error)")
            }
        }
    }

    /// Newest first.
    public func recent(limit: Int = 300) -> [CleanupLogEntry] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            let decoder = Self.decoder()
            let entries = data.split(separator: UInt8(ascii: "\n")).compactMap {
                try? decoder.decode(CleanupLogEntry.self, from: Data($0))
            }
            return Array(entries.suffix(limit).reversed())
        }
    }

    private func writeLines(_ entries: [CleanupLogEntry]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        rotateIfNeeded(fm)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var payload = Data()
        for entry in entries {
            payload.append(try encoder.encode(entry))
            payload.append(UInt8(ascii: "\n"))
        }
        if !fm.fileExists(atPath: fileURL.path) {
            try payload.write(to: fileURL)
            return
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
    }

    private func rotateIfNeeded(_ fm: FileManager) {
        let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0
        guard size > Self.maxFileBytes else { return }
        let previous = fileURL.appendingPathExtension("1")
        try? fm.removeItem(at: previous)
        do {
            try fm.moveItem(at: fileURL, to: previous)
        } catch {
            NSLog("Xmac cleanup log rotate error: \(error)")
        }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
