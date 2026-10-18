import Cocoa

public class AppUninstallerEngine: ObservableObject {
    public static let shared = AppUninstallerEngine()
    
    @Published public var apps: [InstalledAppItem] = []
    @Published public var isScanning: Bool = false
    @Published public var isUninstalling: Bool = false
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    public func scanApps() {
        guard !isScanning else { return }
        self.isScanning = true
        self.apps = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            var foundApps: [InstalledAppItem] = []
            
            let directoriesToScan = [
                "/Applications",
                ("~/Applications" as NSString).expandingTildeInPath
            ]
            
            for dir in directoriesToScan {
                guard let items = try? self.fileManager.contentsOfDirectory(atPath: dir) else { continue }
                for item in items where item.hasSuffix(".app") {
                    let fullPath = (dir as NSString).appendingPathComponent(item)
                    if let appInfo = self.parseAppBundle(at: fullPath) {
                        foundApps.append(appInfo)
                    }
                }
            }
            
            foundApps.sort { $0.totalSize > $1.totalSize }
            
            DispatchQueue.main.async {
                self.apps = foundApps
                self.isScanning = false
            }
        }
    }
    
    private func parseAppBundle(at bundlePath: String) -> InstalledAppItem? {
        guard let bundle = Bundle(path: bundlePath) else { return nil }
        
        let bundleId = bundle.bundleIdentifier ?? ""
        let appName = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? (bundlePath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        
        let isSystemApp = AppUninstallPolicy.isSystemApp(bundlePath: bundlePath, bundleIdentifier: bundleId)
        
        var associatedFiles: [AppAssociatedFile] = []
        
        // 1. Bundle file
        let bundleSize = getFileSize(atPath: bundlePath)
        associatedFiles.append(AppAssociatedFile(
            name: (bundlePath as NSString).lastPathComponent,
            path: bundlePath,
            fileType: "Application Bundle",
            size: bundleSize,
            confidence: .verified,
            isSelected: true
        ))
        
        // 2. Quét các file phụ trợ nếu có bundleIdentifier hợp lệ
        // Info.plist là dữ liệu không tin cậy: bỏ qua tệp phụ trợ nếu id/tên có thể thoát khỏi thư mục Library
        if AppUninstallPolicy.isSafePathComponent(bundleId) && AppUninstallPolicy.isSafePathComponent(appName) {
            let libraryPath = ("~/Library" as NSString).expandingTildeInPath
            
            // Application Support
            let appSupport1 = "\(libraryPath)/Application Support/\(bundleId)"
            let appSupport2 = "\(libraryPath)/Application Support/\(appName)"
            addAssociatedIfExists(path: appSupport1, type: "Application Support", confidence: .verified, to: &associatedFiles)
            if appSupport1 != appSupport2 {
                addAssociatedIfExists(path: appSupport2, type: "Application Support", confidence: .inferred, to: &associatedFiles)
            }
            
            // Caches
            let cache1 = "\(libraryPath)/Caches/\(bundleId)"
            let cache2 = "\(libraryPath)/Caches/\(appName)"
            addAssociatedIfExists(path: cache1, type: "Caches", confidence: .verified, to: &associatedFiles)
            if cache1 != cache2 {
                addAssociatedIfExists(path: cache2, type: "Caches", confidence: .inferred, to: &associatedFiles)
            }
            
            // Preferences .plist
            let prefPath = "\(libraryPath)/Preferences/\(bundleId).plist"
            addAssociatedIfExists(path: prefPath, type: "Preferences", confidence: .verified, to: &associatedFiles)
            
            // Saved Application State
            let savedState = "\(libraryPath)/Saved Application State/\(bundleId).savedState"
            addAssociatedIfExists(path: savedState, type: "Saved State", confidence: .verified, to: &associatedFiles)
            
            // Containers (Sandbox)
            let containerPath = "\(libraryPath)/Containers/\(bundleId)"
            addAssociatedIfExists(path: containerPath, type: "Sandbox Container", confidence: .verified, to: &associatedFiles)
            
            // WebKit data
            let webKitPath = "\(libraryPath)/WebKit/\(bundleId)"
            addAssociatedIfExists(path: webKitPath, type: "WebKit Data", confidence: .verified, to: &associatedFiles)
            
            // HTTPStorages
            let httpStorage = "\(libraryPath)/HTTPStorages/\(bundleId)"
            addAssociatedIfExists(path: httpStorage, type: "HTTP Storages", confidence: .verified, to: &associatedFiles)
        }
        
        return InstalledAppItem(
            name: appName,
            bundleIdentifier: bundleId,
            bundlePath: bundlePath,
            version: version,
            isSystemApp: isSystemApp,
            associatedFiles: associatedFiles,
            isSelected: false
        )
    }
    
    private func addAssociatedIfExists(
        path: String,
        type: String,
        confidence: AssociationConfidence,
        to list: inout [AppAssociatedFile]
    ) {
        guard fileManager.fileExists(atPath: path),
              !list.contains(where: { $0.path == path }) else { return }
        let size = getFileSize(atPath: path)
        list.append(AppAssociatedFile(
            name: (path as NSString).lastPathComponent,
            path: path,
            fileType: type,
            size: size,
            confidence: confidence,
            isSelected: confidence == .verified
        ))
    }
    
    public func uninstallApp(_ app: InstalledAppItem, completion: @escaping (UninstallResult) -> Void) {
        guard !isUninstalling, !app.isSystemApp else {
            completion(UninstallResult(success: false, errorMessage: nil, failedPaths: []))
            return
        }
        guard let currentBundle = Bundle(path: app.bundlePath),
              app.bundleIdentifier.isEmpty || currentBundle.bundleIdentifier == app.bundleIdentifier else {
            completion(UninstallResult(success: false, errorMessage: nil, failedPaths: []))
            return
        }
        if Self.isRunning(bundleIdentifier: app.bundleIdentifier) {
            completion(UninstallResult(
                success: false,
                errorMessage: L10n.format("%@ đang chạy. Hãy thoát ứng dụng trước khi gỡ bỏ.", app.name),
                failedPaths: []
            ))
            return
        }
        self.isUninstalling = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.performUninstall(app) { url in
                // Chuyển vào Thùng rác để đảm bảo an toàn
                try self.fileManager.trashItem(at: url, resultingItemURL: nil)
            }
            if result.success {
                SoundEffectManager.shared.play(.clean)
            }
            
            DispatchQueue.main.async {
                self.isUninstalling = false
                self.scanApps() // Quét lại danh sách app
                completion(result)
            }
        }
    }

    private static func isRunning(bundleIdentifier: String) -> Bool {
        guard !bundleIdentifier.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Gỡ app bundle trước; nếu thất bại thì dừng, không đụng tới tệp phụ trợ.
    static func performUninstall(_ app: InstalledAppItem, trash: (URL) throws -> Void) -> UninstallResult {
        let selectedFiles = app.associatedFiles.filter(\.isSelected)
        guard !selectedFiles.isEmpty else {
            return UninstallResult(success: false, errorMessage: nil, failedPaths: [])
        }
        let auxiliaryFiles = selectedFiles.filter { $0.path != app.bundlePath }

        if selectedFiles.contains(where: { $0.path == app.bundlePath }) {
            guard UninstallPathPolicy.isAllowed(path: app.bundlePath, bundlePath: app.bundlePath) else {
                NSLog("Xmac Uninstall rejected unsafe bundle path: \(app.bundlePath)")
                return UninstallResult(
                    success: false,
                    errorMessage: L10n.format("Không thể gỡ %@: đường dẫn ứng dụng không hợp lệ.", app.name),
                    failedPaths: [app.bundlePath]
                )
            }
            do {
                try trash(URL(fileURLWithPath: app.bundlePath))
            } catch {
                NSLog("Xmac Uninstall error moving app bundle to Trash: \(error)")
                return UninstallResult(
                    success: false,
                    errorMessage: L10n.format("Không thể chuyển %@ vào Thùng rác. Chưa có tệp nào bị thay đổi.", app.name),
                    failedPaths: [app.bundlePath]
                )
            }
        }

        var failedPaths: [String] = []
        for file in auxiliaryFiles {
            guard UninstallPathPolicy.isAllowed(path: file.path, bundlePath: app.bundlePath) else {
                NSLog("Xmac Uninstall rejected unsafe path: \(file.path)")
                failedPaths.append(file.path)
                continue
            }
            do {
                try trash(URL(fileURLWithPath: file.path))
            } catch {
                NSLog("Xmac Uninstall error moving \(file.path) to Trash: \(error)")
                failedPaths.append(file.path)
            }
        }
        guard failedPaths.isEmpty else {
            let names = failedPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return UninstallResult(
                success: false,
                errorMessage: L10n.format("Đã gỡ %@ nhưng %lld tệp phụ trợ không chuyển được vào Thùng rác: %@", app.name, Int64(failedPaths.count), names),
                failedPaths: failedPaths
            )
        }
        return .ok
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
