import Cocoa
import Combine
import Foundation
import UserNotifications

/// Manages automatic periodic background scans for duplicate files and notifies the user
/// when significant disk space can be reclaimed via APFS Copy-on-Write cloning.
@MainActor
public final class DeduplicatorScheduler: ObservableObject {
    public static let shared = DeduplicatorScheduler()

    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "Deduplicator.Schedule.Enabled")
            checkIfDue()
        }
    }

    @Published public var interval: DeduplicatorScheduleInterval {
        didSet {
            UserDefaults.standard.set(interval.rawValue, forKey: "Deduplicator.Schedule.Interval")
            checkIfDue()
        }
    }

    @Published public var minNotifyMB: Int {
        didSet {
            UserDefaults.standard.set(minNotifyMB, forKey: "Deduplicator.Schedule.MinNotifyMB")
        }
    }

    @Published public private(set) var lastScanDate: Date?
    @Published public private(set) var isBackgroundScanning: Bool = false
    @Published public private(set) var lastFoundReclaimableBytes: Int64 = 0

    private var timer: Timer?

    public init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "Deduplicator.Schedule.Enabled")
        let savedIntervalRaw = UserDefaults.standard.string(forKey: "Deduplicator.Schedule.Interval") ?? DeduplicatorScheduleInterval.weekly.rawValue
        self.interval = DeduplicatorScheduleInterval(rawValue: savedIntervalRaw) ?? .weekly
        let savedMinNotify = UserDefaults.standard.integer(forKey: "Deduplicator.Schedule.MinNotifyMB")
        self.minNotifyMB = savedMinNotify > 0 ? savedMinNotify : 500

        let lastTimestamp = UserDefaults.standard.double(forKey: "Deduplicator.Schedule.LastScan")
        if lastTimestamp > 0 {
            self.lastScanDate = Date(timeIntervalSince1970: lastTimestamp)
        }
    }

    public func start() {
        guard timer == nil else { return }
        // Check every 30 minutes if schedule is due
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkIfDue()
            }
        }
        checkIfDue()
    }

    public func checkIfDue() {
        guard isEnabled, !isBackgroundScanning else { return }
        let now = Date().timeIntervalSince1970
        let last = lastScanDate?.timeIntervalSince1970 ?? 0
        if now - last >= interval.timeInterval {
            runBackgroundScan()
        }
    }

    public func runBackgroundScan() {
        guard !isBackgroundScanning else { return }
        isBackgroundScanning = true

        let options = DeduplicatorScanOptions(
            rootPaths: [
                NSHomeDirectory() + "/Downloads",
                NSHomeDirectory() + "/Documents",
                NSHomeDirectory() + "/Desktop"
            ],
            minSizeBytes: 64 * 1024,
            skipPaths: [
                NSHomeDirectory() + "/Library",
                NSHomeDirectory() + "/.Trash"
            ],
            category: .all
        )

        let scanner = DeduplicatorScanner(options: options)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let report = scanner.scan()

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isBackgroundScanning = false
                let now = Date()
                self.lastScanDate = now
                self.lastFoundReclaimableBytes = report.totalReclaimableBytes
                UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "Deduplicator.Schedule.LastScan")

                let thresholdBytes = Int64(self.minNotifyMB) * 1024 * 1024
                if report.totalReclaimableBytes >= thresholdBytes {
                    self.postNotification(reclaimableBytes: report.totalReclaimableBytes, groupsCount: report.groups.count)
                }
            }
        }
    }

    private func postNotification(reclaimableBytes: Int64, groupsCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text("Phát hiện tệp trùng lặp APFS")
        content.body = L10n.format(
            "Xmac phát hiện %@ dung lượng có thể hợp nhất CoW an toàn mà không cần xóa tệp (%d nhóm).",
            ByteSize.string(reclaimableBytes, countStyle: .file),
            groupsCount
        )
        content.sound = .default
        content.userInfo = ["tab": NavigationTab.deduplicator.rawValue]

        let request = UNNotificationRequest(
            identifier: "xmac.deduplicator.scheduled_found",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("Lỗi gửi thông báo Deduplicator: \(error)")
            }
        }
    }
}
