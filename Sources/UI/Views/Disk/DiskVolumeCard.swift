import SwiftUI

enum DiskAction {
    case mount
    case enableNTFSWrite
    case openInFinder
    case eject
    case verify
    case repair
    case health
    case rename
    case erase
    case toggleAutoWrite
}

struct DiskVolumeCard: View {
    let volume: DiskVolume
    let isBusy: Bool
    let isAutoWriteEnabled: Bool
    let onAction: (DiskAction) -> Void

    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: volume.isExternal ? "externaldrive.fill" : "internaldrive.fill")
                        .font(.system(size: 32))
                        .foregroundColor(accent)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(volume.name)
                                .font(.system(size: 16, weight: .bold))
                            fileSystemBadge
                            // WritableVolume is always false for an unmounted partition, so "read-only" would be wrong there.
                            StatusBadge(
                                title: !volume.isMounted ? "Chưa gắn kết" : (volume.isWritable ? "Đọc - Ghi" : "Chỉ đọc"),
                                isPositive: volume.isMounted && volume.isWritable
                            )
                        }

                        Text(L10n.format("Phân vùng: /dev/%@  •  Gắn kết: %@", volume.bsdName, volume.mountPoint ?? L10n.text("Chưa gắn kết")))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    actionButtons
                }
                capacity
            }
        }
    }

    private var accent: Color { volume.isNTFS ? XmacTheme.violet : XmacTheme.blue }

    private var fileSystemBadge: some View {
        Text(volume.isNTFS ? "NTFS" : volume.fileSystem)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(volume.isNTFS ? XmacTheme.violet.opacity(0.13) : Color.gray.opacity(0.15)))
            .foregroundColor(volume.isNTFS ? XmacTheme.violet : .secondary)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !volume.isMounted {
                Button("Gắn kết") { onAction(.mount) }
                    .buttonStyle(BrandPrimaryButtonStyle())
            }
            if volume.isNTFS && !volume.isWritable {
                Button("Bật Ghi NTFS") { onAction(.enableNTFSWrite) }
                    .buttonStyle(BrandPrimaryButtonStyle())
            }
            Button("Mở trong Finder") { onAction(.openInFinder) }
                .buttonStyle(BrandSecondaryButtonStyle())
                .disabled(!volume.isMounted)
            if volume.isExternal {
                Button { onAction(.eject) } label: { Image(systemName: "eject.fill") }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(!volume.isMounted)
                    .help(L10n.text("Ngắt kết nối an toàn"))
                    .accessibilityLabel(L10n.format("Ngắt kết nối %@ an toàn", volume.name))
            }
            toolsMenu
        }
        .disabled(isBusy)
    }

    private var toolsMenu: some View {
        Menu {
            Button(L10n.text("Kiểm tra lỗi")) { onAction(.verify) }
            Button(L10n.text("Sửa lỗi")) { onAction(.repair) }
            Divider()
            Button(L10n.text("Sức khoẻ & tốc độ...")) { onAction(.health) }
            Button(L10n.text("Đổi tên...")) { onAction(.rename) }
                .disabled(!volume.isMounted)
            if volume.isNTFS && volume.volumeUUID != nil {
                Divider()
                Button(isAutoWriteEnabled ? L10n.text("Tắt tự bật ghi NTFS") : L10n.text("Tự bật ghi NTFS khi cắm")) {
                    onAction(.toggleAutoWrite)
                }
            }
            if volume.isExternal {
                Divider()
                Button(L10n.text("Định dạng ổ...")) { onAction(.erase) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.text("Công cụ ổ đĩa"))
        .accessibilityLabel(L10n.format("Công cụ cho %@", volume.name))
    }

    @ViewBuilder
    private var capacity: some View {
        if volume.hasReliableCapacity {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accent)
                            .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, volume.usedPercentage))), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(L10n.format("Đã dùng: %@ (%lld%%)", volume.formattedUsedSize, Int64(volume.usedPercentage * 100)))
                    Spacer()
                    Text(L10n.format("Còn trống: %@ / Tổng: %@", volume.formattedFreeSize, volume.formattedTotalSize))
                        .fontWeight(.medium)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        } else if volume.totalSize > 0 {
            HStack {
                Text("Dung lượng chưa khả dụng khi phân vùng chưa được gắn kết")
                Spacer()
                Text(L10n.format("Tổng: %@", volume.formattedTotalSize))
                    .fontWeight(.medium)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }
}
