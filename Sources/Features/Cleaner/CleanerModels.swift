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

public struct AppAssociatedFile: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let fileType: String // "Application Support", "Caches", "Preferences", "Container", etc.
    public let size: Int64
    public var isSelected: Bool
    
    public var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
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
