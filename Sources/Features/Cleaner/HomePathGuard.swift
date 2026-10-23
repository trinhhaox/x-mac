import Foundation

/// Path checks shared by the cleaner and the uninstaller.
///
/// Policies compare *resolved* paths. Resolving alone is not enough: if `~/Library/Caches`
/// itself were a symlink to `~/Documents`, the resolved root would be `~/Documents` and
/// everything there would look like a cache. A root is only trusted when no component
/// below the home directory is a symlink.
enum HomePathGuard {
    static func resolve(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }

    /// `standardizedFileURL` collapses `..` as text, while the kernel would follow a symlink
    /// before it; scanners never produce these components, so policies reject them outright.
    static func hasRelativeComponents(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0 == ".." || $0 == "." }
    }

    static func resolvedHome(_ homeDirectory: String) -> URL {
        resolve(homeDirectory)
    }

    /// `home/relative` resolved, or nil when the root or one of its ancestors below home is a symlink.
    static func trustedRoot(_ relative: String, home: URL) -> URL? {
        let literal = home.appendingPathComponent(relative, isDirectory: true).standardizedFileURL
        let resolved = literal.resolvingSymlinksInPath()
        return resolved.path == literal.path ? resolved : nil
    }

    static func isStrictDescendant(_ item: URL, of root: URL) -> Bool {
        item.path != root.path && item.pathComponents.starts(with: root.pathComponents)
    }

    static func isDirectChild(_ item: URL, of root: URL) -> Bool {
        isStrictDescendant(item, of: root) && item.pathComponents.count == root.pathComponents.count + 1
    }
}

/// Names of per-app folders and files in ~/Library: `com.vendor.app`, `com.vendor.app.plist`,
/// `com.vendor.app.savedState`, `com.vendor.app.binarycookies`.
enum BundleIdentifierName {
    private static let fileSuffixes = [".plist", ".savedState", ".binarycookies"]
    private static let pattern = #"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9_-]*){2,}$"#

    /// The bundle identifier a Library entry is named after, or nil when the name is not one.
    static func identifier(fromItemName name: String) -> String? {
        var base = name
        for suffix in fileSuffixes where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
            break
        }
        return base.range(of: pattern, options: .regularExpression) == nil ? nil : base
    }
}
