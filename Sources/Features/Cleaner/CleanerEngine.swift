import Cocoa

public class CleanerEngine: ObservableObject {
    public static let shared = CleanerEngine()
    
    @Published public var categories: [JunkCategory] = []
    @Published public var isScanning: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var lastCleanedBytes: Int64 = 0
    
    private let fileManager = FileManager.default
    private let whitelist: CleanerWhitelist
    private let operationLog: CleanupOperationLog
    
    private init(whitelist: CleanerWhitelist = .shared, operationLog: CleanupOperationLog = .shared) {
        self.whitelist = whitelist
        self.operationLog = operationLog
    }

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
            // An unreadable whitelist hides nothing here; cleaning refuses to run on it anyway.
            let scanner = JunkScanner(protectedPaths: (try? self.whitelist.load()) ?? [])
            let scannedCategories = scanner.scanAll()
            
            DispatchQueue.main.async {
                self.categories = scannedCategories
                self.isScanning = false
            }
        }
    }

    /// Protects one item from future cleanups and drops it from the current results.
    public func protect(_ item: JunkItem) throws {
        try whitelist.add(item.path)
        for index in categories.indices {
            categories[index].items.removeAll { $0.path == item.path }
        }
    }

    enum Decision: Equatable {
        case trash
        case deletePermanently
        case skip(reason: String)
        case reject
    }

    /// What to do with one selected item. Anything that cannot be shown safe is skipped.
    static func decide(
        item: JunkItem,
        protectedPaths: [String],
        openFiles: OpenFileSnapshot?,
        runningBundleIdentifiers: Set<String>,
        homeDirectory: String = NSHomeDirectory()
    ) -> Decision {
        guard CleanerPathPolicy.isAllowed(itemPath: item.path, homeDirectory: homeDirectory) else { return .reject }
        if CleanerWhitelist.isProtected(item.path, by: protectedPaths) { return .skip(reason: "whitelisted") }
        if CleanerItemPolicy.isInTrash(path: item.path, homeDirectory: homeDirectory) { return .deletePermanently }
        let entryName = (item.path as NSString).lastPathComponent
        if CleanerItemPolicy.shouldSkip(itemName: entryName, runningBundleIdentifiers: runningBundleIdentifiers) {
            return .skip(reason: "app running")
        }
        guard let openFiles else { return .skip(reason: "open-file check unavailable") }
        if openFiles.isInUse(item.path) { return .skip(reason: "in use") }
        return .trash
    }
    
    public func cleanSelectedJunk(completion: @escaping (CleanResult) -> Void) {
        guard !isCleaning else { return }
        self.isCleaning = true
        let selectedCategories = categories
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.clean(Self.selectedItems(in: selectedCategories))
            if result.deletedCount > 0 {
                SoundEffectManager.shared.play(.clean)
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.lastCleanedBytes = result.deletedBytes
                self.startScan() // Quét lại để cập nhật số liệu mới
                completion(result)
            }
        }
    }

    private func clean(_ items: [JunkItem]) -> CleanResult {
        let protectedPaths: [String]
        do {
            protectedPaths = try whitelist.load()
        } catch {
            return CleanResult(
                deletedBytes: 0, deletedCount: 0, failedCount: 0,
                abortMessage: L10n.text("Không đọc được danh sách mục được bảo vệ nên chưa dọn gì. Hãy kiểm tra tệp cleaner-whitelist.json trong ~/Library/Application Support/Xmac.")
            )
        }
        let runningIds = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let needsOpenFileCheck = items.contains { !CleanerItemPolicy.isInTrash(path: $0.path) }
        let openFiles = needsOpenFileCheck ? OpenFileSnapshot.capture() : nil

        var freedBytes: Int64 = 0
        var deletedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var journal: [CleanupLogEntry] = []
        func record(_ item: JunkItem, _ outcome: CleanupLogEntry.Outcome, _ reason: String? = nil) {
            journal.append(CleanupLogEntry(date: Date(), action: .clean, path: item.path, bytes: item.size, outcome: outcome, reason: reason))
        }

        for item in items {
            let decision = Self.decide(item: item, protectedPaths: protectedPaths, openFiles: openFiles, runningBundleIdentifiers: runningIds)
            do {
                switch decision {
                case .reject:
                    NSLog("Xmac Cleaner rejected unsafe path: \(item.path)")
                    failedCount += 1
                    record(item, .failed, "path not allowed")
                    continue
                case .skip(let reason):
                    skippedCount += 1
                    record(item, .skipped, reason)
                    continue
                case .deletePermanently:
                    try fileManager.removeItem(atPath: item.path)
                    record(item, .deleted)
                case .trash:
                    // The user may protect an item while this run is in progress; an unreadable list now means stop.
                    guard let latest = try? whitelist.load(), !CleanerWhitelist.isProtected(item.path, by: latest) else {
                        skippedCount += 1
                        record(item, .skipped, "whitelisted during cleaning")
                        continue
                    }
                    try fileManager.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    record(item, .trashed)
                }
                freedBytes += item.size
                deletedCount += 1
            } catch {
                NSLog("Xmac Cleaner delete error: \(error)")
                failedCount += 1
                record(item, .failed, error.localizedDescription)
            }
        }
        operationLog.append(journal)
        return CleanResult(
            deletedBytes: freedBytes, deletedCount: deletedCount, failedCount: failedCount, skippedCount: skippedCount,
            openFileCheckUnavailable: needsOpenFileCheck && openFiles == nil
        )
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
}
