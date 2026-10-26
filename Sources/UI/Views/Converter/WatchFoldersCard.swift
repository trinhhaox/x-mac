import SwiftUI

/// Master switch and rule list for folders whose new files are converted automatically.
struct WatchFoldersCard: View {
    @ObservedObject private var store = WatchFolderStore.shared
    @State private var showingNewRule = false

    var body: some View {
        ModernCard {
            BrandSectionTitle(
                "Thư mục theo dõi",
                subtitle: "Chỉ xử lý tệp mới xuất hiện sau khi bật. Tệp gốc luôn được giữ lại."
            )
            BrandToggleRow("Tự chuyển đổi tệp mới trong thư mục theo dõi", isOn: $store.isEnabled)
            VStack(spacing: 0) {
                ForEach($store.rules) { $rule in
                    ruleRow($rule)
                    Divider()
                }
            }
            Button(L10n.text("Thêm quy tắc…")) { showingNewRule = true }
                .buttonStyle(BrandSecondaryButtonStyle())
        }
        .sheet(isPresented: $showingNewRule) {
            WatchFolderRuleSheet { store.rules.append($0) }
        }
    }

    private func ruleRow(_ rule: Binding<WatchFolderRule>) -> some View {
        let value = rule.wrappedValue
        return BrandListRow {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: value.folderURL.lastPathComponent).font(.system(size: 13, weight: .medium))
                    Text(verbatim: summary(of: value)).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer(minLength: 12)
                Toggle(L10n.text("Bật"), isOn: rule.enabled).toggleStyle(.switch).labelsHidden().tint(XmacTheme.blue)
                Button(L10n.text("Xoá")) { store.rules.removeAll { $0.id == value.id } }
                    .buttonStyle(BrandSecondaryButtonStyle())
            }
        }
    }

    private func summary(of rule: WatchFolderRule) -> String {
        let line = "\(rule.extensions.joined(separator: ", ")) → \(rule.targetTitle)"
        guard let subfolder = rule.outputSubfolder else { return line }
        return line + " · " + L10n.format("lưu vào “%@”", subfolder)
    }
}
