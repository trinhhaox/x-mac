import SwiftUI

public struct SettingsView: View {
    @ObservedObject var launchManager = LaunchAtLoginManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var vm = SettingsViewModel.shared
    
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
                            Text("Phiên bản 1.0.0 (Build 1)")
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
    }
}
