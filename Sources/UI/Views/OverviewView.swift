import SwiftUI

public struct OverviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var appState = AppState.shared
    @ObservedObject var cutPaste = FinderCutPasteManager.shared
    @ObservedObject var diskManager = DiskManager.shared
    @ObservedObject var cleaner = CleanerEngine.shared
    @ObservedObject var downloads = DownloadManager.shared
    @ObservedObject var permissions = PermissionsManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandPageHeader(
                    title: "Tổng quan",
                    subtitle: "Trạng thái quan trọng và tác vụ thường dùng trên máy Mac."
                ) {
                    Button(action: refresh) {
                        Label(L10n.text("Làm mới"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                }

                if !permissions.isAccessibilityGranted {
                    permissionBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    MetricCard(
                        title: "Tải xuống",
                        value: downloads.activeCount > 0
                            ? L10n.format("%lld đang tải", Int64(downloads.activeCount))
                            : L10n.text("Không có tác vụ"),
                        subtitle: "Tác vụ đang chạy hoặc chờ kết nối",
                        iconName: "arrow.down.circle.fill",
                        accentColor: XmacTheme.blue
                    )

                    MetricCard(
                        title: "Finder Cut & Paste",
                        value: permissions.isAccessibilityGranted
                            ? L10n.text(cutPaste.isEnabled ? "Đang hoạt động" : "Đang tắt")
                            : L10n.text("Cần quyền Trợ năng"),
                        subtitle: L10n.format("%lld mục đang chờ di chuyển", Int64(cutPaste.cutFiles.count)),
                        iconName: "scissors",
                        accentColor: XmacTheme.cyan
                    )

                    MetricCard(
                        title: "Ổ đĩa & NTFS",
                        value: L10n.format("%lld ổ đĩa", Int64(diskManager.volumes.count)),
                        subtitle: L10n.format("%lld phân vùng NTFS", Int64(diskManager.volumes.filter { $0.isNTFS }.count)),
                        iconName: "externaldrive.fill",
                        accentColor: XmacTheme.indigo
                    )

                    MetricCard(
                        title: "Tài nguyên hệ thống",
                        value: appState.systemRAMUsage,
                        subtitle: appState.diskFreeSpace,
                        iconName: "cpu",
                        accentColor: XmacTheme.violet
                    )
                }

                ModernCard {
                    HStack(alignment: .center) {
                        BrandSectionTitle(
                            "Thao tác nhanh",
                            subtitle: "Mở nhanh các tác vụ thường dùng."
                        )
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        quickAction(
                            title: "Giải phóng RAM",
                            icon: "bolt.fill",
                            action: {
                                cleaner.purgeMemory { _ in appState.updateSystemStats() }
                            }
                        )
                        quickAction(
                            title: "Quét rác",
                            icon: "sparkles",
                            action: {
                                appState.selectedTab = .junkCleaner
                                cleaner.startScan()
                            }
                        )
                        quickAction(
                            title: "Tải xuống",
                            icon: "arrow.down.circle.fill",
                            action: { appState.selectedTab = .downloads }
                        )
                        quickAction(
                            title: "Tìm tệp",
                            icon: "doc.text.magnifyingglass",
                            action: { appState.selectedTab = .fileSearch }
                        )
                    }
                }

            }
            .padding(26)
        }
        .xmacPage()
    }

    private var permissionBanner: some View {
        HStack(spacing: 14) {
            BrandIconTile(iconName: "lock.trianglebadge.exclamationmark", color: .orange, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cần quyền Trợ năng")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("Cho phép Xmac hỗ trợ phím tắt Finder và bộ gõ Tiếng Việt trên toàn hệ thống.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Mở Quyền riêng tư") {
                permissions.requestAccessibility()
                permissions.openAccessibilitySettings()
            }
            .buttonStyle(BrandPrimaryButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: permissions.isAccessibilityGranted)
    }

    private func quickAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(L10n.text(title))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrandSecondaryButtonStyle())
    }

    private func refresh() {
        appState.updateSystemStats()
        diskManager.refreshVolumes()
        permissions.checkPermissions()
    }
}
