import SwiftUI

public struct SettingsView: View {
    @ObservedObject var launchManager = LaunchAtLoginManager.shared
    @ObservedObject var dockIcon = DockIconManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var vm = SettingsViewModel.shared
    @ObservedObject private var downloads = DownloadEnvironment.shared
    @ObservedObject private var updates = AppUpdateManager.shared
    @ObservedObject private var launcher = QuickLauncher.shared
    @ObservedObject private var localization = LocalizationManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandPageHeader(
                    title: "Cài đặt Xmac",
                    subtitle: "Quản lý khởi động, phản hồi và quyền hệ thống."
                ) {
                    EmptyView()
                }
                
                // General Settings Card
                ModernCard {
                    BrandSectionTitle("Ngôn ngữ giao diện", subtitle: "Chọn ngôn ngữ hiển thị cho toàn bộ Xmac.")
                    Picker(L10n.text("Ngôn ngữ giao diện"), selection: $localization.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(L10n.text("Ngôn ngữ giao diện"))
                    Text(L10n.text("Thay đổi được áp dụng ngay cho cửa sổ chính, Menu Bar và bảng mở nhanh."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ModernCard {
                    BrandSectionTitle("Cài đặt chung", subtitle: "Các hành vi áp dụng trên toàn ứng dụng.")
                    
                    VStack(spacing: 12) {
                        BrandToggleRow(
                            "Khởi động cùng macOS",
                            subtitle: "Tự động mở Xmac khi bạn đăng nhập vào máy tính.",
                            isOn: Binding(
                                get: { launchManager.isEnabled },
                                set: { launchManager.setEnabled($0) }
                            ))
                        
                        Divider()

                        BrandToggleRow(
                            "Hiện biểu tượng trên Dock",
                            subtitle: "Tắt để Xmac chỉ chạy trên thanh menu, không chiếm chỗ trên Dock.",
                            isOn: $dockIcon.showsDockIcon
                        )

                        Divider()
                        
                        BrandToggleRow(
                            "Hiệu ứng âm thanh tương tác",
                            subtitle: "Phát âm thanh nhẹ khi cắt, dán file, dọn rác hoặc cắm/rút ổ cứng.",
                            isOn: $vm.enableSoundEffects
                        )
                    }
                }
                
                ModernCard {
                    BrandSectionTitle("Mở nhanh", subtitle: "Tìm lệnh, ứng dụng và tệp từ bất kỳ ứng dụng nào.")
                    HStack(spacing: 12) {
                        Picker(L10n.text("Phím tắt"), selection: Binding(get: { launcher.shortcut }, set: { launcher.setShortcut($0) })) {
                            ForEach(LauncherShortcut.allCases) { choice in Text(choice.title).tag(choice) }
                        }
                        Spacer()
                        Button(L10n.text("Mở bảng lệnh")) { launcher.show() }
                            .buttonStyle(BrandSecondaryButtonStyle())
                    }
                    Text(launcher.shortcutMessage).font(.caption).foregroundColor(.secondary)
                    Text(L10n.text("Nhấp trái biểu tượng Menu Bar để xem trạng thái; nhấp phải để mở menu đầy đủ."))
                        .font(.caption).foregroundColor(.secondary)
                }

                ModernCard {
                    BrandSectionTitle("Tải xuống", subtitle: "Quản lý nguồn điện và kết nối khi tải tệp.")
                    BrandToggleRow(
                        "Giữ máy thức khi đang tải",
                        subtitle: "Màn hình vẫn có thể tắt; chế độ ngủ tự khôi phục khi tải xong.",
                        isOn: $downloads.keepAwake
                    )
                    Divider().opacity(0.55)
                    BrandToggleRow(
                        "Chờ kết nối không giới hạn dữ liệu",
                        subtitle: downloads.online
                            ? (downloads.metered ? "Mạng hiện tại đang hạn chế dữ liệu." : "Mạng hiện tại sẵn sàng tải.")
                            : "Đang ngoại tuyến; tác vụ sẽ tự chờ kết nối.",
                        isOn: $downloads.avoidMetered
                    )
                }

                ModernCard {
                    BrandSectionTitle("Cập nhật ứng dụng", subtitle: "Bản phát hành chính thức từ GitHub của Xmac.")
                    BrandToggleRow(
                        "Tự kiểm tra bản mới mỗi ngày",
                        subtitle: "Thông báo khi có phiên bản Xmac mới.",
                        isOn: $updates.automaticChecks
                    )
                    Divider().opacity(0.55)
                    HStack(spacing: 8) {
                        Image(systemName: updates.busy ? "arrow.triangle.2.circlepath" : "info.circle")
                            .foregroundColor(XmacTheme.blue)
                        Text(L10n.text(updates.message)).font(.system(size: 12)).textSelection(.enabled)
                        Spacer()
                        if updates.busy { ProgressView().controlSize(.small) }
                    }
                    if let progress = updates.downloadProgress {
                        ProgressView(value: progress)
                    }
                    if let release = updates.release {
                        Text(release.body ?? L10n.format("Bản cập nhật Xmac %@", release.version))
                            .font(.caption).lineLimit(10).textSelection(.enabled)
                        Link(L10n.text("Xem đầy đủ ghi chú phát hành"), destination: release.html_url)
                        Button(L10n.format("Tải và cài Xmac %@…", release.version)) { updates.confirmInstallation = true }
                            .buttonStyle(BrandPrimaryButtonStyle())
                            .disabled(updates.busy || release.installer == nil)
                    }
                    Button(L10n.text("Kiểm tra cập nhật")) { Task { await updates.check() } }
                        .buttonStyle(BrandSecondaryButtonStyle())
                        .disabled(updates.busy)
                    Text(L10n.text("Xmac xác thực bộ cài và giữ bản cũ để bạn có thể khôi phục thủ công khi cần."))
                        .font(.caption).foregroundColor(.secondary)
                }

                // Permissions Card
                ModernCard {
                    BrandSectionTitle("Quyền hệ thống", subtitle: "Xmac chỉ yêu cầu quyền cho những tính năng bạn sử dụng.")
                    
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.text("Trợ năng (Accessibility)"))
                                    .font(.system(size: 13, weight: .medium))
                                Text(L10n.text("Bắt buộc để ⌘X/⌘V trong Finder và Bộ gõ tiếng Việt hoạt động."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            StatusBadge(
                                title: permissions.isAccessibilityGranted ? "Đã cấp quyền" : "Chưa cấp quyền",
                                isPositive: permissions.isAccessibilityGranted
                            )
                            Button(L10n.text("Mở Cài đặt")) {
                                permissions.openAccessibilitySettings()
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.text("Truy cập ổ đĩa đầy đủ (Full Disk Access)"))
                                    .font(.system(size: 13, weight: .medium))
                                Text(L10n.text("Cho phép dọn dẹp bộ nhớ đệm sâu và quét file phụ trợ của ứng dụng."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            StatusBadge(
                                title: permissions.isFullDiskAccessGranted ? "Đã cấp quyền" : "Khuyên dùng",
                                isPositive: permissions.isFullDiskAccessGranted
                            )
                            Button(L10n.text("Mở Cài đặt")) {
                                permissions.openFullDiskAccessSettings()
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.text("Tự động hoá Finder (Automation)"))
                                    .font(.system(size: 13, weight: .medium))
                                Text(L10n.text("Cho phép Xmac giao tiếp với Finder để lấy danh sách file đang chọn."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(L10n.text("Mở Cài đặt")) {
                                permissions.openAutomationSettings()
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        }
                    }
                }
                
                // About App Card
                ModernCard {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 58, height: 58)
                            .shadow(color: XmacTheme.blue.opacity(0.22), radius: 10, y: 5)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Xmac")
                                .font(.system(size: 16, weight: .bold))
                            Text(AppVersionInfo.current.settingsDescription)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(L10n.text("Một bảng điều khiển cho những tiện ích macOS thiết yếu."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding(26)
        }
        .xmacPage()
        .alert("Cài đặt bản cập nhật?", isPresented: $updates.confirmInstallation) {
            Button("Hủy", role: .cancel) {}
            Button("Cài đặt và mở lại") { Task { await updates.install() } }
        } message: {
            Text("Xmac sẽ tải bộ cài chính thức, kiểm tra tính toàn vẹn và mở lại ứng dụng. Hãy hoàn tất tác vụ đang làm trước khi cập nhật.")
        }
    }
}
