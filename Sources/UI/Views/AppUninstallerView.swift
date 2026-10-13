import SwiftUI

public struct AppUninstallerView: View {
    @ObservedObject var uninstaller = AppUninstallerEngine.shared
    @ObservedObject var vm = AppUninstallerViewModel.shared
    
    public init() {}
    
    public var filteredApps: [InstalledAppItem] {
        if vm.searchText.isEmpty {
            return uninstaller.apps
        }
        return uninstaller.apps.filter {
            $0.name.localizedCaseInsensitiveContains(vm.searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(vm.searchText)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gỡ ứng dụng Triệt để")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Tìm và xoá toàn bộ file thừa, cache, preferences của ứng dụng khi gỡ cài đặt.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Ô tìm kiếm
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Tìm ứng dụng...", text: $vm.searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 160)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                
                Button(action: {
                    uninstaller.scanApps()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(uninstaller.isScanning)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)
            
            Divider()
            
            if let result = vm.uninstallResultText {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(result)
                        .font(.system(size: 12))
                    Spacer()
                    Button("Đóng") {
                        vm.uninstallResultText = nil
                    }
                    .buttonStyle(.link)
                }
                .padding(10)
                .background(Color.green.opacity(0.12))
            }
            
            // Content: Danh sách chia đôi (Master - Detail)
            if uninstaller.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Đang quét các ứng dụng và tệp phụ trợ liên quan...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // Danh sách bên trái
                    List(filteredApps, selection: $vm.selectedApp) { app in
                        AppListItemRow(app: app, isSelected: vm.selectedApp?.id == app.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.vm.selectedApp = app
                            }
                    }
                    .listStyle(.inset)
                    .frame(minWidth: 280, maxWidth: 360)
                    
                    // Chi tiết bên phải
                    if let app = vm.selectedApp {
                        AppDetailView(app: app, onUninstall: {
                            vm.showConfirmAlert = true
                        })
                        .frame(minWidth: 320)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Chọn một ứng dụng từ danh sách để xem chi tiết các tệp phụ trợ")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .onAppear {
            if uninstaller.apps.isEmpty {
                uninstaller.scanApps()
            }
        }
        .alert(isPresented: $vm.showConfirmAlert) {
            Alert(
                title: Text("Xác nhận gỡ bỏ \(vm.selectedApp?.name ?? "")?"),
                message: Text("Ứng dụng và các file phụ trợ đã chọn sẽ được chuyển an toàn vào Thùng rác (Trash)."),
                primaryButton: .destructive(Text("Gỡ bỏ triệt để")) {
                    if let app = vm.selectedApp {
                        uninstaller.uninstallApp(app) { success in
                            if success {
                                self.vm.uninstallResultText = "Đã chuyển \(app.name) và toàn bộ file thừa vào Thùng rác!"
                                self.vm.selectedApp = nil
                            }
                        }
                    }
                },
                secondaryButton: .cancel(Text("Huỷ"))
            )
        }
    }
}

struct AppListItemRow: View {
    let app: InstalledAppItem
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(app.version)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(app.formattedTotalSize)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct AppDetailView: View {
    let app: InstalledAppItem
    let onUninstall: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header app info
                HStack(spacing: 16) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                        .resizable()
                        .frame(width: 56, height: 56)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.system(size: 18, weight: .bold))
                        Text(app.bundleIdentifier)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("Tổng dung lượng: \(app.formattedTotalSize)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    if !app.isSystemApp {
                        Button(action: onUninstall) {
                            Label("Gỡ bỏ triệt để", systemImage: "trash.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Text("Ứng dụng hệ thống")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                
                // Danh sách file phụ trợ
                Text("Tệp phụ trợ phát hiện được (\(app.associatedFiles.count) mục):")
                    .font(.system(size: 13, weight: .bold))
                
                VStack(spacing: 8) {
                    ForEach(app.associatedFiles) { file in
                        HStack {
                            Image(systemName: iconForType(file.fileType))
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(file.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("(\(file.fileType))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Text(file.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                            
                            Text(file.formattedSize)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.02)))
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func iconForType(_ type: String) -> String {
        switch type {
        case "Application Bundle": return "app.fill"
        case "Application Support": return "folder.fill"
        case "Caches": return "cylinder.split.1x2.fill"
        case "Preferences": return "gearshape.fill"
        case "Saved State": return "clock.arrow.circlepath"
        default: return "doc.fill"
        }
    }
}
