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
        
        let isSystemApp = bundlePath.hasPrefix("/System/") || bundleId.hasPrefix("com.apple.")
        
        var associatedFiles: [AppAssociatedFile] = []
        
        // 1. Bundle file
        let bundleSize = getFileSize(atPath: bundlePath)
        associatedFiles.append(AppAssociatedFile(
            name: (bundlePath as NSString).lastPathComponent,
            path: bundlePath,
            fileType: "Application Bundle",
            size: bundleSize,
            isSelected: true
        ))
        
        // 2. Quét các file phụ trợ nếu có bundleIdentifier hợp lệ
        if !bundleId.isEmpty {
            let libraryPath = ("~/Library" as NSString).expandingTildeInPath
            
            // Application Support
            let appSupport1 = "\(libraryPath)/Application Support/\(bundleId)"
            let appSupport2 = "\(libraryPath)/Application Support/\(appName)"
            addAssociatedIfExists(path: appSupport1, type: "Application Support", to: &associatedFiles)
            if appSupport1 != appSupport2 {
                addAssociatedIfExists(path: appSupport2, type: "Application Support", to: &associatedFiles)
            }
            
            // Caches
            let cache1 = "\(libraryPath)/Caches/\(bundleId)"
            let cache2 = "\(libraryPath)/Caches/\(appName)"
            addAssociatedIfExists(path: cache1, type: "Caches", to: &associatedFiles)
            if cache1 != cache2 {
                addAssociatedIfExists(path: cache2, type: "Caches", to: &associatedFiles)
            }
            
            // Preferences .plist
            let prefPath = "\(libraryPath)/Preferences/\(bundleId).plist"
            addAssociatedIfExists(path: prefPath, type: "Preferences", to: &associatedFiles)
            
            // Saved Application State
            let savedState = "\(libraryPath)/Saved Application State/\(bundleId).savedState"
            addAssociatedIfExists(path: savedState, type: "Saved State", to: &associatedFiles)
            
            // Containers (Sandbox)
            let containerPath = "\(libraryPath)/Containers/\(bundleId)"
            addAssociatedIfExists(path: containerPath, type: "Sandbox Container", to: &associatedFiles)
            
            // WebKit data
            let webKitPath = "\(libraryPath)/WebKit/\(bundleId)"
            addAssociatedIfExists(path: webKitPath, type: "WebKit Data", to: &associatedFiles)
            
            // HTTPStorages
            let httpStorage = "\(libraryPath)/HTTPStorages/\(bundleId)"
            addAssociatedIfExists(path: httpStorage, type: "HTTP Storages", to: &associatedFiles)
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
    
    private func addAssociatedIfExists(path: String, type: String, to list: inout [AppAssociatedFile]) {
        guard fileManager.fileExists(atPath: path) else { return }
        let size = getFileSize(atPath: path)
        list.append(AppAssociatedFile(
            name: (path as NSString).lastPathComponent,
            path: path,
            fileType: type,
            size: size,
            isSelected: true
        ))
    }
    
    public func uninstallApp(_ app: InstalledAppItem, completion: @escaping (Bool) -> Void) {
        guard !isUninstalling, !app.isSystemApp else { return }
        self.isUninstalling = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var allSucceeded = true
            
            for file in app.associatedFiles where file.isSelected {
                let url = URL(fileURLWithPath: file.path)
                do {
                    // Chuyển vào Thùng rác để đảm bảo an toàn
                    try self.fileManager.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    NSLog("Xmac Uninstall error moving \(file.path) to Trash: \(error)")
                    allSucceeded = false
                }
            }
            
            SoundEffectManager.shared.play(.clean)
            
            DispatchQueue.main.async {
                self.isUninstalling = false
                self.scanApps() // Quét lại danh sách app
                completion(allSucceeded)
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
