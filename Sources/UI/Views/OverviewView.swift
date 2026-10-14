import SwiftUI

public struct OverviewView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var cutPaste = FinderCutPasteManager.shared
    @ObservedObject var ime = InputHookManager.shared
    @ObservedObject var diskManager = DiskManager.shared
    @ObservedObject var cleaner = CleanerEngine.shared
    @ObservedObject var downloads = DownloadManager.shared
    @ObservedObject var permissions = PermissionsManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandPageHeader(
                    eyebrow: "System overview",
                    title: "Trung tâm điều khiển",
                    subtitle: "Theo dõi và điều khiển các tiện ích thiết yếu trên máy Mac của bạn."
                ) {
                    Button(action: refresh) {
                        Label("Làm mới", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                }

                heroPanel

                if !permissions.isAccessibilityGranted {
                    permissionBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    MetricCard(
                        title: "Finder Cut & Paste",
                        value: permissions.isAccessibilityGranted
                            ? (cutPaste.isEnabled ? "Đang hoạt động" : "Đang tắt")
                            : "Cần quyền Trợ năng",
                        subtitle: "\(cutPaste.cutFiles.count) mục đang chờ di chuyển",
                        iconName: "scissors",
                        accentColor: XmacTheme.blue
                    )

                    MetricCard(
                        title: "Bộ gõ Tiếng Việt",
                        value: permissions.isAccessibilityGranted
                            ? (ime.isVietnameseMode ? "Tiếng Việt · V" : "English · E")
                            : "Cần quyền Trợ năng",
                        subtitle: "Kiểu gõ \(ime.typingMethod.rawValue)",
                        iconName: "character.bubble.fill",
                        accentColor: XmacTheme.cyan
                    )

                    MetricCard(
                        title: "Ổ đĩa & NTFS",
                        value: "\(diskManager.volumes.count) ổ đĩa",
                        subtitle: "\(diskManager.volumes.filter { $0.isNTFS }.count) phân vùng NTFS",
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
                            subtitle: "Những tác vụ thường dùng, luôn trong một chạm."
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

                ModernCard {
                    BrandSectionTitle(
                        "Tiện ích đang quản lý",
                        subtitle: "Bật, tắt hoặc mở nhanh từng công cụ."
                    )

                    moduleRow(
                        icon: "doc.text.magnifyingglass",
                        title: "Tìm tệp nhanh",
                        subtitle: "Tên, nội dung, loại tệp và phạm vi bằng chỉ mục Spotlight"
                    ) {
                        Button("Mở tìm kiếm") { appState.selectedTab = .fileSearch }
                            .buttonStyle(BrandSecondaryButtonStyle())
                    }

                    Divider().opacity(0.55)

                    moduleRow(
                        icon: "arrow.down.circle.fill",
                        title: "Trung tâm tải xuống",
                        subtitle: downloads.activeCount > 0
                            ? "\(downloads.activeCount) tác vụ đang tải"
                            : "HTTP/HTTPS, tạm dừng và tiếp tục tải"
                    ) {
                        Button("Mở tải xuống") { appState.selectedTab = .downloads }
                            .buttonStyle(BrandSecondaryButtonStyle())
                    }

                    Divider().opacity(0.55)

                    moduleRow(
                        icon: "scissors",
                        title: "Finder Cut & Paste",
                        subtitle: "⌘X để cắt · ⌘V để di chuyển · ⌘Z để hoàn tác"
                    ) {
                        Toggle("", isOn: $cutPaste.isEnabled).labelsHidden()
                            .disabled(!permissions.isAccessibilityGranted)
                    }

                    Divider().opacity(0.55)

                    moduleRow(
                        icon: "character.bubble.fill",
                        title: "Bộ gõ Tiếng Việt",
                        subtitle: "Telex, VNI và gõ tắt trong một engine nhẹ"
                    ) {
                        Toggle("", isOn: $ime.isVietnameseMode).labelsHidden()
                            .disabled(!permissions.isAccessibilityGranted)
                    }

                    Divider().opacity(0.55)

                    moduleRow(
                        icon: "externaldrive.fill",
                        title: "Ổ đĩa & NTFS",
                        subtitle: "Theo dõi dung lượng, mount đọc-ghi và eject an toàn"
                    ) {
                        Button("Mở quản lý") { appState.selectedTab = .diskNTFS }
                            .buttonStyle(BrandSecondaryButtonStyle())
                    }
                }
            }
            .padding(26)
        }
        .xmacPage()
    }

    private var heroPanel: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(XmacTheme.brandGradient)

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 230, height: 230)
                .offset(x: 52, y: -72)

            Circle()
                .fill(XmacTheme.cyan.opacity(0.14))
                .frame(width: 150, height: 150)
                .offset(x: -80, y: 85)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.green.opacity(0.8), radius: 5)
                        Text("XMAC ĐANG HOẠT ĐỘNG")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.3)
                            .foregroundColor(.white.opacity(0.78))
                    }

                    Text("Một bảng điều khiển.\nMọi công cụ cần thiết.")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Finder, bộ gõ, ổ đĩa và dọn dẹp — luôn sẵn sàng nhưng không làm gián đoạn công việc.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: 460, alignment: .leading)
                }

                Spacer()

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.24), radius: 20, y: 10)
            }
            .padding(24)
        }
        .frame(minHeight: 170)
        .shadow(color: XmacTheme.indigo.opacity(0.22), radius: 20, y: 10)
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
        .animation(.easeOut(duration: 0.24), value: permissions.isAccessibilityGranted)
    }

    private func quickAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrandSecondaryButtonStyle())
    }

    private func moduleRow<Accessory: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 13) {
            BrandIconTile(iconName: icon, color: XmacTheme.blue, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            accessory()
        }
    }

    private func refresh() {
        appState.updateSystemStats()
        diskManager.refreshVolumes()
        permissions.checkPermissions()
    }
}
