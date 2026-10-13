import Cocoa

public struct JunkItem: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: Int64
    public var isSelected: Bool
    
    public var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

public struct JunkCategory: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let iconName: String
    public var items: [JunkItem]
    public var isSelected: Bool
    
    public var totalSize: Int64 {
        return items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    public var rawTotalSize: Int64 {
        return items.reduce(0) { $0 + $1.size }
    }
    
    public var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

public struct CleanResult: Equatable {
    public let deletedBytes: Int64
    public let deletedCount: Int
    public let failedCount: Int
}

enum CleanerPathPolicy {
    static func isAllowed(itemPath: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let itemURL = URL(fileURLWithPath: itemPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let homeURL = URL(fileURLWithPath: homeDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let allowedRoots = [
            homeURL.appendingPathComponent("Library/Caches", isDirectory: true),
            homeURL.appendingPathComponent("Library/Logs", isDirectory: true),
            homeURL.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
            homeURL.appendingPathComponent(".Trash", isDirectory: true)
        ].map { $0.standardizedFileURL.resolvingSymlinksInPath() }

        return allowedRoots.contains { root in
            itemURL.path != root.path
                && itemURL.pathComponents.starts(with: root.pathComponents)
        }
    }
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
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

public enum AssociationConfidence: String, Hashable {
    case verified = "Xác định"
    case inferred = "Suy đoán"
}

enum UninstallPathPolicy {
    static func isAllowed(
        path: String,
        bundlePath: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> Bool {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let bundle = URL(fileURLWithPath: bundlePath).standardizedFileURL.resolvingSymlinksInPath()
        let home = URL(fileURLWithPath: homeDirectory).standardizedFileURL.resolvingSymlinksInPath()

        if candidate.path == bundle.path {
            let applicationRoots = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true)
            ].map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            return applicationRoots.contains { root in
                candidate.pathComponents.starts(with: root.pathComponents)
                    && candidate.path != root.path
            }
        }

        let libraryRoot = home.appendingPathComponent("Library", isDirectory: true)
        let allowedLibraryRoots = [
            "Application Support",
            "Caches",
            "Preferences",
            "Saved Application State",
            "Containers",
            "WebKit",
            "HTTPStorages"
        ].map {
            libraryRoot.appendingPathComponent($0, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }
        return allowedLibraryRoots.contains { root in
            candidate.path != root.path
                && candidate.pathComponents.starts(with: root.pathComponents)
        }
    }
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
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
