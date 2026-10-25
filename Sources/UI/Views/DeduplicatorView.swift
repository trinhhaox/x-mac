import SwiftUI

public struct DeduplicatorView: View {
    @ObservedObject var vm = DeduplicatorViewModel.shared
    @State private var expandedGroupIDs = Set<String>()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                BrandPageHeader(
                    title: "Hợp nhất tệp CoW (APFS)",
                    subtitle: "Giải phóng ổ cứng bằng APFS Copy-on-Write: các file trùng lặp chia sẻ dung lượng mà không bị xóa."
                ) {
                    if vm.isScanning {
                        Button(action: { vm.cancelScan() }) {
                            Label("Dừng quét", systemImage: "xmark.circle")
                        }
                        .buttonStyle(BrandSecondaryButtonStyle())
                    } else {
                        Button(action: { vm.startScan() }) {
                            Label(vm.groups.isEmpty ? "Bắt đầu quét" : "Quét lại", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(BrandSecondaryButtonStyle())
                        .disabled(vm.isCloning)
                    }

                    if vm.undoAvailable {
                        Button(action: { vm.undoAll() }) {
                            Label("Hoàn tác (Tách riêng)", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(BrandSecondaryButtonStyle())
                        .disabled(vm.isCloning || vm.isScanning)
                    }
                }

                // Progress Banner
                if vm.isScanning || vm.isCloning {
                    ModernCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 20, height: 20)
                                Text(vm.statusMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                } else if !vm.statusMessage.isEmpty {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(XmacTheme.cyan)
                        Text(vm.statusMessage)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(XmacTheme.cyan.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(XmacTheme.cyan.opacity(0.18), lineWidth: 1))
                }

                // Summary Action Card
                ModernCard {
                    HStack(alignment: .center) {
                        BrandIconTile(iconName: "square.2.layers.3d.top.filled", color: XmacTheme.cyan, size: 58)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dung lượng có thể giải phóng an toàn")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(vm.isScanning ? "—" : vm.formattedTotalReclaimable)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        Button(action: {
                            vm.reclaimSelected()
                        }) {
                            Label(
                                vm.isCloning
                                    ? "Đang xử lý..."
                                    : (vm.totalReclaimableBytes > 0
                                        ? L10n.format("Hợp nhất CoW (%@)", vm.formattedTotalReclaimable)
                                        : "Chọn mục để hợp nhất"),
                                systemImage: "arrow.triangle.merge"
                            )
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .disabled(vm.totalReclaimableBytes == 0 || vm.isCloning || vm.isScanning)
                    }
                }

                // Info Banner
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("An toàn tuyệt đối: Không mất file, không hỏng liên kết")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Mọi file vẫn ở nguyên vị trí, giữ nguyên ngày giờ và quyền truy cập. Khi bạn chỉnh sửa bất kỳ file nào, macOS tự động phân tách phần thay đổi.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.15), lineWidth: 1))

                // Duplicate List
                if !vm.groups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Tất cả tệp trùng lặp (\(vm.groups.count) nhóm)")
                                .font(.system(size: 14, weight: .bold))

                            Spacer()

                            Button(action: { vm.toggleSelectAll() }) {
                                Text(vm.groups.allSatisfy { $0.isSelected } ? "Bỏ chọn tất cả" : "Chọn tất cả")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.link)
                        }

                        ForEach($vm.groups) { $group in
                            duplicateGroupRow(group: $group)
                        }
                    }
                } else if !vm.isScanning {
                    // Empty state
                    VStack(spacing: 14) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 42))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 30)

                        Text("Chưa có kết quả quét tệp trùng lặp")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("Nhấn \"Bắt đầu quét\" để Xmac tìm kiếm các tệp trùng lặp trong Downloads, Documents và Desktop.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)

                        Button(action: { vm.startScan() }) {
                            Label("Bắt đầu quét", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .padding(.bottom, 30)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .xmacPage()
    }

    // MARK: - Row Subview

    private func duplicateGroupRow(group: Binding<DuplicateGroup>) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.wrappedValue.id)

        return ModernCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Toggle("", isOn: group.isSelected)
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                    Image(systemName: "doc.fill")
                        .font(.system(size: 20))
                        .foregroundColor(XmacTheme.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(group.wrappedValue.fileName)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(group.wrappedValue.categoryName)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.white.opacity(0.1)))
                        }

                        Text(L10n.format("Bản gốc: %@", group.wrappedValue.keeper))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L10n.format("+%@", group.wrappedValue.formattedReclaimable))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color.green)
                        Text(L10n.format("%d bản sao", group.wrappedValue.duplicates.count))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Button(action: {
                        if isExpanded {
                            expandedGroupIDs.remove(group.wrappedValue.id)
                        } else {
                            expandedGroupIDs.insert(group.wrappedValue.id)
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                // Expanded duplicates list
                if isExpanded {
                    Divider().padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Các bản sao sẽ được chia sẻ CoW:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        ForEach(group.wrappedValue.duplicates, id: \.self) { dupPath in
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Text(dupPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Button("Xem") {
                                    vm.revealInFinder(dupPath)
                                }
                                .buttonStyle(.link)
                                .font(.system(size: 11))
                            }
                            .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }
}
