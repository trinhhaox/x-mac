import Foundation

/// File systems Xmac offers when erasing an external drive.
public enum DiskFormat: String, CaseIterable, Identifiable {
    case exFAT
    case apfs
    case fat32
    case macExtended

    public var id: String { rawValue }

    /// Maps diskutil's `FilesystemType` to a format, so renames get the same name rules as erases.
    public init?(fileSystem: String) {
        switch fileSystem.lowercased() {
        case "exfat": self = .exFAT
        case "apfs": self = .apfs
        case "msdos": self = .fat32
        case "hfs": self = .macExtended
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .exFAT: return "ExFAT"
        case .apfs: return "APFS"
        case .fat32: return "FAT32"
        case .macExtended: return "Mac OS Extended (Journaled)"
        }
    }

    public var hint: String {
        switch self {
        case .exFAT: return "Dùng chung macOS và Windows, hỗ trợ tệp lớn hơn 4 GB."
        case .apfs: return "Tốt nhất cho SSD chỉ dùng với Mac."
        case .fat32: return "Tương thích rộng (TV, máy ảnh) nhưng giới hạn tệp 4 GB."
        case .macExtended: return "Cho ổ cứng HDD hoặc Mac đời cũ."
        }
    }

    /// The personality name `diskutil eraseVolume/eraseDisk` expects.
    var diskutilName: String {
        switch self {
        case .exFAT: return "ExFAT"
        case .apfs: return "APFS"
        case .fat32: return "FAT32"
        case .macExtended: return "JHFS+"
        }
    }

    /// FAT32 media is read by more devices when partitioned MBR; everything else uses GPT.
    var partitionScheme: String { self == .fat32 ? "MBR" : "GPT" }

    var maxNameLength: Int {
        switch self {
        case .fat32: return 11
        case .exFAT: return 15
        case .apfs, .macExtended: return 255
        }
    }

    /// FAT volume labels are stored upper-case; normalise up front so the user sees the real result.
    public func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return self == .fat32 ? trimmed.uppercased() : trimmed
    }

    /// Nil when `name` is usable for this format, otherwise a message explaining why not.
    public func nameProblem(_ name: String) -> String? {
        let name = normalizedName(name)
        if name.isEmpty { return L10n.text("Tên ổ không được để trống.") }
        if name.count > maxNameLength {
            return L10n.format("Tên ổ %@ tối đa %lld ký tự.", title, Int64(maxNameLength))
        }
        if name.contains(":") || name.contains("/") { return L10n.text("Tên ổ không được chứa dấu : hoặc /.") }
        if self == .fat32, name.unicodeScalars.contains(where: { !$0.isASCII || "\"*+,.;<=>?[\\]|".unicodeScalars.contains($0) }) {
            return L10n.text("FAT32 chỉ nhận chữ không dấu, số và một số ký hiệu đơn giản.")
        }
        return nil
    }
}

/// Whether Xmac may erase a whole device or one partition.
public enum DiskEraseScope: String, CaseIterable, Identifiable {
    case volume
    case wholeDisk

    public var id: String { rawValue }
}

enum DiskEraseGuard {
    /// Destructive operations are restricted to external, non-virtual devices that share no
    /// physical drive with the running system (which may itself boot from an external drive).
    static func isAllowed(targetInfo: [String: Any], bootInfo: [String: Any]?) -> Bool {
        guard (targetInfo["Internal"] as? Bool) == false,
              (targetInfo["BusProtocol"] as? String) != "Disk Image",
              (targetInfo["MountPoint"] as? String) != "/",
              let bootInfo else { return false }
        let target = physicalDisks(of: targetInfo)
        let boot = physicalDisks(of: bootInfo)
        return !target.isEmpty && !boot.isEmpty && target.isDisjoint(with: boot)
    }

    /// The physical drives behind a volume. APFS volumes live on a synthesized container whose
    /// `ParentWholeDisk` is the container itself, so follow its physical stores instead.
    static func physicalDisks(of info: [String: Any]) -> Set<String> {
        let stores = ((info["APFSPhysicalStores"] as? [[String: Any]]) ?? [])
            .compactMap { $0["APFSPhysicalStore"] as? String }
        let devices = stores.isEmpty
            ? [(info["ParentWholeDisk"] as? String) ?? (info["DeviceIdentifier"] as? String)].compactMap { $0 }
            : stores
        return Set(devices.compactMap(wholeDisk(of:)))
    }

    /// "disk4s2" -> "disk4"; nil for anything that is not a BSD device name.
    static func wholeDisk(of device: String) -> String? {
        guard BSDDeviceName.isValid(device) else { return nil }
        return device.range(of: #"^disk[0-9]+"#, options: .regularExpression).map { String(device[$0]) }
    }

    /// BSD names are reassigned when drives are swapped, so confirm the device still holds the
    /// volume the user confirmed before touching it.
    static func isSameVolume(info: [String: Any], as volume: DiskVolume) -> Bool {
        if let uuid = volume.volumeUUID {
            return (info["VolumeUUID"] as? String) == uuid
        }
        return DiskManager.displayName(from: info, bsdName: volume.bsdName) == volume.name
            && (info["TotalSize"] as? Int64) == volume.totalSize
    }
}
