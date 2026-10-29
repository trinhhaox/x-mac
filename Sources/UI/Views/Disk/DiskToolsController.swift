import SwiftUI

enum DiskSheet: Identifiable {
    case health(DiskVolume)
    case rename(DiskVolume)
    case erase(DiskVolume)

    var id: String {
        switch self {
        case .health(let volume): return "health-\(volume.bsdName)"
        case .rename(let volume): return "rename-\(volume.bsdName)"
        case .erase(let volume): return "erase-\(volume.bsdName)"
        }
    }
}

/// Runs card actions and reports progress through the page's status banner.
final class DiskToolsController: ObservableObject {
    static let shared = DiskToolsController()

    @Published var activeSheet: DiskSheet?

    private let status = DiskNTFSViewModel.shared
    private let settings = DiskAutomationSettings.shared

    private init() {}

    func handle(_ action: DiskAction, for volume: DiskVolume) {
        switch action {
        case .mount:
            run(L10n.format("Đang gắn kết %@...", volume.name)) {
                let report = await DiskOperations.mount(volume)
                return report.succeeded
                    ? L10n.format("Đã gắn kết %@.", volume.name)
                    : L10n.format("Không thể gắn kết %@. macOS có thể đang kiểm tra ổ, hãy thử lại sau ít phút.", volume.name)
            }
        case .verify:
            run(L10n.format("Đang kiểm tra lỗi %@. Ổ lớn có thể mất vài phút...", volume.name)) {
                let report = await DiskOperations.verify(volume)
                return report.succeeded
                    ? L10n.format("%@ không có lỗi. %@", volume.name, report.summary)
                    : L10n.format("Phát hiện vấn đề trên %@: %@. Hãy chạy Sửa lỗi.", volume.name, report.summary)
            }
        case .repair:
            run(L10n.format("Đang sửa lỗi %@. Đừng rút ổ trong lúc này...", volume.name)) {
                let report = await DiskOperations.repair(volume)
                return report.succeeded
                    ? L10n.format("Đã sửa xong %@. %@", volume.name, report.summary)
                    : L10n.format("Không sửa được %@: %@. Hãy sao lưu dữ liệu và cân nhắc định dạng lại.", volume.name, report.summary)
            }
        case .enableNTFSWrite:
            enableNTFSWrite(volume)
        case .openInFinder:
            NTFSMountHelper.shared.openInFinder(volume: volume)
        case .eject:
            eject(volume)
        case .toggleAutoWrite:
            let enable = !settings.isAutoWriteEnabled(for: volume)
            settings.setAutoWrite(enable, for: volume)
            status.mountStatusMessage = enable
                ? L10n.format("Xmac sẽ tự bật ghi NTFS mỗi khi cắm %@.", volume.name)
                : L10n.format("Đã tắt tự bật ghi NTFS cho %@.", volume.name)
        case .health:
            activeSheet = .health(volume)
        case .rename:
            activeSheet = .rename(volume)
        case .erase:
            activeSheet = .erase(volume)
        }
    }

    /// Shows `progress`, runs `work` off the main thread, then shows the message it returns.
    func run(_ progress: String, work: @escaping () async -> String) {
        status.isProcessing = true
        status.mountStatusMessage = progress
        Task {
            let message = await work()
            await MainActor.run {
                self.status.isProcessing = false
                self.status.mountStatusMessage = message
            }
        }
    }

    private func enableNTFSWrite(_ volume: DiskVolume) {
        status.isProcessing = true
        status.mountStatusMessage = L10n.format("Đang kích hoạt chế độ ghi NTFS cho %@...", volume.name)
        NTFSMountHelper.shared.mountNTFSReadWrite(volume: volume) { result in
            self.status.isProcessing = false
            switch result {
            case .success(let mountPath):
                self.status.mountStatusMessage = L10n.format("Kích hoạt ghi NTFS thành công tại: %@", mountPath)
            case .requiresSudo(let cmd):
                self.status.mountStatusMessage = L10n.format("Cần quyền administrator: %@", cmd)
            case .failure(let err):
                self.status.mountStatusMessage = L10n.format("Lỗi kích hoạt NTFS: %@", err)
            case .helperMissing(let message):
                self.status.mountStatusMessage = message
            }
        }
    }

    private func eject(_ volume: DiskVolume) {
        status.isProcessing = true
        status.mountStatusMessage = L10n.format("Đang ngắt kết nối an toàn cho %@...", volume.name)
        NTFSMountHelper.shared.ejectVolume(volume: volume) { success in
            self.status.isProcessing = false
            self.status.mountStatusMessage = success
                ? L10n.format("Đã ngắt kết nối an toàn cho %@. Bạn có thể rút ổ đĩa.", volume.name)
                : L10n.text("Không thể ngắt kết nối ổ đĩa. Có thể tệp tin đang được sử dụng.")
        }
    }
}
