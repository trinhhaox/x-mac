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
            BrandPageHeader(
                title: "Gỡ ứng dụng",
                subtitle: "Kiểm tra từng tệp liên quan trước khi chuyển ứng dụng vào Thùng rác."
            ) {
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(XmacTheme.blue)
                        TextField("Tìm ứng dụng...", text: $vm.searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 150)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(XmacTheme.cardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(XmacTheme.cardStroke, lineWidth: 1))

                    Button(action: { uninstaller.scanApps() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(uninstaller.isScanning)
                    .help("Quét lại danh sách ứng dụng")
                    .accessibilityLabel("Quét lại danh sách ứng dụng")
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            if let result = vm.uninstallResultText {
                HStack {
                    Image(systemName: vm.uninstallSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(vm.uninstallSucceeded ? .green : .orange)
                    Text(result)
                        .font(.system(size: 12))
                    Spacer()
                    Button("Đóng") {
                        vm.uninstallResultText = nil
                    }
                    .buttonStyle(.link)
                }
                .padding(10)
                .background((vm.uninstallSucceeded ? Color.green : Color.orange).opacity(0.1))
                .transition(.move(edge: .top).combined(with: .opacity))
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
                    .scrollContentBackground(.hidden)
                    .background(XmacTheme.workspaceBackground)
                    .frame(minWidth: 280, maxWidth: 360)
                    
                    // Chi tiết bên phải
                    if let app = vm.selectedApp {
                        AppDetailView(app: app, onUninstall: { configuredApp in
                            vm.selectedApp = configuredApp
                            vm.showConfirmAlert = true
                        })
                        .id(app.id)
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
                title: Text(L10n.format("Xác nhận gỡ bỏ %@?", vm.selectedApp?.name ?? "")),
                message: Text("Ứng dụng và các file phụ trợ đã chọn sẽ được chuyển an toàn vào Thùng rác (Trash)."),
                primaryButton: .destructive(Text("Chuyển vào Thùng rác")) {
                    if let app = vm.selectedApp {
                        uninstaller.uninstallApp(app) { result in
                            self.vm.uninstallSucceeded = result.success
                            self.vm.uninstallResultText = result.success
                                ? L10n.format("Đã chuyển các mục đã chọn của %@ vào Thùng rác.", app.name)
                                : result.errorMessage ?? L10n.format("Không thể gỡ bỏ đầy đủ %@.", app.name)
                            self.vm.selectedApp = nil
                        }
                    }
                },
                secondaryButton: .cancel(Text("Huỷ"))
            )
        }
        .xmacPage()
    }
}

struct AppListItemRow: View {
    let app: InstalledAppItem
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconCache.shared.icon(forFile: app.bundlePath))
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

private final class AppDetailSelection: ObservableObject {
    @Published var app: InstalledAppItem

    init(app: InstalledAppItem) {
        self.app = app
    }
}

struct AppDetailView: View {
    @StateObject private var selection: AppDetailSelection
    let onUninstall: (InstalledAppItem) -> Void

    init(app: InstalledAppItem, onUninstall: @escaping (InstalledAppItem) -> Void) {
        _selection = StateObject(wrappedValue: AppDetailSelection(app: app))
        self.onUninstall = onUninstall
    }

    private var app: InstalledAppItem {
        selection.app
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header app info
                HStack(spacing: 16) {
                    Image(nsImage: AppIconCache.shared.icon(forFile: app.bundlePath))
                        .resizable()
                        .frame(width: 56, height: 56)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.system(size: 18, weight: .bold))
                        Text(app.bundleIdentifier)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(L10n.format("Tổng dung lượng: %@", app.formattedTotalSize))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(XmacTheme.blue)
                    }
                    
                    Spacer()
                    
                    if !app.isSystemApp {
                        Button(action: { onUninstall(app) }) {
                            Label("Gỡ các mục đã chọn", systemImage: "trash.fill")
                        }
                        .buttonStyle(BrandDestructiveButtonStyle())
                        .disabled(app.selectedSize == 0)
                    } else {
                        Text("Ứng dụng hệ thống")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 18).fill(XmacTheme.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(XmacTheme.cardStroke, lineWidth: 1))
                
                // Danh sách file phụ trợ
                Text(L10n.format("Tệp phụ trợ phát hiện được (%lld mục):", Int64(app.associatedFiles.count)))
                    .font(.system(size: 13, weight: .bold))
                
                VStack(spacing: 8) {
                    ForEach($selection.app.associatedFiles) { $file in
                        HStack {
                            Toggle(L10n.format("Chọn tệp %@", file.name), isOn: $file.isSelected)
                                .labelsHidden()

                            Image(systemName: iconForType(file.fileType))
                                .foregroundColor(XmacTheme.blue)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(file.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("(\(file.fileType))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(file.confidence.title)
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(
                                            file.confidence == .verified
                                                ? Color.green.opacity(0.12)
                                                : Color.orange.opacity(0.15)
                                        ))
                                        .foregroundColor(file.confidence == .verified ? .green : .orange)
                                }
                                Text(file.path)
                                    .font(.system(size: 11, design: .monospaced))
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
                        .background(RoundedRectangle(cornerRadius: 10).fill(XmacTheme.blue.opacity(0.035)))
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
