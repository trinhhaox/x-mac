import Foundation

/// Hands out non-overwriting output paths; the in-memory set covers files not yet written to disk.
public actor OutputPathReserver {
    public static let shared = OutputPathReserver()

    private var reserved: Set<String> = []

    public init() {}

    public func reserve(fileName: String, in directory: URL) -> URL {
        let safeName = DownloadManager.sanitizedFileName(fileName, fallback: "output")
        var candidate = DownloadManager.uniqueDestination(for: safeName, in: directory)
        var suffix = 0
        while reserved.contains(candidate.path) {
            suffix += 1
            candidate = DownloadManager.uniqueDestination(for: Self.numbered(safeName, suffix), in: directory)
        }
        reserved.insert(candidate.path)
        return candidate
    }

    public func release(_ url: URL) {
        reserved.remove(url.path)
    }

    private static func numbered(_ name: String, _ suffix: Int) -> String {
        let url = URL(fileURLWithPath: name)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
    }
}
