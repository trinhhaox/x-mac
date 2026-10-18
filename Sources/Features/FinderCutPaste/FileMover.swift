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
    private let fileManager: FileManager
    private let stateLock = NSLock()
    private var lastMoves: [MoveRecord] = []
    private var undoDeadline: Date?
    /// Undo only owns ⌘Z in Finder briefly after a paste, so Finder's own undo
    /// (Trash, rename, …) stays reachable afterwards.
    private let undoWindow: TimeInterval
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        undoWindow: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.undoWindow = undoWindow
        self.now = now
    }

    public func moveFiles(sources: [String], destinationFolder: String) -> [MoveRecord] {
        var completedMoves: [MoveRecord] = []
        let destURL = URL(fileURLWithPath: destinationFolder, isDirectory: true)

        for sourcePath in sources {
            let sourceURL = URL(fileURLWithPath: sourcePath)

            let normalizedSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            let normalizedDestination = destURL.standardizedFileURL.resolvingSymlinksInPath()
            if normalizedDestination.pathComponents.starts(with: normalizedSource.pathComponents),
               normalizedDestination != normalizedSource {
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
            stateLock.lock()
            self.lastMoves = completedMoves
            undoDeadline = now().addingTimeInterval(undoWindow)
            stateLock.unlock()
        }

        return completedMoves
    }

    public func undoLastMove() -> Int {
        stateLock.lock()
        let movesToUndo = isUndoExpired ? [] : lastMoves
        stateLock.unlock()
        guard !movesToUndo.isEmpty else { return 0 }

        var undoneCount = 0
        var failedMoves: [MoveRecord] = []

        for record in movesToUndo.reversed() {
            let currentURL = URL(fileURLWithPath: record.destinationPath)
            let originalURL = URL(fileURLWithPath: record.originalPath)

            if fileManager.fileExists(atPath: currentURL.path) {
                let safeOriginal = uniqueURL(for: originalURL)
                do {
                    try fileManager.moveItem(at: currentURL, to: safeOriginal)
                    undoneCount += 1
                } catch {
                    NSLog("Xmac Undo error: \(error)")
                    failedMoves.append(record)
                }
            }
        }

        stateLock.lock()
        lastMoves = failedMoves.reversed()
        // Keep failed items retryable for a fresh window.
        undoDeadline = lastMoves.isEmpty ? nil : now().addingTimeInterval(undoWindow)
        stateLock.unlock()
        return undoneCount
    }

    public var canUndo: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !lastMoves.isEmpty && !isUndoExpired
    }

    /// Caller must hold `stateLock`.
    private var isUndoExpired: Bool {
        guard let undoDeadline else { return true }
        return now() >= undoDeadline
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
