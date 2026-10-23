import Foundation

/// Last check before the cleaner moves anything: every scanner result must pass it again.
enum CleanerPathPolicy {
    /// Any entry below these roots may be cleaned.
    static let descendantRoots = [
        "Library/Caches",
        "Library/Logs",
        "Library/Developer/Xcode/DerivedData",
        ".Trash"
    ] + DeveloperCacheCatalog.childScannedFolders.map(\.relativePath)

    /// Only a direct child named after a bundle id (data left by an uninstalled app).
    static let bundleIdentifierRoots = OrphanedAppDataScanner.scannedFolders

    static func isAllowed(itemPath: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        guard !HomePathGuard.hasRelativeComponents(itemPath) else { return false }
        let item = HomePathGuard.resolve(itemPath)
        let home = HomePathGuard.resolvedHome(homeDirectory)

        for relative in DeveloperCacheCatalog.wholeFolderCaches.map(\.relativePath) {
            if let root = HomePathGuard.trustedRoot(relative, home: home), item.path == root.path {
                return true
            }
        }
        for relative in descendantRoots {
            if let root = HomePathGuard.trustedRoot(relative, home: home),
               HomePathGuard.isStrictDescendant(item, of: root) {
                return true
            }
        }
        for relative in bundleIdentifierRoots {
            if let root = HomePathGuard.trustedRoot(relative, home: home),
               HomePathGuard.isDirectChild(item, of: root),
               BundleIdentifierName.identifier(fromItemName: item.lastPathComponent) != nil {
                return true
            }
        }
        return false
    }
}
