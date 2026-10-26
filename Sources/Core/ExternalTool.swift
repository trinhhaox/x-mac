import Foundation

public enum ExternalTool: String, CaseIterable {
    case ffmpeg
    case ffprobe
    case soffice

    var defaultCandidates: [String] {
        switch self {
        case .ffmpeg, .ffprobe:
            return ["/opt/homebrew/bin/\(rawValue)", "/usr/local/bin/\(rawValue)"]
        case .soffice:
            return [
                "/Applications/LibreOffice.app/Contents/MacOS/soffice",
                "/opt/homebrew/bin/soffice",
                "/usr/local/bin/soffice"
            ]
        }
    }

    public var overrideDefaultsKey: String { "Converter.ToolPath.\(rawValue)" }
}

/// Finds external binaries without relying on the shell PATH (GUI apps do not inherit Homebrew's).
public struct BinaryLocator {
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let extraCandidates: [ExternalTool: [String]]

    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        extraCandidates: [ExternalTool: [String]] = [:]
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.extraCandidates = extraCandidates
    }

    /// The user override wins; a bad override is ignored rather than silently replaced by a different binary.
    public func locate(_ tool: ExternalTool) -> URL? {
        if let override = defaults.string(forKey: tool.overrideDefaultsKey), !override.isEmpty {
            return usableExecutable(at: override)
        }
        let candidates = (extraCandidates[tool] ?? []) + tool.defaultCandidates
        return candidates.lazy.compactMap { usableExecutable(at: $0) }.first
    }

    /// Homebrew binaries are symlinks, so the resolved target must be an executable regular file.
    func usableExecutable(at path: String) -> URL? {
        let url = URL(fileURLWithPath: path)
        let resolved = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: resolved.path) else { return nil }
        return url
    }
}
