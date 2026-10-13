import SwiftUI

public struct OverviewView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var cutPaste = FinderCutPasteManager.shared
    @ObservedObject var ime = InputHookManager.shared
    @ObservedObject var diskManager = DiskManager.shared
    @ObservedObject var cleaner = CleanerEngine.shared
    @ObservedObject var permissions = PermissionsManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Xmac Control Center")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Bộ công cụ thiết yếu và tối ưu toàn diện cho máy Mac của bạn")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        appState.updateSystemStats()
                        diskManager.refreshVolumes()
                        permissions.checkPermissions()
                    }) {
                        Label("Làm mới", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                
                // Status Warning nếu thiếu quyền
                if !permissions.isAccessibilityGranted {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cần cấp quyền Accessibility")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Xmac cần quyền trợ năng để hỗ trợ tính năng ⌘X/⌘V trong Finder và bộ gõ tiếng Việt.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Cấp quyền ngay") {
                            permissions.requestAccessibility()
                            permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                }
                
                // Metric Cards Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    MetricCard(
                        title: "FINDER CUT & PASTE",
                        value: cutPaste.isEnabled ? "Đang bật" : "Đã tắt",
                        subtitle: "\(cutPaste.cutFiles.count) mục đang trong clipboard",
                        iconName: "scissors",
                        accentColor: .blue
                    )
                    
                    MetricCard(
                        title: "BỘ GÕ TIẾNG VIỆT",
                        value: ime.isVietnameseMode ? "Tiếng Việt (V)" : "Tiếng Anh (E)",
                        subtitle: "Kiểu gõ: \(ime.typingMethod.rawValue)",
                        iconName: "character.bubble.fill",
                        accentColor: .green
                    )
                    
                    MetricCard(
                        title: "QUẢN LÝ Ổ ĐĨA & NTFS",
                        value: "\(diskManager.volumes.count) Ổ đĩa",
                        subtitle: "\(diskManager.volumes.filter { $0.isNTFS }.count) phân vùng NTFS",
                        iconName: "externaldrive.fill.badge.plus",
                        accentColor: .indigo
                    )
                    
                    MetricCard(
                        title: "TÀI NGUYÊN HỆ THỐNG",
                        value: appState.systemRAMUsage,
                        subtitle: appState.diskFreeSpace,
                        iconName: "cpu",
                        accentColor: .purple
                    )
                }
                
                // Quick Actions Card
                ModernCard {
                    Text("Thao tác nhanh")
                        .font(.system(size: 15, weight: .bold))
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            cleaner.purgeMemory()
                            appState.updateSystemStats()
                        }) {
                            Label("Giải phóng RAM", systemImage: "bolt.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        
                        Button(action: {
                            appState.selectedTab = .junkCleaner
                            cleaner.startScan()
                        }) {
                            Label("Quét rác hệ thống", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        
                        Button(action: {
                            ime.toggleLanguage()
                        }) {
                            Label(ime.isVietnameseMode ? "Chuyển sang Tiếng Anh (E)" : "Chuyển sang Tiếng Việt (V)", systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }
                
                // Feature Modules List Preview
                ModernCard {
                    Text("Các module hoạt động")
                        .font(.system(size: 15, weight: .bold))
                    
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "scissors")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("True Cut & Paste cho macOS Finder")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Phím ⌘X cắt file, ⌘V dán di chuyển file, ⌘Z hoàn tác.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $cutPaste.isEnabled)
                                .labelsHidden()
                        }
                        Divider()
                        HStack {
                            Image(systemName: "character.bubble.fill")
                                .foregroundColor(.green)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bộ gõ Tiếng Việt thông minh Xmac")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Hỗ trợ Telex/VNI, gõ tắt macro, hoàn tác từ tiếng Anh.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $ime.isVietnameseMode)
                                .labelsHidden()
                        }
                        Divider()
                        HStack {
                            Image(systemName: "externaldrive.fill.badge.plus")
                                .foregroundColor(.indigo)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Đọc & Ghi ổ NTFS ngoại vi")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Mount ổ cứng Windows NTFS ở chế độ Đọc - Ghi toàn quyền, Safe Eject.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Quản lý ổ đĩa") {
                                appState.selectedTab = .diskNTFS
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
