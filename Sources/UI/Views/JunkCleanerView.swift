import SwiftUI

public struct JunkCleanerView: View {
    @ObservedObject var cleaner = CleanerEngine.shared
    @ObservedObject var vm = JunkCleanerViewModel.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandPageHeader(
                    title: "Dọn rác hệ thống",
                    subtitle: "Xem trước, chọn lọc và làm sạch cache, log cùng dữ liệu tạm."
                ) {
                    Button(action: {
                        cleaner.startScan()
                    }) {
                        Label(cleaner.isScanning ? "Đang quét..." : "Quét lại", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(cleaner.isScanning || cleaner.isCleaning)
                }
                
                // Result Banner
                if let res = vm.cleanResultText {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(res)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button("Đóng") {
                            vm.cleanResultText = nil
                        }
                        .buttonStyle(.link)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.18), lineWidth: 1))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Total Junk Found Card
                ModernCard {
                    HStack(alignment: .center) {
                        BrandIconTile(iconName: "sparkles", color: XmacTheme.cyan, size: 58)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tổng tệp rác đã phát hiện")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(cleaner.formattedTotalDiscoveredSize)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            vm.showCleanConfirmation = true
                        }) {
                            Label(
                                cleaner.isCleaning
                                    ? "Đang dọn..."
                                    : (cleaner.totalSelectedSize > 0
                                        ? L10n.format("Dọn %@", cleaner.formattedTotalSelectedSize)
                                        : "Chọn mục để dọn"),
                                systemImage: "trash.fill"
                            )
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(BrandDestructiveButtonStyle())
                        .disabled(cleaner.totalSelectedSize == 0 || cleaner.isCleaning || cleaner.isScanning)
                    }
                }
                
                // Memory Purge Action Card
                ModernCard {
                    HStack(spacing: 12) {
                        BrandIconTile(iconName: "bolt.fill", color: XmacTheme.violet, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tối ưu & Giải phóng RAM")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Giải phóng bộ nhớ đệm Inactive Memory giúp máy tính phản hồi nhanh và mượt mà hơn.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Giải phóng RAM") {
                            cleaner.purgeMemory { success in
                                vm.cleanResultText = success
                                    ? "Đã giải phóng bộ nhớ RAM đệm thành công!"
                                    : "Không thể giải phóng RAM trên hệ thống hiện tại."
                            }
                        }
                        .buttonStyle(BrandSecondaryButtonStyle())
                    }
                }
                
                // Danh mục rác chi tiết
                VStack(spacing: 12) {
                    if cleaner.isScanning {
                        ModernCard {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Đang quét phân tích các tệp tin trong hệ thống...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                        }
                    } else if cleaner.categories.isEmpty {
                        ModernCard {
                            VStack(spacing: 8) {
                                Text("Chưa có dữ liệu quét")
                                    .font(.system(size: 14, weight: .semibold))
                                Button("Bắt đầu quét rác") {
                                    cleaner.startScan()
                                }
                                .buttonStyle(BrandPrimaryButtonStyle())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    } else {
                        ForEach($cleaner.categories) { $category in
                            CategoryRow(category: $category, vm: vm)
                        }
                    }
                }
            }
            .padding(26)
        }
        .xmacPage()
        .onAppear {
            if cleaner.categories.isEmpty {
                cleaner.startScan()
            }
        }
        .alert(isPresented: $vm.showCleanConfirmation) {
            Alert(
                title: Text("Xác nhận xóa dữ liệu đã chọn?"),
                message: Text("Các mục đã chọn sẽ được chuyển vào Thùng rác (riêng mục trong Thùng rác sẽ bị xóa vĩnh viễn). Cache của ứng dụng đang chạy sẽ được bỏ qua."),
                primaryButton: .destructive(Text("Chuyển vào Thùng rác")) {
                    cleaner.cleanSelectedJunk { result in
                        let formatted = ByteCountFormatter.string(
                            fromByteCount: result.deletedBytes,
                            countStyle: .file
                        )
                        var text = result.failedCount == 0
                            ? L10n.format("Đã chuyển %lld mục (%@) vào Thùng rác. Dọn sạch Thùng rác để lấy lại dung lượng.", Int64(result.deletedCount), formatted)
                            : L10n.format("Đã chuyển %lld mục (%@) vào Thùng rác; %lld mục thất bại hoặc bị từ chối.", Int64(result.deletedCount), formatted, Int64(result.failedCount))
                        if result.skippedCount > 0 {
                            text += " " + L10n.format("Bỏ qua %lld mục của ứng dụng đang chạy.", Int64(result.skippedCount))
                        }
                        vm.cleanResultText = text
                    }
                },
                secondaryButton: .cancel(Text("Huỷ"))
            )
        }
    }
}

struct CategoryRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var category: JunkCategory
    @ObservedObject var vm: JunkCleanerViewModel
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle(L10n.format("Chọn tất cả trong %@", category.name), isOn: $category.isSelected)
                        .labelsHidden()
                        .onChange(of: category.isSelected) { newValue in
                            for i in 0..<category.items.count {
                                category.items[i].isSelected = newValue
                            }
                        }
                    
                    Image(systemName: category.iconName)
                        .foregroundColor(XmacTheme.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.system(size: 14, weight: .semibold))
                        Text(category.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(category.formattedTotalSize)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(category.totalSize > 0 ? .primary : .secondary)
                    
                    Button(action: {
                        vm.toggleExpand(categoryName: category.name)
                    }) {
                        Image(systemName: vm.isExpanded(categoryName: category.name) ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        vm.isExpanded(categoryName: category.name)
                            ? L10n.format("Thu gọn %@", category.name)
                            : L10n.format("Mở rộng %@", category.name)
                    )
                }
                
                if vm.isExpanded(categoryName: category.name) && !category.items.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach($category.items) { $item in
                            HStack {
                                Toggle(L10n.format("Chọn %@", item.name), isOn: $item.isSelected)
                                    .labelsHidden()
                                Text(item.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                Text(item.formattedSize)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 36)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: vm.isExpanded(categoryName: category.name))
        }
    }
}
