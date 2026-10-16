import SwiftUI

public struct DiskNTFSView: View {
    @ObservedObject var diskManager = DiskManager.shared
    @ObservedObject var vm = DiskNTFSViewModel.shared
    
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
                
                // Banner thông báo nếu có
                if let msg = vm.mountStatusMessage {
                    HStack {
                        BrandIconTile(iconName: "info.circle.fill", color: XmacTheme.blue, size: 34)
                        Text(msg)
                            .font(.system(size: 12))
                        Spacer()
                        Button("Đóng") {
                            vm.mountStatusMessage = nil
                        }
                        .buttonStyle(.link)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(XmacTheme.blue.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(XmacTheme.blue.opacity(0.16), lineWidth: 1))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Danh sách ổ đĩa
                if diskManager.volumes.isEmpty {
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
                } else {
                    VStack(spacing: 14) {
                        ForEach(diskManager.volumes) { volume in
                            DiskVolumeCard(volume: volume, onMountRW: {
                                mountVolume(volume)
                            }, onEject: {
                                ejectVolume(volume)
                            }, onOpen: {
                                NTFSMountHelper.shared.openInFinder(volume: volume)
                            })
                        }
                    }
                }
                
                // NTFS Tips & Guide Card
                ModernCard {
                    BrandSectionTitle("Lưu ý khi dùng NTFS", subtitle: "Ba nguyên tắc để bảo vệ dữ liệu trên ổ ngoài.")
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• macOS mặc định chỉ đọc ổ đĩa NTFS được định dạng từ Windows.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("• Bật Ghi NTFS sẽ gắn kết lại phân vùng ở chế độ đọc và ghi.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("• Luôn ngắt kết nối an toàn trước khi rút cáp để bảo vệ dữ liệu.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(26)
        }
        .xmacPage()
    }
    
    private func mountVolume(_ volume: DiskVolume) {
        vm.isProcessing = true
        vm.mountStatusMessage = L10n.format("Đang kích hoạt chế độ ghi NTFS cho %@...", volume.name)
        NTFSMountHelper.shared.mountNTFSReadWrite(volume: volume) { result in
            self.vm.isProcessing = false
            switch result {
            case .success(let mountPath):
                self.vm.mountStatusMessage = L10n.format("Kích hoạt ghi NTFS thành công tại: %@", mountPath)
            case .requiresSudo(let cmd):
                self.vm.mountStatusMessage = L10n.format("Cần quyền administrator: %@", cmd)
            case .failure(let err):
                self.vm.mountStatusMessage = L10n.format("Lỗi kích hoạt NTFS: %@", err)
            case .helperMissing(let message):
                self.vm.mountStatusMessage = message
            }
        }
    }
    
    private func ejectVolume(_ volume: DiskVolume) {
        vm.isProcessing = true
        vm.mountStatusMessage = L10n.format("Đang ngắt kết nối an toàn cho %@...", volume.name)
        NTFSMountHelper.shared.ejectVolume(volume: volume) { success in
            self.vm.isProcessing = false
            if success {
                self.vm.mountStatusMessage = L10n.format("Đã ngắt kết nối an toàn cho %@. Bạn có thể rút ổ đĩa.", volume.name)
            } else {
                self.vm.mountStatusMessage = "Không thể ngắt kết nối ổ đĩa. Có thể tệp tin đang được sử dụng."
            }
        }
    }
}

struct DiskVolumeCard: View {
    let volume: DiskVolume
    let onMountRW: () -> Void
    let onEject: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: volume.isExternal ? "externaldrive.fill" : "internaldrive.fill")
                        .font(.system(size: 32))
                        .foregroundColor(volume.isNTFS ? XmacTheme.violet : XmacTheme.blue)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill((volume.isNTFS ? XmacTheme.violet : XmacTheme.blue).opacity(0.12)))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(volume.name)
                                .font(.system(size: 16, weight: .bold))
                            
                            if volume.isNTFS {
                                Text("NTFS")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(XmacTheme.violet.opacity(0.13)))
                                    .foregroundColor(XmacTheme.violet)
                            } else {
                                Text(volume.fileSystem)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.gray.opacity(0.15)))
                                    .foregroundColor(.secondary)
                            }
                            
                            StatusBadge(
                                title: volume.isWritable ? "Đọc - Ghi" : "Chỉ đọc",
                                isPositive: volume.isWritable
                            )
                        }
                        
                        Text(L10n.format("Phân vùng: /dev/%@  •  Gắn kết: %@", volume.bsdName, volume.mountPoint ?? L10n.text("Chưa gắn kết")))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Thao tác nút
                    HStack(spacing: 8) {
                        if volume.isNTFS && !volume.isWritable {
                            Button("Bật Ghi NTFS", action: onMountRW)
                                .buttonStyle(BrandPrimaryButtonStyle())
                        }
                        
                        Button("Mở trong Finder", action: onOpen)
                            .buttonStyle(BrandSecondaryButtonStyle())
                            .disabled(!volume.isMounted)
                        
                        if volume.isExternal {
                            Button(action: onEject) {
                                Image(systemName: "eject.fill")
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                            .disabled(!volume.isMounted)
                            .help("Ngắt kết nối an toàn")
                            .accessibilityLabel(L10n.format("Ngắt kết nối %@ an toàn", volume.name))
                        }
                    }
                }
                
                // Dung lượng đĩa
                if volume.hasReliableCapacity {
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(volume.isNTFS ? XmacTheme.violet : XmacTheme.blue)
                                    .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, volume.usedPercentage))), height: 8)
                            }
                        }
                        .frame(height: 8)
                        
                        HStack {
                            Text(L10n.format("Đã dùng: %@ (%lld%%)", volume.formattedUsedSize, Int64(volume.usedPercentage * 100)))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(L10n.format("Còn trống: %@ / Tổng: %@", volume.formattedFreeSize, volume.formattedTotalSize))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                } else if volume.totalSize > 0 {
                    HStack {
                        Text("Dung lượng chưa khả dụng khi phân vùng chưa được gắn kết")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(L10n.format("Tổng: %@", volume.formattedTotalSize))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
