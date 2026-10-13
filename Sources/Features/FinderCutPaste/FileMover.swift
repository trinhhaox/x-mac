import Cocoa

public struct MoveRecord {
    public let originalPath: String
    public let destinationPath: String
}

public protocol FileMoving {
    func moveFiles(sources: [String], destinationFolder: String) -> [MoveRecord]
    func undoLastMove() -> Int
    var canUndo: Bool { get }
}

public class FileMover: FileMoving {
    public static let shared = FileMover()
    private let fileManager = FileManager.default
    private var lastMoves: [MoveRecord] = []

    private init() {}

    public func moveFiles(sources: [String], destinationFolder: String) -> [MoveRecord] {
        var completedMoves: [MoveRecord] = []
        let destURL = URL(fileURLWithPath: destinationFolder, isDirectory: true)

        for sourcePath in sources {
            let sourceURL = URL(fileURLWithPath: sourcePath)

            if destinationFolder.hasPrefix(sourcePath) && destinationFolder != sourcePath {
                continue
            }

            if sourceURL.deletingLastPathComponent().path == destURL.path {
                continue
            }

            let targetURL = uniqueURL(for: destURL.appendingPathComponent(sourceURL.lastPathComponent))

            do {
                try fileManager.moveItem(at: sourceURL, to: targetURL)
                completedMoves.append(
                    MoveRecord(originalPath: sourcePath, destinationPath: targetURL.path)
                )
            } catch {
                NSLog("Xmac FileMover error moving \(sourcePath) to \(targetURL.path): \(error)")
            }
        }

        if !completedMoves.isEmpty {
            self.lastMoves = completedMoves
        }

        return completedMoves
    }

    public func undoLastMove() -> Int {
        guard !lastMoves.isEmpty else { return 0 }
        var undoneCount = 0

        for record in lastMoves.reversed() {
            let currentURL = URL(fileURLWithPath: record.destinationPath)
            let originalURL = URL(fileURLWithPath: record.originalPath)

            if fileManager.fileExists(atPath: currentURL.path) {
                let safeOriginal = uniqueURL(for: originalURL)
                do {
                    try fileManager.moveItem(at: currentURL, to: safeOriginal)
                    undoneCount += 1
                } catch {
                    NSLog("Xmac Undo error: \(error)")
                }
            }
        }

        lastMoves.removeAll()
        return undoneCount
    }

    public var canUndo: Bool {
        return !lastMoves.isEmpty
    }

    private func uniqueURL(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let nameWithoutExt = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        while true {
            let newName = ext.isEmpty
                ? "\(nameWithoutExt) (\(counter))"
                : "\(nameWithoutExt) (\(counter)).\(ext)"
            let candidate = directory.appendingPathComponent(newName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
