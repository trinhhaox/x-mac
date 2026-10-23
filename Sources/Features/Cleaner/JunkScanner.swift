import Cocoa

/// Builds the cleaner's categories. Every item it returns must also pass `CleanerPathPolicy`.
struct JunkScanner {
    /// Entries smaller than this are noise in the list.
    static let minimumItemBytes: Int64 = 50 * 1024

    var homeDirectory: String = NSHomeDirectory()
    var protectedPaths: [String] = []
    var fileManager: FileManager = .default

    func scanAll() -> [JunkCategory] {
        var categories: [JunkCategory] = [
            scanDirectory(
                name: L10n.text("Bộ nhớ đệm người dùng (User Caches)"),
                description: L10n.text("Dữ liệu cache tạm thời của các ứng dụng giúp tăng tốc độ nhưng có thể tích tụ qua thời gian."),
                iconName: "cylinder.split.1x2",
                relativePath: "Library/Caches"
            ),
            scanDirectory(
                name: L10n.text("Nhật ký ứng dụng & hệ thống (Logs)"),
                description: L10n.text("Các file nhật ký ghi lại sự kiện và lỗi phần mềm, thường không còn cần thiết."),
                iconName: "doc.text.magnifyingglass",
                relativePath: "Library/Logs",
                // Xmac's own cleanup journal must survive a log cleanup.
                excludingNames: ["DiagnosticReports", "Xmac"]
            ),
            scanDirectory(
                name: L10n.text("Báo cáo lỗi (Crash & Diagnostic Reports)"),
                description: L10n.text("Báo cáo lỗi tự động gửi khi ứng dụng bị tắt đột ngột."),
                iconName: "exclamationmark.triangle",
                relativePath: "Library/Logs/DiagnosticReports"
            )
        ]

        let xcode = scanDirectory(
            name: L10n.text("Dữ liệu biên dịch Xcode (DerivedData)"),
            description: L10n.text("Bộ nhớ cache biên dịch dự án của lập trình viên, có thể giải phóng dung lượng rất lớn."),
            iconName: "hammer",
            relativePath: "Library/Developer/Xcode/DerivedData"
        )
        if !xcode.items.isEmpty { categories.append(xcode) }

        let developer = scanDeveloperCaches()
        if !developer.items.isEmpty { categories.append(developer) }

        let orphans = scanOrphanedAppData()
        if !orphans.items.isEmpty { categories.append(orphans) }

        categories.append(scanDirectory(
            name: L10n.text("Thùng rác (Trash)"),
            description: L10n.text("Các tệp tin bạn đã xóa nhưng vẫn lưu trữ trong Thùng rác hệ thống."),
            iconName: "trash",
            relativePath: ".Trash"
        ))
        return categories
    }

    func scanDeveloperCaches() -> JunkCategory {
        var items: [JunkItem] = []
        for entry in DeveloperCacheCatalog.wholeFolderCaches {
            let path = absolute(entry.relativePath)
            if let item = makeItem(name: "\(entry.name) (~/\(entry.relativePath))", path: path) {
                items.append(item)
            }
        }
        for folder in DeveloperCacheCatalog.childScannedFolders {
            items += childItems(of: absolute(folder.relativePath)) { "\(folder.name) · \($0)" }
        }
        return category(
            name: L10n.text("Bộ nhớ đệm công cụ lập trình"),
            description: L10n.text("Cache của npm, pnpm, Bun, uv, Gradle, Cargo và bản hỗ trợ thiết bị iOS cũ. Công cụ sẽ tự tải lại khi cần; mục đang được dùng sẽ được bỏ qua. Store của pnpm/Bun dùng chung tệp với node_modules nên dung lượng thực giải phóng có thể ít hơn."),
            iconName: "terminal",
            items: items
        )
    }

    func scanOrphanedAppData() -> JunkCategory {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = OrphanedAppDataScanner.scan(
            homeDirectory: homeDirectory,
            installed: OrphanedAppDataScanner.installedBundleIdentifiers(fileManager: fileManager),
            running: running,
            isRegistered: OrphanedAppDataScanner.isRegisteredWithLaunchServices,
            fileManager: fileManager
        )
        let items = candidates.compactMap { makeItem(name: "\($0.bundleIdentifier) · \($0.folder)", path: $0.path) }
        return category(
            name: L10n.text("Dữ liệu sót lại của ứng dụng đã gỡ"),
            description: L10n.text("Thư mục mang tên ứng dụng không còn cài trên máy và không thay đổi trong 30 ngày. Đây là suy đoán: hãy kiểm tra trước khi chọn."),
            iconName: "shippingbox",
            items: items
        )
    }

    private func scanDirectory(
        name: String,
        description: String,
        iconName: String,
        relativePath: String,
        excludingNames: Set<String> = []
    ) -> JunkCategory {
        let items = childItems(of: absolute(relativePath), excluding: excludingNames) { $0 }
        return category(name: name, description: description, iconName: iconName, items: items)
    }

    private func childItems(
        of directory: String,
        excluding excludedNames: Set<String> = [],
        displayName: (String) -> String
    ) -> [JunkItem] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        return names.compactMap { child in
            guard !child.hasPrefix("."), !excludedNames.contains(child) else { return nil }
            return makeItem(name: displayName(child), path: (directory as NSString).appendingPathComponent(child))
        }
    }

    private func makeItem(name: String, path: String) -> JunkItem? {
        guard fileManager.fileExists(atPath: path),
              CleanerPathPolicy.isAllowed(itemPath: path, homeDirectory: homeDirectory),
              !CleanerWhitelist.isProtected(path, by: protectedPaths) else { return nil }
        let size = DirectorySize.bytes(atPath: path, fileManager: fileManager)
        guard size > Self.minimumItemBytes else { return nil }
        return JunkItem(name: name, path: path, size: size, isSelected: false)
    }

    private func category(name: String, description: String, iconName: String, items: [JunkItem]) -> JunkCategory {
        JunkCategory(
            name: name,
            description: description,
            iconName: iconName,
            items: items.sorted { $0.size > $1.size },
            isSelected: false
        )
    }

    private func absolute(_ relativePath: String) -> String {
        (homeDirectory as NSString).appendingPathComponent(relativePath)
    }
}
