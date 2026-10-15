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
                BrandPageHeader(eyebrow: "CLIPBOARD", title: "Lịch sử clipboard", subtitle: "Lưu và tìm nội dung đã chép trên máy này.") { EmptyView() }
                ModernCard {
                    Toggle("Bật lưu lịch sử clipboard", isOn: $history.enabled)
                    Text("Lưu cục bộ dạng không mã hóa, tối đa 100 mục / 16 MB. Mục không ghim được xóa sau 7 ngày; mỗi mục tối đa 1 MB. Bộ lọc không thể nhận diện mọi mật khẩu hoặc bí mật; hãy tạm tắt trước khi chép dữ liệu nhạy cảm.")
                        .font(.caption).foregroundColor(.secondary)
                    Text("Ứng dụng loại trừ (bundle ID, cách nhau bằng dấu phẩy)").font(.caption).foregroundColor(.secondary)
                    TextField("Bundle ID ứng dụng loại trừ, ngăn cách bằng dấu phẩy", text: $history.exclusions)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Tìm nội dung hoặc ứng dụng nguồn", text: $state.query).textFieldStyle(.roundedBorder)
                        Button("Xóa toàn bộ…") { state.confirmClear = true }.disabled(history.items.isEmpty)
                    }
                    Text(history.message).font(.caption).foregroundColor(.secondary)
                }
                if filtered.isEmpty { Text("Chưa có nội dung phù hợp. Bật lưu rồi chép nội dung mới để bắt đầu.").foregroundColor(.secondary) }
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { item in
                        ModernCard {
                            HStack(alignment: .top) {
                                if let data = item.png, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 70, height: 55)
                                } else { Image(systemName: item.kind == .files ? "doc.on.doc" : "text.alignleft").foregroundColor(XmacTheme.blue) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).lineLimit(4).textSelection(.enabled)
                                    Text("\(item.source) • \(item.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundColor(.secondary)
                                    HStack {
                                        Button("Chép") { history.copy(item) }
                                        if item.kind == .text { Button("Chép văn bản thuần") { history.copy(item, plainText: true) } }
                                        Button(item.pinned ? "Bỏ ghim" : "Ghim") { history.togglePin(item.id) }
                                        Button("Xóa") { history.remove(item.id) }
                                    }.font(.caption)
                                }
                                Spacer(minLength: 0)
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
