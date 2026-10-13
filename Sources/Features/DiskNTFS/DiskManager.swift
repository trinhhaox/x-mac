import Cocoa

public class DiskManager: ObservableObject {
    public static let shared = DiskManager()
    
    @Published public var volumes: [DiskVolume] = []
    @Published public var isLoading: Bool = false
    
    private init() {
        refreshVolumes()
        setupDiskNotifications()
    }
    
    private func setupDiskNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(onDiskEvent), name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(onDiskEvent), name: NSWorkspace.didUnmountNotification, object: nil)
    }
    
    @objc private func onDiskEvent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshVolumes()
        }
    }
    
    public func refreshVolumes() {
        self.isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = self.scanAllVolumes()
            DispatchQueue.main.async {
                self.volumes = scanned
                self.isLoading = false
            }
        }
    }
    
    private func scanAllVolumes() -> [DiskVolume] {
        var results: [DiskVolume] = []
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["list", "-plist", "external"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let allDisksAndPartitions = plist["AllDisksAndPartitions"] as? [[String: Any]] {
                
                for disk in allDisksAndPartitions {
                    if let partitions = disk["Partitions"] as? [[String: Any]] {
                        for partition in partitions {
                            if let bsd = partition["DeviceIdentifier"] as? String {
                                if let vol = getVolumeInfo(bsdName: bsd) {
                                    results.append(vol)
                                }
                            }
                        }
                    } else if let bsd = disk["DeviceIdentifier"] as? String {
                        if let vol = getVolumeInfo(bsdName: bsd) {
                            results.append(vol)
                        }
                    }
                }
            }
        } catch {
            NSLog("Xmac scan external disks error: \(error)")
        }
        
        // Nếu không có ổ external nào, quét thêm ổ local để hiển thị demo/thông tin
        if results.isEmpty {
            let internalVols = scanInternalVolumes()
            results.append(contentsOf: internalVols)
        }
        
        return results
    }
    
    private func scanInternalVolumes() -> [DiskVolume] {
        var list: [DiskVolume] = []
        let fm = FileManager.default
        let mountedURLs = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey, .volumeIsInternalKey], options: [.skipHiddenVolumes]) ?? []
        
        for url in mountedURLs {
            let res = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey, .volumeIsInternalKey])
            let name = res?.volumeName ?? url.lastPathComponent
            let total = Int64(res?.volumeTotalCapacity ?? 0)
            let free = Int64(res?.volumeAvailableCapacity ?? 0)
            let isReadOnly = res?.volumeIsReadOnly ?? false
            let isInternal = res?.volumeIsInternal ?? true
            
            let vol = DiskVolume(
                name: name,
                bsdName: url.lastPathComponent,
                mountPoint: url.path,
                fileSystem: "APFS/Native",
                totalSize: total,
                freeSize: free,
                isExternal: !isInternal,
                isWritable: !isReadOnly,
                isMounted: true
            )
            list.append(vol)
        }
        return list
    }
    
    public func getVolumeInfo(bsdName: String) -> DiskVolume? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", bsdName]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                return nil
            }
            
            let name = (plist["VolumeName"] as? String) ?? (plist["MediaName"] as? String) ?? bsdName
            let mountPoint = plist["MountPoint"] as? String
            let fs = (plist["FilesystemType"] as? String) ?? (plist["FilesystemName"] as? String) ?? "Unknown"
            let totalSize = (plist["TotalSize"] as? Int64) ?? 0
            let freeSize = (plist["FreeSpace"] as? Int64) ?? 0
            let isWritable = (plist["WritableVolume"] as? Bool) ?? false
            let isMounted = (plist["Mounted"] as? Bool) ?? (mountPoint != nil)
            let isInternal = (plist["Internal"] as? Bool) ?? false
            
            return DiskVolume(
                name: name,
                bsdName: bsdName,
                mountPoint: mountPoint,
                fileSystem: fs,
                totalSize: totalSize,
                freeSize: freeSize,
                isExternal: !isInternal,
                isWritable: isWritable,
                isMounted: isMounted
            )
        } catch {
            return nil
        }
    }
}
