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
        associatedFiles.append(AppAssociatedFile(
            name: (bundlePath as NSString).lastPathComponent,
            path: bundlePath,
            fileType: "Application Bundle",
            size: DirectorySize.bytes(atPath: bundlePath, fileManager: fileManager),
            confidence: .verified,
            isSelected: true
        ))
        
        // 2. Quét các file phụ trợ nếu có bundleIdentifier hợp lệ
        // Info.plist là dữ liệu không tin cậy: bỏ qua tệp phụ trợ nếu id/tên có thể thoát khỏi thư mục Library
        if AppUninstallPolicy.isSafePathComponent(bundleId) && AppUninstallPolicy.isSafePathComponent(appName) {
            let locator = AppLeftoverLocator(library: ("~/Library" as NSString).expandingTildeInPath, fileManager: fileManager)
            for candidate in locator.candidates(bundleIdentifier: bundleId, appName: appName, bundlePath: bundlePath) {
                associatedFiles.append(AppAssociatedFile(
                    name: (candidate.path as NSString).lastPathComponent,
                    path: candidate.path,
                    fileType: candidate.type,
                    size: DirectorySize.bytes(atPath: candidate.path, fileManager: fileManager),
                    confidence: candidate.confidence,
                    isSelected: candidate.confidence == .verified
                ))
            }
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
            var journal: [CleanupLogEntry] = []
            let result = Self.performUninstall(
                app,
                trash: { url in
                    try AppTrashMover.trash(url, fileManager: self.fileManager)
                },
                record: { file, outcome, reason in
                    journal.append(CleanupLogEntry(date: Date(), action: .uninstall, path: file.path, bytes: file.size, outcome: outcome, reason: reason))
                }
            )
            CleanupOperationLog.shared.append(journal)
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
    /// Launch agents are unloaded before they are moved, otherwise launchd keeps respawning them.
    static func performUninstall(
        _ app: InstalledAppItem,
        trash: (URL) throws -> Void,
        unloadLaunchAgent: (URL) -> Void = LaunchAgentControl.bootOut,
        record: (AppAssociatedFile, CleanupLogEntry.Outcome, String?) -> Void = { _, _, _ in }
    ) -> UninstallResult {
        let selectedFiles = app.associatedFiles.filter(\.isSelected)
        guard !selectedFiles.isEmpty else {
            return UninstallResult(success: false, errorMessage: nil, failedPaths: [])
        }
        let auxiliaryFiles = selectedFiles.filter { $0.path != app.bundlePath }

        if let bundleFile = selectedFiles.first(where: { $0.path == app.bundlePath }) {
            guard UninstallPathPolicy.isAllowed(path: app.bundlePath, bundlePath: app.bundlePath) else {
                NSLog("Xmac Uninstall rejected unsafe bundle path: \(app.bundlePath)")
                record(bundleFile, .failed, "path not allowed")
                return UninstallResult(
                    success: false,
                    errorMessage: L10n.format("Không thể gỡ %@: đường dẫn ứng dụng không hợp lệ.", app.name),
                    failedPaths: [app.bundlePath]
                )
            }
            do {
                try trash(URL(fileURLWithPath: app.bundlePath))
                record(bundleFile, .trashed, nil)
            } catch {
                NSLog("Xmac Uninstall error moving app bundle to Trash: \(error)")
                record(bundleFile, .failed, error.localizedDescription)
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
                record(file, .failed, "path not allowed")
                continue
            }
            let url = URL(fileURLWithPath: file.path)
            if file.fileType == AppLeftoverLocator.launchAgentType {
                unloadLaunchAgent(url)
            }
            do {
                try trash(url)
                record(file, .trashed, nil)
            } catch {
                NSLog("Xmac Uninstall error moving \(file.path) to Trash: \(error)")
                failedPaths.append(file.path)
                record(file, .failed, error.localizedDescription)
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
}
