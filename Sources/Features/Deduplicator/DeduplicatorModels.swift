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

    public var category: DeduplicatorFileCategory {
        let ext = URL(fileURLWithPath: keeper).pathExtension.lowercased()
        for cat in DeduplicatorFileCategory.allCases where cat != .all {
            if cat.extensions.contains(ext) {
                return cat
            }
        }
        return .all
    }

    public var categoryName: String {
        category == .all ? L10n.text("Tệp khác") : category.title
    }
}

public enum DeduplicatorFileCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "Tất cả"
    case images = "Hình ảnh"
    case videos = "Video"
    case code = "Mã nguồn"
    case documents = "Tài liệu"
    case archives = "Tệp nén"

    public var id: String { rawValue }

    public var title: String {
        L10n.text(rawValue)
    }

    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .images: return "photo"
        case .videos: return "film"
        case .code: return "curlybraces"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        }
    }

    public var extensions: Set<String> {
        switch self {
        case .all:
            return []
        case .images:
            return ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "svg", "raw", "cr2", "nef", "arw", "bmp", "ico"]
        case .videos:
            return ["mp4", "mov", "mkv", "avi", "webm", "m4v", "flv", "wmv", "3gp", "ts"]
        case .code:
            return ["swift", "py", "js", "ts", "tsx", "jsx", "c", "cpp", "h", "hpp", "go", "rs", "java", "kt", "html", "css", "scss", "json", "yaml", "yml", "md", "sh", "zsh", "sql", "rb", "php", "dart", "xml"]
        case .documents:
            return ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "txt", "rtf", "csv", "pages", "numbers", "key"]
        case .archives:
            return ["zip", "tar", "gz", "bz2", "xz", "7z", "dmg", "iso", "pkg", "rar", "tgz"]
        }
    }

    public func matches(path: String) -> Bool {
        if self == .all { return true }
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return extensions.contains(ext)
    }
}

public enum DeduplicatorScheduleInterval: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily = "Hàng ngày"
    case weekly = "Hàng tuần"
    case monthly = "Hàng tháng"

    public var id: String { rawValue }

    public var title: String {
        L10n.text(rawValue)
    }

    public var timeInterval: TimeInterval {
        switch self {
        case .daily: return 86400
        case .weekly: return 604800
        case .monthly: return 2592000
        }
    }
}

public struct DeduplicatorScanOptions: Sendable {
    public var rootPaths: [String]
    public var minSizeBytes: Int64
    public var skipPaths: Set<String>
    public var category: DeduplicatorFileCategory

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
        ],
        category: DeduplicatorFileCategory = .all
    ) {
        self.rootPaths = rootPaths
        self.minSizeBytes = minSizeBytes
        self.skipPaths = skipPaths
        self.category = category
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
