import Foundation

/// Temp-directory, process and publish helpers shared by the converters in this folder.
enum ConverterWorkspace {
    static let tempPrefix = "xmac-convert-"

    /// Prefers a directory on the destination volume so the final move is a rename, not a copy.
    /// Those live in the system's per-volume temp area and are not swept by `sweepStaleTempDirectories`.
    static func makeTempDirectory(near destination: URL) throws -> URL {
        let parent = destination.deletingLastPathComponent()
        if let url = try? FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: parent, create: true
        ) {
            return url
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tempPrefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs `body` with a fresh temp directory that is always removed afterwards.
    static func withTempDirectory<T>(near destination: URL, _ body: (URL) async throws -> T) async throws -> T {
        let directory = try makeTempDirectory(near: destination)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    /// Removes fallback temp directories left behind by a crash or force-quit.
    static func sweepStaleTempDirectories(olderThan age: TimeInterval = 3600, in root: URL = FileManager.default.temporaryDirectory) {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-age)
        let entries = (try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for entry in entries where entry.lastPathComponent.hasPrefix(tempPrefix) {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? fileManager.removeItem(at: entry) }
        }
    }

    /// Moves the finished file into place; the destination is only touched once the work succeeded.
    static func publish(_ produced: URL, to destination: URL) throws {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: produced.path) else {
            throw ConversionError.failed("Output was not produced")
        }
        try FileManager.default.moveItem(at: produced, to: destination)
    }

    /// Runs a tool and maps failures to `ConversionError` (cancellation stays `CancellationError`).
    @discardableResult
    static func run(
        _ executable: URL,
        _ arguments: [String],
        timeout: TimeInterval? = nil,
        onStderrLine: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        do {
            return try await ProcessRunner.run(
                executable: executable, arguments: arguments, timeout: timeout, onStderrLine: onStderrLine
            ).throwIfFailed()
        } catch ProcessRunnerError.cancelled {
            throw CancellationError()
        } catch ProcessRunnerError.nonZeroExit(_, let tail) {
            throw ConversionError.failed(tail.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch ProcessRunnerError.timedOut {
            throw ConversionError.failed("Timed out")
        } catch ProcessRunnerError.launchFailed(let message) {
            throw ConversionError.failed(message)
        }
    }

    static func requireTool(_ tool: ExternalTool, locator: BinaryLocator) throws -> URL {
        guard let url = locator.locate(tool) else { throw ConversionError.toolMissing(tool) }
        return url
    }
}

extension URL {
    var lowercasedExtension: String { pathExtension.lowercased() }
}
