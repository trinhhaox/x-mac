import Foundation

/// Represents a set of files that share identical byte content.
public struct DuplicateGroup: Identifiable, Sendable, Codable, Hashable {
    public var id: String { keeper }
    public let size: Int64
    public let keeper: String
    public let duplicates: [String]
    public var isSelected: Bool

    public init(size: Int64, keeper: String, duplicates: [String], isSelected: Bool = true) {
        self.size = size
        self.keeper = keeper
        self.duplicates = duplicates
        self.isSelected = isSelected
    }

    public var allFiles: [String] {
        [keeper] + duplicates
    }

    /// Dung lượng tiết kiệm được khi hợp nhất tất cả các bản sao vào `keeper`.
    public var reclaimableBytes: Int64 {
        size * Int64(duplicates.count)
    }

    public var formattedSize: String {
        ByteSize.string(size, countStyle: .file)
    }

    public var formattedReclaimable: String {
        ByteSize.string(reclaimableBytes, countStyle: .file)
    }

    public var fileName: String {
        URL(fileURLWithPath: keeper).lastPathComponent
    }

    public var categoryName: String {
        let ext = URL(fileURLWithPath: keeper).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "svg", "raw":
            return L10n.text("Hình ảnh")
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return L10n.text("Video")
        case "mp3", "m4a", "wav", "flac", "aac", "ogg":
            return L10n.text("Âm thanh")
        case "zip", "tar", "gz", "bz2", "xz", "7z", "dmg", "iso", "pkg":
            return L10n.text("Tệp nén & Cài đặt")
        case "pdf", "docx", "xlsx", "pptx", "txt", "md", "csv", "json":
            return L10n.text("Tài liệu")
        case "js", "ts", "swift", "py", "rs", "go", "cpp", "c", "h", "java", "kt":
            return L10n.text("Mã nguồn")
        default:
            return L10n.text("Tệp khác")
        }
    }
}

public struct DeduplicatorScanOptions: Sendable {
    public var rootPaths: [String]
    public var minSizeBytes: Int64
    public var skipPaths: Set<String>

    public init(
        rootPaths: [String] = [
            NSHomeDirectory() + "/Downloads",
            NSHomeDirectory() + "/Documents",
            NSHomeDirectory() + "/Desktop"
        ],
        minSizeBytes: Int64 = 64 * 1024,
        skipPaths: Set<String> = [
            NSHomeDirectory() + "/Library",
            NSHomeDirectory() + "/.Trash"
        ]
    ) {
        self.rootPaths = rootPaths
        self.minSizeBytes = minSizeBytes
        self.skipPaths = skipPaths
    }
}

public enum DeduplicatorPhase: Equatable, Sendable {
    case idle
    case scanningDirectories(scannedFiles: Int)
    case edgeHashing(done: Int, total: Int)
    case fullHashing(done: Int, total: Int)
    case byteVerifying(done: Int, total: Int)
    case cloning(done: Int, total: Int, currentPath: String)
    case done
}

public struct DeduplicatorScanReport: Sendable {
    public var groups: [DuplicateGroup]
    public var filesScanned: Int
    public var bytesScanned: Int64
    public var durationSeconds: Double

    public init(groups: [DuplicateGroup] = [], filesScanned: Int = 0, bytesScanned: Int64 = 0, durationSeconds: Double = 0) {
        self.groups = groups
        self.filesScanned = filesScanned
        self.bytesScanned = bytesScanned
        self.durationSeconds = durationSeconds
    }

    public var totalReclaimableBytes: Int64 {
        groups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var totalDuplicateFilesCount: Int {
        groups.reduce(0) { $0 + $1.duplicates.count }
    }
}
