import Foundation

/// Scratch folders for browser drops: `<scratchRoot>/<uuid>/` holds the kept copy, `incoming/` the unfinished one.
/// Every deletion here is confined to `scratchRoot`.
extension BrowserDropCoordinator {
    nonisolated static let scratchRoot = FileManager.default.temporaryDirectory.appendingPathComponent("xmac-browser-drop", isDirectory: true)
    nonisolated static let userDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    nonisolated static let incomingFolder = "incoming"
    private nonisolated static let staleAge: TimeInterval = 24 * 3600

    nonisolated static func newScratchFolder() -> URL {
        scratchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    /// Deletes scratch copies once their jobs are over.
    nonisolated static func dispose(_ inputs: [URL], root: URL = scratchRoot) {
        for input in scratchInputs(inputs, root: root) {
            try? FileManager.default.removeItem(at: input)
            removeFolderIfEmpty(input.deletingLastPathComponent(), root: root)
        }
    }

    /// A failed conversion must not cost the user the fetched file: scratch inputs move to `folder` under a free name.
    nonisolated static func rescue(_ inputs: [URL], into folder: URL, root: URL = scratchRoot) {
        for input in scratchInputs(inputs, root: root) {
            let destination = DownloadManager.uniqueDestination(for: input.lastPathComponent, in: folder)
            do {
                try FileManager.default.moveItem(at: input, to: destination)
            } catch {
                NSLog("Converter: could not keep \(input.lastPathComponent): \(error)")
                continue
            }
            removeFolderIfEmpty(input.deletingLastPathComponent(), root: root)
        }
    }

    /// Scratch folders left behind by a crash or by a selection that was never converted.
    nonisolated static func sweepStaleScratch(root: URL = scratchRoot, now: Date = Date()) {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for folder in folders {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > staleAge { try? manager.removeItem(at: folder) }
        }
    }

    private nonisolated static func scratchInputs(_ inputs: [URL], root: URL) -> [URL] {
        let rootPath = root.standardizedFileURL.path + "/"
        return inputs.filter { $0.standardizedFileURL.path.hasPrefix(rootPath) }
    }

    private nonisolated static func removeFolderIfEmpty(_ folder: URL, root: URL) {
        let manager = FileManager.default
        guard folder.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),
              (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true else { return }
        try? manager.removeItem(at: folder)
    }
}
