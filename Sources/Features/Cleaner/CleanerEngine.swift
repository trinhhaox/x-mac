import Cocoa

public class CleanerEngine: ObservableObject {
    public static let shared = CleanerEngine()
    
    @Published public var categories: [JunkCategory] = []
    @Published public var isScanning: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var lastCleanedBytes: Int64 = 0
    
    private let fileManager = FileManager.default
    
    private init() {}

    static func selectedSize(in categories: [JunkCategory]) -> Int64 {
        categories.reduce(0) { $0 + $1.selectedSize }
    }

    static func discoveredSize(in categories: [JunkCategory]) -> Int64 {
        categories.reduce(0) { $0 + $1.totalSize }
    }

    static func selectedItems(in categories: [JunkCategory]) -> [JunkItem] {
        categories.flatMap { category in
            category.items.filter(\.isSelected)
        }
    }
    
    public var totalSelectedSize: Int64 {
        return Self.selectedSize(in: categories)
    }
    
    public var formattedTotalSelectedSize: String {
        return ByteSize.string(totalSelectedSize, countStyle: .file)
    }

    public var totalDiscoveredSize: Int64 {
        Self.discoveredSize(in: categories)
    }

    public var formattedTotalDiscoveredSize: String {
        ByteSize.string(totalDiscoveredSize, countStyle: .file)
    }
    
    public func startScan() {
        guard !isScanning else { return }
        self.isScanning = true
        self.categories = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            var scannedCategories: [JunkCategory] = []
            
            // 1. User Caches
            let cachePath = ("~/Library/Caches" as NSString).expandingTildeInPath
            let cacheCategory = self.scanDirectory(
                name: L10n.text("Bộ nhớ đệm người dùng (User Caches)"),
                description: L10n.text("Dữ liệu cache tạm thời của các ứng dụng giúp tăng tốc độ nhưng có thể tích tụ qua thời gian."),
                iconName: "cylinder.split.1x2",
                directoryPath: cachePath
            )
            scannedCategories.append(cacheCategory)
            
            // 2. System & User Logs
            let logPath = ("~/Library/Logs" as NSString).expandingTildeInPath
            let logCategory = self.scanDirectory(
                name: L10n.text("Nhật ký ứng dụng & hệ thống (Logs)"),
                description: L10n.text("Các file nhật ký ghi lại sự kiện và lỗi phần mềm, thường không còn cần thiết."),
                iconName: "doc.text.magnifyingglass",
                directoryPath: logPath,
                excludingNames: ["DiagnosticReports"]
            )
            scannedCategories.append(logCategory)
            
            // 3. Crash Reports
            let crashPath = ("~/Library/Logs/DiagnosticReports" as NSString).expandingTildeInPath
            let crashCategory = self.scanDirectory(
                name: L10n.text("Báo cáo lỗi (Crash & Diagnostic Reports)"),
                description: L10n.text("Báo cáo lỗi tự động gửi khi ứng dụng bị tắt đột ngột."),
                iconName: "exclamationmark.triangle",
                directoryPath: crashPath
            )
            scannedCategories.append(crashCategory)
            
            // 4. Xcode & Developer Caches
            let xcodePath = ("~/Library/Developer/Xcode/DerivedData" as NSString).expandingTildeInPath
            let xcodeCategory = self.scanDirectory(
                name: L10n.text("Dữ liệu biên dịch Xcode (DerivedData)"),
                description: L10n.text("Bộ nhớ cache biên dịch dự án của lập trình viên, có thể giải phóng dung lượng rất lớn."),
                iconName: "hammer",
                directoryPath: xcodePath
            )
            if !xcodeCategory.items.isEmpty {
                scannedCategories.append(xcodeCategory)
            }
            
            // 5. Thùng rác (Trash)
            let trashPath = ("~/.Trash" as NSString).expandingTildeInPath
            let trashCategory = self.scanDirectory(
                name: L10n.text("Thùng rác (Trash)"),
                description: L10n.text("Các tệp tin bạn đã xóa nhưng vẫn lưu trữ trong Thùng rác hệ thống."),
                iconName: "trash",
                directoryPath: trashPath
            )
            scannedCategories.append(trashCategory)
            
            DispatchQueue.main.async {
                self.categories = scannedCategories
                self.isScanning = false
            }
        }
    }
    
    private func scanDirectory(
        name: String,
        description: String,
        iconName: String,
        directoryPath: String,
        excludingNames: Set<String> = []
    ) -> JunkCategory {
        var items: [JunkItem] = []
        guard fileManager.fileExists(atPath: directoryPath) else {
            return JunkCategory(name: name, description: description, iconName: iconName, items: [], isSelected: false)
        }
        
        if let subpaths = try? fileManager.contentsOfDirectory(atPath: directoryPath) {
            for sub in subpaths {
                if sub.hasPrefix(".") || excludingNames.contains(sub) { continue }
                let fullPath = (directoryPath as NSString).appendingPathComponent(sub)
                let size = getFileSize(atPath: fullPath)
                if size > 1024 * 50 { // Chỉ hiển thị các mục lớn hơn 50 KB
                    items.append(JunkItem(name: sub, path: fullPath, size: size, isSelected: false))
                }
            }
        }
        
        items.sort { $0.size > $1.size }
        return JunkCategory(name: name, description: description, iconName: iconName, items: items, isSelected: false)
    }
    
    public func cleanSelectedJunk(completion: @escaping (CleanResult) -> Void) {
        guard !isCleaning else { return }
        self.isCleaning = true
        let selectedCategories = categories
        
        DispatchQueue.global(qos: .userInitiated).async {
            var freedBytes: Int64 = 0
            var deletedCount = 0
            var failedCount = 0
            var skippedCount = 0
            let runningIds = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            
            for item in Self.selectedItems(in: selectedCategories) {
                guard CleanerPathPolicy.isAllowed(itemPath: item.path) else {
                    NSLog("Xmac Cleaner rejected unsafe path: \(item.path)")
                    failedCount += 1
                    continue
                }
                let inTrash = CleanerItemPolicy.isInTrash(path: item.path)
                if !inTrash, CleanerItemPolicy.shouldSkip(itemName: item.name, runningBundleIdentifiers: runningIds) {
                    skippedCount += 1
                    continue
                }
                do {
                    if inTrash {
                        try self.fileManager.removeItem(atPath: item.path)
                    } else {
                        try self.fileManager.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    }
                    freedBytes += item.size
                    deletedCount += 1
                } catch {
                    NSLog("Xmac Cleaner delete error: \(error)")
                    failedCount += 1
                }
            }
            
            if deletedCount > 0 {
                SoundEffectManager.shared.play(.clean)
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.lastCleanedBytes = freedBytes
                self.startScan() // Quét lại để cập nhật số liệu mới
                completion(CleanResult(
                    deletedBytes: freedBytes,
                    deletedCount: deletedCount,
                    failedCount: failedCount,
                    skippedCount: skippedCount
                ))
            }
        }
    }
    
    public func purgeMemory(completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
            let success: Bool
            do {
                try process.run()
                process.waitUntilExit()
                success = process.terminationStatus == 0
            } catch {
                NSLog("Xmac purge error: \(error)")
                success = false
            }
            if success {
                SoundEffectManager.shared.play(.clean)
            }
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }
    
    private func getFileSize(atPath path: String) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        
        if !isDir.boolValue {
            let attr = try? fileManager.attributesOfItem(atPath: path)
            return (attr?[.size] as? Int64) ?? 0
        }
        
        var totalSize: Int64 = 0
        if let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                   let isDirectory = resourceValues.isDirectory, !isDirectory,
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        return totalSize
    }
}
