import Cocoa

public struct JunkItem: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: Int64
    public var isSelected: Bool
    
    public var formattedSize: String {
        return ByteSize.string(size, countStyle: .file)
    }
}

public struct JunkCategory: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let iconName: String
    public var items: [JunkItem]
    public var isSelected: Bool
    
    public var selectedSize: Int64 {
        return items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    public var totalSize: Int64 {
        return items.reduce(0) { $0 + $1.size }
    }

    public var rawTotalSize: Int64 { totalSize }
    
    public var formattedTotalSize: String {
        return ByteSize.string(totalSize, countStyle: .file)
    }
}

public struct CleanResult: Equatable {
    public let deletedBytes: Int64
    public let deletedCount: Int
    public let failedCount: Int
    public var skippedCount: Int = 0
    /// Set when nothing was cleaned because a safety precondition failed (e.g. unreadable whitelist).
    public var abortMessage: String? = nil
    /// lsof could not run, so everything outside the Trash was skipped.
    public var openFileCheckUnavailable: Bool = false
}

enum CleanerItemPolicy {
    /// Cache/log entries named after a running app's bundle id (or a helper "<id>.xxx") are in use: skip them.
    static func shouldSkip(itemName: String, runningBundleIdentifiers: Set<String>) -> Bool {
        runningBundleIdentifiers.contains { id in
            !id.isEmpty && (itemName == id || itemName.hasPrefix(id + "."))
        }
    }

    /// Only entries already inside the Trash are removed permanently; everything else goes to the Trash.
    static func isInTrash(path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let trash = URL(fileURLWithPath: homeDirectory).appendingPathComponent(".Trash", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let item = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        return item.path != trash.path && item.pathComponents.starts(with: trash.pathComponents)
    }
}

enum AppUninstallPolicy {
    private static let systemRoots = ["/System/"]
    private static let protectedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.Safari",
        "com.apple.AppStore",
        "com.apple.systempreferences",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver"
    ]

    /// Apple apps in /Applications (Xcode, Pages, GarageBand...) are removable; only OS-owned ones are protected.
    static func isSystemApp(bundlePath: String, bundleIdentifier: String) -> Bool {
        let path = URL(fileURLWithPath: bundlePath).standardizedFileURL.resolvingSymlinksInPath().path
        if systemRoots.contains(where: { path.hasPrefix($0) }) { return true }
        return protectedBundleIdentifiers.contains(bundleIdentifier)
    }

    /// Bundle id / name come from the target's Info.plist and are used to build paths: reject anything path-like.
    static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("/")
            && !value.contains("\0")
            && !value.contains("..")
    }
}

public struct UninstallResult: Equatable {
    public let success: Bool
    /// Localized, user-facing error (nil on success).
    public let errorMessage: String?
    public let failedPaths: [String]

    static let ok = UninstallResult(success: true, errorMessage: nil, failedPaths: [])
}

public struct AppAssociatedFile: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let fileType: String // "Application Support", "Caches", "Preferences", "Container", etc.
    public let size: Int64
    public let confidence: AssociationConfidence
    public var isSelected: Bool
    
    public var formattedSize: String {
        return ByteSize.string(size, countStyle: .file)
    }
}

public enum AssociationConfidence: String, Hashable {
    case verified = "Xác định"
    case inferred = "Suy đoán"

    var title: String { L10n.text(rawValue) }
}

enum UninstallPathPolicy {
    static func isAllowed(
        path: String,
        bundlePath: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> Bool {
        guard !HomePathGuard.hasRelativeComponents(path) else { return false }
        let candidate = HomePathGuard.resolve(path)
        let bundle = HomePathGuard.resolve(bundlePath)
        let home = HomePathGuard.resolvedHome(homeDirectory)

        if candidate.path == bundle.path {
            let applicationRoots = [
                HomePathGuard.resolve("/Applications"),
                HomePathGuard.trustedRoot("Applications", home: home)
            ].compactMap { $0 }
            return applicationRoots.contains { HomePathGuard.isStrictDescendant(candidate, of: $0) }
        }

        return libraryRoots.contains { relative in
            guard let root = HomePathGuard.trustedRoot("Library/\(relative)", home: home) else { return false }
            return HomePathGuard.isStrictDescendant(candidate, of: root)
        }
    }

    static let libraryRoots = [
        "Application Support",
        "Caches",
        "Preferences",
        "Saved Application State",
        "Containers",
        "Group Containers",
        "WebKit",
        "HTTPStorages",
        "LaunchAgents",
        "Application Scripts",
        "Logs",
        "Cookies"
    ]
}

public struct InstalledAppItem: Identifiable, Hashable {
    public var id: String { bundlePath }
    public let name: String
    public let bundleIdentifier: String
    public let bundlePath: String
    public let version: String
    public let isSystemApp: Bool
    public var associatedFiles: [AppAssociatedFile]
    public var isSelected: Bool
    
    public var bundleSize: Int64 {
        return associatedFiles.first(where: { $0.path == bundlePath })?.size ?? 0
    }
    
    public var totalSize: Int64 {
        return associatedFiles.reduce(0) { $0 + $1.size }
    }
    
    public var selectedSize: Int64 {
        return associatedFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    public var formattedTotalSize: String {
        return ByteSize.string(totalSize, countStyle: .file)
    }
}
