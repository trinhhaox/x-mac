import SwiftUI

public struct SettingsView: View {
    @ObservedObject var launchManager = LaunchAtLoginManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var vm = SettingsViewModel.shared
    @ObservedObject private var downloads = DownloadEnvironment.shared
    @ObservedObject private var updates = AppUpdateManager.shared
    @ObservedObject private var launcher = QuickLauncher.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandPageHeader(
                    eyebrow: "Preferences",
                    title: "Cài đặt Xmac",
                    subtitle: "Quản lý khởi động, phản hồi và quyền hệ thống."
                ) {
                    EmptyView()
                }
                
                // General Settings Card
                ModernCard {
                    BrandSectionTitle("Cài đặt chung", subtitle: "Các hành vi áp dụng trên toàn ứng dụng.")
                    
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Khởi động cùng macOS")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Tự động mở Xmac khi bạn đăng nhập vào máy tính.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { launchManager.isEnabled },
                                set: { launchManager.setEnabled($0) }
                            ))
                            .labelsHidden()
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hiệu ứng âm thanh tương tác")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Phát âm thanh nhẹ khi cắt, dán file, dọn rác hoặc cắm/rút ổ cứng.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $vm.enableSoundEffects)
                                .labelsHidden()
                        }
                    }
                }
                
                ModernCard {
                    BrandSectionTitle("Mở nhanh", subtitle: "Tìm lệnh, ứng dụng và tệp từ bất kỳ ứng dụng nào.")
                    Picker("Phím tắt", selection: Binding(get: { launcher.shortcut }, set: { launcher.setShortcut($0) })) {
                        ForEach(LauncherShortcut.allCases) { choice in Text(choice.title).tag(choice) }
                    }
                    Text(launcher.shortcutMessage).font(.caption).foregroundColor(.secondary)
                    Button("Mở bảng lệnh") { launcher.show() }
                    Text("Nhấp trái biểu tượng Menu Bar để xem trạng thái; nhấp phải để mở menu đầy đủ.")
                        .font(.caption).foregroundColor(.secondary)
                }

                ModernCard {
                    BrandSectionTitle("Tải xuống", subtitle: "Quản lý nguồn điện và kết nối khi tải tệp.")
                    Toggle("Giữ máy thức khi đang tải", isOn: $downloads.keepAwake)
                    Text("Màn hình vẫn có thể tắt. Xmac trả chế độ ngủ bình thường khi tải xong hoặc tạm dừng.")
                        .font(.caption).foregroundColor(.secondary)
                    Toggle("Chờ Wi-Fi không tính phí hoặc mạng không hạn chế", isOn: $downloads.avoidMetered)
                    Text(downloads.online ? (downloads.metered ? "Mạng hiện tại tính phí hoặc hạn chế dữ liệu." : "Đã kết nối mạng.") : "Đang ngoại tuyến. Tác vụ sẽ chờ kết nối.")
                        .font(.caption).foregroundColor(.secondary)
                }

                ModernCard {
                    BrandSectionTitle("Cập nhật ứng dụng", subtitle: "Bản phát hành chính thức từ GitHub của Xmac.")
                    Toggle("Tự kiểm tra bản mới mỗi ngày", isOn: $updates.automaticChecks)
                    Text(updates.message).font(.system(size: 12)).textSelection(.enabled)
                    if let progress = updates.downloadProgress {
                        ProgressView(value: progress)
                    } else if updates.busy { ProgressView().controlSize(.small) }
                    if let release = updates.release {
                        Text(release.body ?? "Bản cập nhật Xmac \(release.version)")
                            .font(.caption).lineLimit(10).textSelection(.enabled)
                        Link("Xem đầy đủ ghi chú phát hành", destination: release.html_url)
                        Button("Tải và cài Xmac \(release.version)…") { updates.confirmInstallation = true }
                            .disabled(updates.busy || release.installer == nil)
                    }
                    Button("Kiểm tra cập nhật") { Task { await updates.check() } }
                        .disabled(updates.busy)
                    Text("Bộ cài được đối chiếu SHA-256 từ GitHub và kiểm tra chữ ký app. Bản cũ được giữ trong Applications để khôi phục thủ công; cập nhật có thể cần bật lại quyền Trợ năng.")
                        .font(.caption).foregroundColor(.secondary)
                }

                // Permissions Card
                ModernCard {
                    BrandSectionTitle("Quyền hệ thống", subtitle: "Xmac chỉ yêu cầu quyền cho những tính năng bạn sử dụng.")
                    
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Trợ năng (Accessibility)")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Bắt buộc để ⌘X/⌘V trong Finder và Bộ gõ tiếng Việt hoạt động.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            StatusBadge(
                                title: permissions.isAccessibilityGranted ? "Đã cấp quyền" : "Chưa cấp quyền",
                                isPositive: permissions.isAccessibilityGranted
                            )
                            Button("Mở Cài đặt") {
                                permissions.openAccessibilitySettings()
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Truy cập ổ đĩa đầy đủ (Full Disk Access)")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Cho phép dọn dẹp bộ nhớ đệm sâu và quét file phụ trợ của ứng dụng.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            StatusBadge(
                                title: permissions.isFullDiskAccessGranted ? "Đã cấp quyền" : "Khuyên dùng",
                                isPositive: permissions.isFullDiskAccessGranted
                            )
                            Button("Mở Cài đặt") {
                                permissions.openFullDiskAccessSettings()
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tự động hoá Finder (Automation)")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Cho phép Xmac giao tiếp với Finder để lấy danh sách file đang chọn.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Mở Cài đặt") {
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
                            Text("Một bảng điều khiển cho những tiện ích macOS thiết yếu.")
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
