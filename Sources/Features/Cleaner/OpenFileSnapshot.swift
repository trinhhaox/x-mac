import Foundation

/// Files held open by the user's processes, taken once per cleaning run with `lsof`.
///
/// Matching a running app by bundle id misses caches named differently (`Google/`,
/// `com.vendor.app.helper`) and command-line tools (npm, Gradle daemon) entirely; an open
/// file handle is the direct evidence that something is still using a cache.
struct OpenFileSnapshot {
    /// Every open path plus all of its ancestors, lowercased (APFS is case-insensitive), so a
    /// lookup is one set probe.
    private let pathsInUse: Set<String>

    init(openPaths: [String]) {
        var paths = Set<String>()
        for path in openPaths {
            var current = path.lowercased()
            while current.count > 1, paths.insert(current).inserted {
                current = (current as NSString).deletingLastPathComponent
            }
        }
        pathsInUse = paths
    }

    /// True when the path itself, or anything below it, is open.
    func isInUse(_ path: String) -> Bool {
        // resolvingSymlinksInPath drops a leading /private that lsof keeps.
        let resolved = HomePathGuard.resolve(path).path.lowercased()
        return pathsInUse.contains(resolved) || pathsInUse.contains("/private" + resolved)
    }

    /// File paths from `lsof -F n` output (lines `n/...`; process and fd lines are ignored).
    /// Kept verbatim: real names contain " (", e.g. iOS DeviceSupport's "iPhone14,5 16.4.1 (20E252)".
    static func parse(lsofOutput: String) -> [String] {
        lsofOutput.split(separator: "\n").compactMap { line in
            line.hasPrefix("n/") ? String(line.dropFirst()) : nil
        }
    }

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    /// Nil when lsof is missing, fails or times out: callers must then treat everything as in use.
    static func capture(timeout: TimeInterval = 20) -> OpenFileSnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-w", "-n", "-P", "-F", "n", "-u", String(getuid())]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let output = OutputBox()
        let readDone = DispatchSemaphore(value: 0)
        do {
            try process.run()
        } catch {
            NSLog("Xmac Cleaner: cannot run lsof: \(error)")
            return nil
        }
        // Drain the pipe concurrently: lsof output can exceed the pipe buffer and block.
        DispatchQueue.global(qos: .userInitiated).async {
            output.data = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        guard readDone.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            NSLog("Xmac Cleaner: lsof timed out after \(timeout)s")
            return nil
        }
        process.waitUntilExit()
        // A signal (jetsam, crash) truncates the listing: processes after the cut would look idle.
        // Status 1 is normal for lsof when some processes could not be inspected.
        guard process.terminationReason == .exit, [0, 1].contains(process.terminationStatus) else {
            NSLog("Xmac Cleaner: lsof ended abnormally (reason \(process.terminationReason.rawValue), status \(process.terminationStatus))")
            return nil
        }

        let paths = parse(lsofOutput: String(decoding: output.data, as: UTF8.self))
        // lsof exits 1 for partial errors but still lists what it could; an empty list is not credible.
        guard !paths.isEmpty else {
            NSLog("Xmac Cleaner: lsof returned no open files (status \(process.terminationStatus))")
            return nil
        }
        return OpenFileSnapshot(openPaths: paths)
    }
}
