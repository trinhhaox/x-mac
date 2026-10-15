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

        return results
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
            let mountPoint = Self.mountPoint(from: plist)
            let fs = (plist["FilesystemType"] as? String) ?? (plist["FilesystemName"] as? String) ?? "Unknown"
            let totalSize = (plist["TotalSize"] as? Int64) ?? 0
            let freeSize = (plist["FreeSpace"] as? Int64) ?? 0
            let isWritable = (plist["WritableVolume"] as? Bool) ?? false
            let isMounted = Self.isMounted(from: plist)
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

    static func mountPoint(from plist: [String: Any]) -> String? {
        guard let value = plist["MountPoint"] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    static func isMounted(from plist: [String: Any]) -> Bool {
        if let mounted = plist["Mounted"] as? Bool {
            return mounted
        }
        return mountPoint(from: plist) != nil
    }
}
