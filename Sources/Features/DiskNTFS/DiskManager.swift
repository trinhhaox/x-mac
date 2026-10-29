import Cocoa

/// Tags each refresh so results from an older, slower scan never overwrite a newer one.
struct ScanGeneration {
    private(set) var current = 0

    mutating func advance() -> Int {
        current += 1
        return current
    }

    func isCurrent(_ generation: Int) -> Bool { generation == current }
}

public class DiskManager: ObservableObject {
    public static let shared = DiskManager()
    
    @Published public var volumes: [DiskVolume] = []
    @Published public var isLoading: Bool = false
    
    private var scanGeneration = ScanGeneration()

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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.refreshVolumes() }
            return
        }
        let generation = scanGeneration.advance()
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = self.scanAllVolumes()
            DispatchQueue.main.async {
                // A newer refresh is in flight; its result (and isLoading reset) supersedes this one.
                guard self.scanGeneration.isCurrent(generation) else { return }
                self.volumes = scanned
                self.isLoading = false
            }
        }
    }

    /// Reads stdout to EOF before waiting, so output larger than the pipe buffer cannot deadlock the child.
    private func diskutilOutput(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
    
    private func scanAllVolumes() -> [DiskVolume] {
        var results: [DiskVolume] = []

        do {
            let data = try diskutilOutput(["list", "-plist", "external"])
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let allDisksAndPartitions = plist["AllDisksAndPartitions"] as? [[String: Any]] {
                results = Self.userVolumeIdentifiers(from: allDisksAndPartitions).compactMap(getVolumeInfo(bsdName:))
            }
        } catch {
            NSLog("Xmac scan external disks error: \(error)")
        }

        return results
    }

    /// Partition contents that hold no user data: boot/EFI slices and APFS physical stores,
    /// whose real volumes appear separately under the synthesized container's "APFSVolumes".
    private static let hiddenPartitionContents: Set<String> = [
        "EFI", "Apple_APFS", "Apple_APFS_ISC", "Apple_APFS_Recovery", "Apple_Boot", "Apple_partition_map"
    ]

    static func userVolumeIdentifiers(from allDisksAndPartitions: [[String: Any]]) -> [String] {
        var identifiers: [String] = []
        for disk in allDisksAndPartitions {
            let partitions = (disk["Partitions"] as? [[String: Any]]) ?? []
            let apfsVolumes = (disk["APFSVolumes"] as? [[String: Any]]) ?? []
            if partitions.isEmpty && apfsVolumes.isEmpty {
                // Unpartitioned media formatted directly as a volume (common for USB sticks).
                if disk["APFSPhysicalStores"] == nil, let bsd = disk["DeviceIdentifier"] as? String {
                    identifiers.append(bsd)
                }
                continue
            }
            for partition in partitions {
                guard let bsd = partition["DeviceIdentifier"] as? String,
                      !hiddenPartitionContents.contains((partition["Content"] as? String) ?? "") else { continue }
                identifiers.append(bsd)
            }
            identifiers += apfsVolumes.compactMap { $0["DeviceIdentifier"] as? String }
        }
        return identifiers
    }

    static func displayName(from plist: [String: Any], bsdName: String) -> String {
        for key in ["VolumeName", "MediaName"] {
            if let value = (plist[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return bsdName
    }

    public func getVolumeInfo(bsdName: String) -> DiskVolume? {
        do {
            let data = try diskutilOutput(["info", "-plist", bsdName])
            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                return nil
            }
            // `list external` also reports mounted .dmg/.sparseimage files; they are not drives to manage here.
            guard (plist["BusProtocol"] as? String) != "Disk Image" else { return nil }

            let name = Self.displayName(from: plist, bsdName: bsdName)
            let mountPoint = Self.mountPoint(from: plist)
            let fs = (plist["FilesystemType"] as? String) ?? (plist["FilesystemName"] as? String) ?? "Unknown"
            let totalSize = (plist["TotalSize"] as? Int64) ?? 0
            let freeSize = Self.freeSpace(from: plist)
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
                isMounted: isMounted,
                volumeUUID: plist["VolumeUUID"] as? String,
                wholeDisk: DiskEraseGuard.physicalDisks(of: plist).onlyElement
            )
        } catch {
            return nil
        }
    }

    /// diskutil reports `FreeSpace` as 0 for APFS volumes; their free space is the container's.
    static func freeSpace(from plist: [String: Any]) -> Int64 {
        if let free = plist["FreeSpace"] as? Int64, free > 0 { return free }
        return (plist["APFSContainerFree"] as? Int64) ?? 0
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

private extension Set {
    var onlyElement: Element? { count == 1 ? first : nil }
}
