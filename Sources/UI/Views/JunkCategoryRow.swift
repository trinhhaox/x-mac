import SwiftUI

struct CategoryRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var category: JunkCategory
    @ObservedObject var vm: JunkCleanerViewModel

    private func protect(_ item: JunkItem) {
        do {
            try CleanerEngine.shared.protect(item)
            vm.cleanResultText = L10n.format("Đã bảo vệ %@. Mục này sẽ không bị dọn nữa.", item.name)
        } catch {
            vm.cleanResultText = L10n.text("Không lưu được danh sách mục được bảo vệ.")
        }
    }
    
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
                            .help(item.path)
                            .contextMenu {
                                Button("Hiện trong Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                                }
                                Button("Luôn giữ mục này (không dọn)") {
                                    protect(item)
                                }
                                .disabled(CleanerEngine.shared.isCleaning)
                            }
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: vm.isExpanded(categoryName: category.name))
        }
    }
}
