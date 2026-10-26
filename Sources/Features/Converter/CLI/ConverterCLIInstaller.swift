import Foundation

/// `xmac install-cli`: symlinks the running executable into a PATH directory. Never escalates privileges.
struct ConverterCLIInstaller {
    var directories: [URL] = [
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin", isDirectory: true)
    ]
    var fileManager = FileManager.default

    /// Returns a human-readable summary of what was done.
    func install(executable: URL) throws -> String {
        let source = executable.resolvingSymlinksInPath()
        guard !source.path.contains("/AppTranslocation/") else {
            throw ConverterCLIUsageError(message: "Xmac is running from a temporary quarantine location; move Xmac.app to /Applications, open it once, then run install-cli again")
        }
        var lastError: Error?
        for (index, directory) in directories.enumerated() {
            let isLast = index == directories.count - 1
            do {
                if let message = try link(source, in: directory, createDirectory: isLast) { return message }
            } catch let error as ConverterCLIUsageError {
                throw error
            } catch {
                lastError = error
            }
        }
        throw ConverterCLIUsageError(message: "could not create a link: \(lastError?.localizedDescription ?? "no writable directory")")
    }

    /// Nil when the directory is unusable (missing or not writable) so the next one is tried.
    private func link(_ source: URL, in directory: URL, createDirectory: Bool) throws -> String? {
        if createDirectory { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        guard fileManager.isWritableFile(atPath: directory.path) else { return nil }
        let link = directory.appendingPathComponent("xmac")
        if let existing = try? fileManager.destinationOfSymbolicLink(atPath: link.path) {
            let destination = URL(fileURLWithPath: existing, relativeTo: directory).standardizedFileURL.resolvingSymlinksInPath()
            if destination == source {
                return "Already installed: \(link.path) -> \(source.path)"
            }
            guard isReplaceable(destination) else {
                throw ConverterCLIUsageError(message: "\(link.path) already exists (-> \(existing)); remove it first")
            }
            try fileManager.removeItem(at: link)
        } else if fileManager.fileExists(atPath: link.path) {
            throw ConverterCLIUsageError(message: "\(link.path) exists and is not a symlink; remove it first")
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: source)
        var message = "Installed: \(link.path) -> \(source.path)"
        let onPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains { String($0) == directory.path }
        if !onPath { message += "\nNote: \(directory.path) is not on your PATH; add it to your shell profile." }
        return message
    }

    /// A dangling link, or one pointing at an Xmac executable inside an app bundle (an older install).
    func isReplaceable(_ destination: URL) -> Bool {
        guard fileManager.fileExists(atPath: destination.path) else { return true }
        let macOS = destination.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        return destination.lastPathComponent == "Xmac" && macOS.lastPathComponent == "MacOS"
            && contents.lastPathComponent == "Contents" && contents.deletingLastPathComponent().pathExtension == "app"
            && fileManager.isExecutableFile(atPath: destination.path)
    }
}
