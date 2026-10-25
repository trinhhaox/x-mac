import SwiftUI

public struct DeduplicatorView: View {
    @ObservedObject var vm = DeduplicatorViewModel.shared
    @ObservedObject var scheduler = DeduplicatorScheduler.shared
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

                    Button(action: { vm.isScheduleSheetPresented = true }) {
                        Label(
                            scheduler.isEnabled ? "Lịch quét: Bật" : "Lịch quét",
                            systemImage: scheduler.isEnabled ? "clock.badge.checkmark" : "clock.arrow.2.circlepath"
                        )
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .popover(isPresented: $vm.isScheduleSheetPresented) {
                        DeduplicatorSchedulePopoverView(scheduler: scheduler)
                    }

                    if vm.undoAvailable {
                        Button(action: { vm.undoAll() }) {
                            Label("Hoàn tác (Tách riêng)", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(BrandSecondaryButtonStyle())
                        .disabled(vm.isCloning || vm.isScanning)
                    }
                }

                // File Category Filter Bar
                categoryFilterBar

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
                let displayedGroups = vm.filteredGroups
                if !displayedGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.format("Tệp trùng lặp (%d nhóm)", displayedGroups.count))
                                .font(.system(size: 14, weight: .bold))

                            Spacer()

                            Button(action: { vm.toggleSelectAll() }) {
                                Text(displayedGroups.allSatisfy { $0.isSelected } ? "Bỏ chọn tất cả" : "Chọn tất cả")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.link)
                        }

                        ForEach(displayedGroups) { group in
                            duplicateGroupRow(group: group)
                        }
                    }
                } else if !vm.isScanning {
                    // Empty state
                    VStack(spacing: 14) {
                        Image(systemName: vm.selectedCategory.iconName)
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

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(DeduplicatorFileCategory.allCases) { cat in
                let isSelected = vm.selectedCategory == cat
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        vm.selectedCategory = cat
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: cat.iconName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(cat.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? XmacTheme.cyan.opacity(0.18) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? XmacTheme.cyan.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                    .foregroundColor(isSelected ? XmacTheme.cyan : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Row Subview

    private func duplicateGroupRow(group: DuplicateGroup) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.id)
        let bindingSelected = Binding<Bool>(
            get: {
                if let idx = vm.groups.firstIndex(where: { $0.id == group.id }) {
                    return vm.groups[idx].isSelected
                }
                return false
            },
            set: { val in
                if let idx = vm.groups.firstIndex(where: { $0.id == group.id }) {
                    vm.groups[idx].isSelected = val
                }
            }
        )

        return ModernCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Toggle("", isOn: bindingSelected)
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                    Image(systemName: group.category.iconName)
                        .font(.system(size: 15))
                        .foregroundColor(XmacTheme.cyan)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(XmacTheme.cyan.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.fileName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(group.categoryName)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))

                            Text(L10n.format("%d bản sao trùng lặp", group.duplicates.count))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Text(verbatim: "•")
                                .foregroundColor(.secondary.opacity(0.5))

                            Text(L10n.format("Mỗi tệp: %@", group.formattedSize))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L10n.format("Tiết kiệm %@", group.formattedReclaimable))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.green)

                        Button(action: {
                            if isExpanded {
                                expandedGroupIDs.remove(group.id)
                            } else {
                                expandedGroupIDs.insert(group.id)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "Thu gọn" : "Xem chi tiết")
                                    .font(.system(size: 11))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9))
                            }
                        }
                        .buttonStyle(.link)
                    }
                }

                // Expanded duplicates list
                if isExpanded {
                    Divider()
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bản gốc giữ lại (Keeper):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        filePathRow(path: group.keeper, isKeeper: true)

                        Text("Các bản sao sẽ được hợp nhất CoW:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(group.duplicates, id: \.self) { dupPath in
                            filePathRow(path: dupPath, isKeeper: false)
                        }
                    }
                    .padding(.leading, 32)
                }
            }
        }
    }

    private func filePathRow(path: String, isKeeper: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isKeeper ? "star.fill" : "doc.on.doc.fill")
                .font(.system(size: 11))
                .foregroundColor(isKeeper ? .yellow : XmacTheme.cyan)

            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: { vm.revealInFinder(path) }) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Mở trong Finder")
        }
    }
}

// MARK: - Schedule Popover View

public struct DeduplicatorSchedulePopoverView: View {
    @ObservedObject var scheduler: DeduplicatorScheduler
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Lập lịch quét tự động", systemImage: "clock.arrow.2.circlepath")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Toggle("Bật tự động quét định kỳ", isOn: $scheduler.isEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 13, weight: .medium))

            if scheduler.isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Chu kỳ quét:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $scheduler.interval) {
                            ForEach(DeduplicatorScheduleInterval.allCases) { interval in
                                Text(interval.title).tag(interval)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    HStack {
                        Text("Chỉ thông báo khi tiết kiệm từ:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $scheduler.minNotifyMB) {
                            Text("500 MB").tag(500)
                            Text("1 GB").tag(1000)
                            Text("2 GB").tag(2000)
                            Text("5 GB").tag(5000)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    if let lastDate = scheduler.lastScanDate {
                        HStack {
                            Text("Lần quét gần nhất:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: {
                        scheduler.runBackgroundScan()
                    }) {
                        HStack {
                            if scheduler.isBackgroundScanning {
                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                Text("Đang quét nền...")
                            } else {
                                Image(systemName: "play.fill").font(.system(size: 10))
                                Text("Chạy quét nền thử nghiệm ngay")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(scheduler.isBackgroundScanning)
                }
                .padding(.top, 4)
            }

            Text("Quét chạy hoàn toàn trong nền khi máy rảnh rỗi. Khi phát hiện dung lượng trùng lặp đáng kể, Xmac sẽ gửi thông báo để bạn quyết định hợp nhất.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(18)
        .frame(width: 340)
    }
}
