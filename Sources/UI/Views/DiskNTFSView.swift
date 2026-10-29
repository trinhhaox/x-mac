import SwiftUI

public struct DiskNTFSView: View {
    @ObservedObject var diskManager = DiskManager.shared
    @ObservedObject var vm = DiskNTFSViewModel.shared
    @ObservedObject var tools = DiskToolsController.shared
    @ObservedObject var automation = DiskAutomationSettings.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandPageHeader(
                    title: "Ổ đĩa & NTFS",
                    subtitle: "Theo dõi dung lượng, bật ghi NTFS và ngắt kết nối thiết bị an toàn."
                ) {
                    Button(action: {
                        diskManager.refreshVolumes()
                    }) {
                        Label("Quét lại ổ đĩa", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                }

                if let msg = vm.mountStatusMessage {
                    statusBanner(msg)
                }

                if diskManager.volumes.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 14) {
                        ForEach(diskManager.volumes) { volume in
                            DiskVolumeCard(
                                volume: volume,
                                isBusy: vm.isProcessing,
                                isAutoWriteEnabled: automation.isAutoWriteEnabled(for: volume)
                            ) { action in
                                tools.handle(action, for: volume)
                            }
                        }
                    }
                }

                ModernCard {
                    BrandSectionTitle("Tự động hoá", subtitle: "Xmac theo dõi ổ ngoài ngay cả khi cửa sổ đang đóng.")
                    BrandToggleRow(
                        "Thông báo khi cắm hoặc rút ổ",
                        subtitle: "Cảnh báo khi ổ bị rút lúc chưa ngắt kết nối an toàn.",
                        isOn: $automation.notifyOnPlugEvents
                    )
                    Text("Bật \"Tự bật ghi NTFS khi cắm\" cho từng ổ NTFS trong menu ⋯ của thẻ ổ đĩa.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                ModernCard {
                    BrandSectionTitle("Lưu ý khi dùng NTFS", subtitle: "Ba nguyên tắc để bảo vệ dữ liệu trên ổ ngoài.")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("• macOS mặc định chỉ đọc ổ đĩa NTFS được định dạng từ Windows.")
                        Text("• Bật Ghi NTFS sẽ gắn kết lại phân vùng ở chế độ đọc và ghi.")
                        Text("• Luôn ngắt kết nối an toàn trước khi rút cáp để bảo vệ dữ liệu.")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
            }
            .padding(26)
        }
        .xmacPage()
        .sheet(item: $tools.activeSheet) { sheet in
            switch sheet {
            case .health(let volume): DiskHealthSheet(volume: volume)
            case .rename(let volume): DiskRenameSheet(volume: volume)
            case .erase(let volume): DiskEraseSheet(volume: volume)
            }
        }
    }

    private func statusBanner(_ msg: String) -> some View {
        HStack {
            if vm.isProcessing {
                ProgressView().controlSize(.small).frame(width: 34)
            } else {
                BrandIconTile(iconName: "info.circle.fill", color: XmacTheme.blue, size: 34)
            }
            Text(msg)
                .font(.system(size: 12))
                .textSelection(.enabled)
            Spacer()
            Button("Đóng") {
                vm.mountStatusMessage = nil
            }
            .buttonStyle(.link)
            .disabled(vm.isProcessing)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(XmacTheme.blue.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(XmacTheme.blue.opacity(0.16), lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var emptyState: some View {
        ModernCard {
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.questionmark")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("Chưa phát hiện ổ cứng ngoại vi")
                    .font(.system(size: 15, weight: .semibold))
                Text("Kết nối USB hoặc ổ cứng ngoài để Xmac hiển thị tại đây.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}
