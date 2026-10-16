import SwiftUI

private final class ClipboardViewState: ObservableObject {
    @Published var query = ""
    @Published var confirmClear = false
}

struct ClipboardHistoryView: View {
    @ObservedObject private var history: ClipboardHistory
    @StateObject private var state = ClipboardViewState()
    init(history: ClipboardHistory = .shared) { self.history = history }
    private var filtered: [ClipboardItem] {
        history.items.filter { state.query.isEmpty || $0.title.localizedCaseInsensitiveContains(state.query) || $0.source.localizedCaseInsensitiveContains(state.query) }
            .sorted { $0.pinned == $1.pinned ? $0.date > $1.date : $0.pinned }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrandPageHeader(
                    title: "Lịch sử clipboard",
                    subtitle: "Tìm lại nội dung đã chép mà không rời khỏi máy Mac."
                ) {
                    StatusBadge(
                        title: history.enabled ? "Đang lưu" : "Đang tắt",
                        isPositive: history.enabled
                    )
                }
                ModernCard {
                    BrandToggleRow(
                        "Lưu lịch sử clipboard",
                        subtitle: "Tối đa 100 mục; mục không ghim được tự xóa sau 7 ngày.",
                        isOn: $history.enabled
                    )

                    Label(
                        "Dữ liệu được lưu cục bộ, không mã hóa. Hãy tạm tắt trước khi chép mật khẩu hoặc nội dung nhạy cảm.",
                        systemImage: "lock.shield"
                    )
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                    Divider().opacity(0.55)

                    Text("Ứng dụng không lưu lịch sử")
                        .font(.system(size: 12, weight: .semibold))
                    BrandTextField(
                        "Bundle ID ứng dụng loại trừ, ngăn cách bằng dấu phẩy",
                        text: $history.exclusions
                    )
                    Text(L10n.text(history.message)).font(.caption).foregroundColor(.secondary)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    BrandSectionTitle(
                        "Nội dung gần đây",
                        subtitle: L10n.format("%lld mục phù hợp", Int64(filtered.count))
                    )
                    Spacer()
                    BrandTextField("Tìm nội dung hoặc ứng dụng nguồn", text: $state.query)
                        .frame(maxWidth: 360)
                    Button("Xóa toàn bộ…") { state.confirmClear = true }
                        .buttonStyle(BrandDestructiveButtonStyle())
                        .disabled(history.items.isEmpty)
                }

                if filtered.isEmpty {
                    ModernCard {
                        VStack(spacing: 10) {
                            BrandIconTile(iconName: "doc.on.clipboard", color: XmacTheme.cyan, size: 54)
                            Text(state.query.isEmpty ? "Clipboard đang trống" : "Không tìm thấy nội dung")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(state.query.isEmpty
                                 ? "Bật lưu lịch sử rồi chép nội dung mới để bắt đầu."
                                 : "Thử một từ khóa hoặc tên ứng dụng nguồn khác.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                    }
                }
                if !filtered.isEmpty {
                    ModernCard {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                                BrandListRow {
                                    HStack(alignment: .top) {
                                        if let data = item.png, let image = NSImage(data: data) {
                                            Image(nsImage: image).resizable().scaledToFit().frame(width: 70, height: 55)
                                        } else {
                                            Image(systemName: item.kind == .files ? "doc.on.doc" : "text.alignleft")
                                                .foregroundColor(XmacTheme.blue)
                                        }
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.title).lineLimit(4).textSelection(.enabled)
                                            Text("\(item.source) • \(item.date.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.caption).foregroundColor(.secondary)
                                            HStack(spacing: 8) {
                                                Button("Chép") { history.copy(item) }
                                                    .buttonStyle(BrandSecondaryButtonStyle())
                                                if item.kind == .text {
                                                    Button("Văn bản thuần") { history.copy(item, plainText: true) }
                                                        .buttonStyle(.link)
                                                }
                                                Spacer()
                                                Button(action: { history.togglePin(item.id) }) {
                                                    Image(systemName: item.pinned ? "pin.slash.fill" : "pin.fill")
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundColor(XmacTheme.blue)
                                                .help(item.pinned ? "Bỏ ghim" : "Ghim")
                                                .accessibilityLabel(item.pinned ? "Bỏ ghim mục này" : "Ghim mục này")
                                                Button(action: { history.remove(item.id) }) {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundColor(.red)
                                                .help("Xóa khỏi lịch sử")
                                                .accessibilityLabel("Xóa mục này khỏi lịch sử clipboard")
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                                if index < filtered.count - 1 {
                                    Divider().opacity(0.55)
                                }
                            }
                        }
                    }
                }
            }.padding(26)
        }
        .xmacPage()
        .alert("Xóa cả các mục đã ghim?", isPresented: $state.confirmClear) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa toàn bộ", role: .destructive) { history.clear() }
        } message: { Text("Thao tác này chỉ xóa lịch sử trong Xmac; không xóa nội dung clipboard hệ thống hoặc các tệp gốc.") }
    }
}
