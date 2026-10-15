import SwiftUI

private final class MenuBarDashboardState: ObservableObject {
    @Published var ejectCandidate: DiskVolume?
    @Published var message = ""
    @Published var ejecting = false
}

struct MenuBarDashboard: View {
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var disks = DiskManager.shared
    @ObservedObject private var ime = InputHookManager.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    @ObservedObject private var environment = DownloadEnvironment.shared
    @StateObject private var state = MenuBarDashboardState()

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Xmac", systemImage: "square.grid.2x2.fill").font(.title3.bold())
                Spacer()
                Button("Mở nhanh…") { QuickLauncher.shared.show() }
            }
            HStack {
                Button(ime.isVietnameseMode ? "🇻🇳 Tiếng Việt" : "English") {
                    ime.toggleLanguage()
                }.disabled(!permissions.isAccessibilityGranted)
                Text(permissions.isAccessibilityGranted ? ime.typingMethod.rawValue : "Cần quyền Trợ năng")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Image(systemName: environment.online ? "wifi" : "wifi.slash")
                    .help(environment.online ? "Có kết nối mạng" : "Ngoại tuyến")
            }
            Divider()
            HStack {
                Text("Tải xuống").font(.headline)
                Spacer()
                Button("Xem tất cả") { open(.downloads) }
            }
            if currentDownloads.isEmpty {
                Text("Không có tác vụ đang chạy hoặc chờ mạng.").font(.caption).foregroundColor(.secondary)
            }
            ForEach(currentDownloads.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.fileName).lineLimit(1)
                        Spacer()
                        Button { downloads.pause(item.id) } label: { Image(systemName: "pause.fill") }
                            .help("Tạm dừng tải")
                    }
                    ProgressView(value: item.progress)
                    Text(item.status == .waitingForNetwork ? "Chờ kết nối" : "\(Int(item.progress * 100))%")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Toggle("Giữ máy thức khi tải", isOn: $environment.keepAwake).font(.caption)
            Divider()
            HStack {
                Text("Ổ đĩa ngoài").font(.headline)
                Spacer()
                Button("Quản lý") { open(.diskNTFS) }
            }
            if disks.volumes.filter({ $0.isExternal }).isEmpty {
                Text(disks.isLoading ? "Đang đọc ổ đĩa…" : "Chưa có ổ đĩa ngoài.").font(.caption).foregroundColor(.secondary)
            }
            ForEach(disks.volumes.filter { $0.isExternal }.prefix(4)) { disk in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(disk.name).lineLimit(1)
                        Text(disk.hasReliableCapacity ? "\(disk.formattedFreeSize) trống / \(disk.formattedTotalSize)" : "Chưa gắn kết")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button { NTFSMountHelper.shared.openInFinder(volume: disk) } label: { Image(systemName: "folder") }
                        .disabled(!disk.isMounted).help("Mở trong Finder")
                    Button { state.ejectCandidate = disk } label: { Image(systemName: "eject") }
                        .disabled(!disk.isMounted || state.ejecting).help("Ngắt kết nối an toàn")
                }
            }
            if !state.message.isEmpty { Text(state.message).font(.caption).foregroundColor(.secondary) }
            Divider()
            HStack {
                Button("Bảng điều khiển") { open(.overview) }
                Button("Tìm tệp") { open(.fileSearch) }
                Spacer()
                Button("Cài đặt") { open(.settings) }
            }
        }
        .padding(18)
        .frame(width: 380)
        }
        .frame(width: 380, height: min(560, (NSScreen.main?.visibleFrame.height ?? 700) - 80))
        .background(XmacTheme.cardBackground)
        .alert(item: $state.ejectCandidate) { volume in
            Alert(title: Text("Ngắt kết nối \(volume.name)?"),
                  message: Text("Hãy hoàn tất các thao tác đọc/ghi trên ổ đĩa trước khi tiếp tục."),
                  primaryButton: .destructive(Text("Ngắt kết nối")) {
                      state.ejecting = true
                      NTFSMountHelper.shared.ejectVolume(volume: volume) { success in
                          DispatchQueue.main.async {
                              state.ejecting = false
                              state.message = success ? "Đã ngắt kết nối \(volume.name)." : "Chưa thể ngắt kết nối; ổ có thể đang được sử dụng."
                              disks.refreshVolumes()
                          }
                      }
                  }, secondaryButton: .cancel(Text("Hủy")))
        }
    }

    private var currentDownloads: [ManagedDownload] {
        downloads.items.filter { $0.status == .downloading || $0.status == .waitingForNetwork }
    }

    private func open(_ tab: NavigationTab) {
        StatusBarController.shared.closeDashboard()
        AppState.shared.selectedTab = tab
        AppDelegate.shared.createMainWindow()
    }
}
