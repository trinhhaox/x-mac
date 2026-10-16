import Cocoa
import SwiftUI

public struct AppVersionInfo: Equatable {
    public let version: String
    public let build: String

    public static let current = from(infoDictionary: Bundle.main.infoDictionary ?? [:])

    public static func from(infoDictionary: [String: Any]) -> AppVersionInfo {
        let version = infoDictionary["CFBundleShortVersionString"] as? String ?? L10n.text("Không xác định")
        let build = infoDictionary["CFBundleVersion"] as? String ?? ""
        return AppVersionInfo(version: version, build: build)
    }

    public var settingsDescription: String {
        guard !build.isEmpty, build != version else { return L10n.format("Phiên bản %@", version) }
        return L10n.format("Phiên bản %@ (Build %@)", version, build)
    }
}

public enum NavigationTab: String, CaseIterable, Identifiable {
    case overview = "Tổng quan"
    case systemMonitor = "Thông tin hệ thống"
    case downloads = "Tải xuống"
    case fileSearch = "Tìm tệp nhanh"
    case clipboard = "Lịch sử clipboard"
    case organizer = "Sắp xếp Downloads"
    case cutPaste = "Finder Cut & Paste"
    case diskNTFS = "Ổ đĩa & NTFS"
    case vietnameseIME = "Bộ gõ Tiếng Việt"
    case junkCleaner = "Dọn rác hệ thống"
    case appUninstaller = "Gỡ ứng dụng"
    case settings = "Cài đặt"
    
    public var id: String { rawValue }

    public var title: String { L10n.text(rawValue) }
    
    public var iconName: String {
        switch self {
        case .overview: return "gauge.medium"
        case .systemMonitor: return "waveform.path.ecg"
        case .downloads: return "arrow.down.circle.fill"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .clipboard: return "doc.on.clipboard"
        case .organizer: return "folder.badge.gearshape"
        case .cutPaste: return "scissors"
        case .diskNTFS: return "externaldrive.fill.badge.plus"
        case .vietnameseIME: return "character.bubble.fill"
        case .junkCleaner: return "sparkles"
        case .appUninstaller: return "trash.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public class AppState: ObservableObject {
    public static let shared = AppState()
    
    @Published public var selectedTab: NavigationTab = .overview
    @Published public var systemRAMUsage: String = L10n.text("Đang tải...")
    @Published public var diskFreeSpace: String = L10n.text("Đang tải...")
    
    private init() {
        updateSystemStats()
    }
    
    public func updateSystemStats() {
        DispatchQueue.global(qos: .utility).async {
            // Lấy dung lượng đĩa chính
            if let space = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity {
                let formatted = ByteCountFormatter.string(fromByteCount: Int64(space), countStyle: .file)
                DispatchQueue.main.async {
                    self.diskFreeSpace = L10n.format("%@ khả dụng", formatted)
                }
            }
            
            // Lấy thông số RAM
            var stats = vm_statistics64()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
            let hostPort = mach_host_self()
            let result = withUnsafeMutablePointer(to: &stats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
                }
            }
            
            if result == KERN_SUCCESS {
                let pageSize = vm_kernel_page_size
                let active = Int64(stats.active_count) * Int64(pageSize)
                let wired = Int64(stats.wire_count) * Int64(pageSize)
                let compressed = Int64(stats.compressor_page_count) * Int64(pageSize)
                let used = active + wired + compressed
                let formattedUsed = ByteCountFormatter.string(fromByteCount: used, countStyle: .memory)
                DispatchQueue.main.async {
                    self.systemRAMUsage = L10n.format("%@ đang dùng", formattedUsed)
                }
            }
        }
    }
}
