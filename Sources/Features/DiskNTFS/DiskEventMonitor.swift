import Cocoa
import DiskArbitration
import UserNotifications

/// What a DiskArbitration description says about a disk, reduced to what the notifications need.
struct DiskEventSnapshot: Equatable {
    let bsdName: String
    let name: String
    let isUserVolume: Bool
    let wasMounted: Bool

    init(description: [String: Any]) {
        bsdName = (description[kDADiskDescriptionMediaBSDNameKey as String] as? String) ?? ""
        let volumeName = (description[kDADiskDescriptionVolumeNameKey as String] as? String) ?? ""
        name = volumeName.isEmpty ? bsdName : volumeName
        let isInternal = (description[kDADiskDescriptionDeviceInternalKey as String] as? Bool) ?? true
        let isVirtual = (description[kDADiskDescriptionDeviceProtocolKey as String] as? String) == "Disk Image"
        let hasFileSystem = description[kDADiskDescriptionVolumeKindKey as String] != nil
        let isEFI = volumeName == "EFI"
        isUserVolume = !isInternal && !isVirtual && hasFileSystem && !isEFI
        wasMounted = description[kDADiskDescriptionVolumePathKey as String] != nil
    }

    /// A clean eject unmounts first, so a volume that still has a mount path when its disk
    /// disappears was pulled out from under the file system.
    var isUnsafeRemoval: Bool { isUserVolume && wasMounted }
}

/// Watches drives coming and going: notifies the user and applies remembered NTFS write mode.
public final class DiskEventMonitor {
    public static let shared = DiskEventMonitor()

    /// DiskArbitration replays every existing disk on registration; those are not new arrivals.
    private static let launchGracePeriod: TimeInterval = 5

    private var session: DASession?
    private var startedAt = Date()
    private var autoWriteAttempted: Set<String> = []
    private let settings = DiskAutomationSettings.shared

    private init() {}

    public func start() {
        guard session == nil, let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        startedAt = Date()
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, { disk, context in
            guard let context else { return }
            Unmanaged<DiskEventMonitor>.fromOpaque(context).takeUnretainedValue().diskAppeared(disk)
        }, context)
        DARegisterDiskDisappearedCallback(session, nil, { disk, context in
            guard let context else { return }
            Unmanaged<DiskEventMonitor>.fromOpaque(context).takeUnretainedValue().diskDisappeared(disk)
        }, context)
        DASessionSetDispatchQueue(session, .main)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(volumeDidMount(_:)), name: NSWorkspace.didMountNotification, object: nil
        )
    }

    private func snapshot(of disk: DADisk) -> DiskEventSnapshot? {
        guard let description = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        return DiskEventSnapshot(description: description)
    }

    private func diskAppeared(_ disk: DADisk) {
        guard Date().timeIntervalSince(startedAt) > Self.launchGracePeriod,
              settings.notifyOnPlugEvents,
              let snapshot = snapshot(of: disk), snapshot.isUserVolume else { return }
        post(title: L10n.format("Đã kết nối ổ %@", snapshot.name), body: nil)
    }

    private func diskDisappeared(_ disk: DADisk) {
        guard let snapshot = snapshot(of: disk) else { return }
        autoWriteAttempted.remove(snapshot.bsdName)
        guard settings.notifyOnPlugEvents, snapshot.isUnsafeRemoval else { return }
        post(
            title: L10n.format("Ổ %@ bị rút khi chưa ngắt kết nối", snapshot.name),
            body: L10n.text("Dữ liệu đang ghi có thể bị hỏng. Hãy cắm lại và chạy Kiểm tra lỗi trong Xmac.")
        )
    }

    @objc private func volumeDidMount(_ notification: Notification) {
        guard !settings.autoWriteVolumeUUIDs.isEmpty,
              let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL,
              let session,
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let bsdPointer = DADiskGetBSDName(disk) else { return }
        let bsdName = String(cString: bsdPointer)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let volume = DiskManager.shared.getVolumeInfo(bsdName: bsdName) else { return }
            DispatchQueue.main.async { self.applyAutoWrite(to: volume) }
        }
    }

    private func applyAutoWrite(to volume: DiskVolume) {
        // One attempt per plug-in: a failed read-write mount falls back to read-only, which
        // fires didMount again and would otherwise loop.
        guard volume.isNTFS, !volume.isWritable, settings.isAutoWriteEnabled(for: volume),
              autoWriteAttempted.insert(volume.bsdName).inserted else { return }
        NTFSMountHelper.shared.mountNTFSReadWrite(volume: volume) { result in
            switch result {
            case .success:
                self.post(title: L10n.format("Đã tự bật ghi NTFS cho %@", volume.name), body: nil)
            case .failure(let message), .helperMissing(let message), .requiresSudo(let message):
                self.post(title: L10n.format("Không tự bật ghi NTFS được cho %@", volume.name), body: message)
            }
        }
    }

    private func post(title: String, body: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        content.userInfo = ["tab": NavigationTab.diskNTFS.rawValue]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Xmac disk notification failed: \(error)") }
        }
    }
}
