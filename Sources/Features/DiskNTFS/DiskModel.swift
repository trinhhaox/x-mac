import Cocoa

public struct DiskVolume: Identifiable, Hashable {
    public var id: String { bsdName }
    public let name: String
    public let bsdName: String // ví dụ: disk4s1
    public let mountPoint: String?
    public let fileSystem: String // NTFS, ExFAT, APFS, MS-DOS (FAT32)...
    public let totalSize: Int64
    public let freeSize: Int64
    public let isExternal: Bool
    public let isWritable: Bool
    public let isMounted: Bool
    
    public var usedSize: Int64 {
        return max(0, totalSize - freeSize)
    }
    
    public var isNTFS: Bool {
        return fileSystem.uppercased().contains("NTFS") || fileSystem.uppercased().contains("WINDOWS")
    }
    
    public var usedPercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(usedSize) / Double(totalSize)
    }

    public var hasReliableCapacity: Bool {
        isMounted && totalSize > 0
    }
    
    public var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    public var formattedFreeSize: String {
        return ByteCountFormatter.string(fromByteCount: freeSize, countStyle: .file)
    }
    
    public var formattedUsedSize: String {
        return ByteCountFormatter.string(fromByteCount: usedSize, countStyle: .file)
    }
}
