import SwiftUI

struct DownloadsOrganizerView: View {
    @ObservedObject private var organizer: DownloadsOrganizer
    init(organizer: DownloadsOrganizer = .shared) { self.organizer = organizer }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrandPageHeader(eyebrow: "DOWNLOADS ORGANIZER", title: "Sắp xếp Downloads", subtitle: "Xem trước, di chuyển vào thư mục theo loại tệp và hoàn tác.") { EmptyView() }
                ModernCard {
                    HStack {
                        Text(organizer.root.path).font(.caption).textSelection(.enabled)
                        Spacer()
                        Button("Chọn thư mục…") { organizer.chooseFolder() }.disabled(organizer.busy)
                    }
                    ForEach(organizer.rules.indices, id: \.self) { index in
                        Toggle("\(organizer.rules[index].folder) — \(organizer.rules[index].extensions.sorted().joined(separator: ", "))",
                               isOn: Binding(get: { organizer.rules[index].enabled }, set: { organizer.rules[index].enabled = $0; organizer.refresh() }))
                            .font(.caption).disabled(organizer.busy)
                    }
                    Text("Theo dõi thư mục chỉ cập nhật bản xem trước. Bỏ qua thư mục, liên kết và tệp mới sửa dưới 5 giây. Tệp đang tải có thể vẫn xuất hiện nếu ứng dụng nguồn ghi trực tiếp vào tên cuối; chỉ xác nhận sau khi tải xong.")
                        .font(.caption).foregroundColor(.secondary)
                }
                ModernCard {
                    HStack {
                        Button("Quét / Xem trước") { organizer.refresh() }.disabled(organizer.busy)
                        Button("Sắp xếp \(organizer.preview.count) tệp…") { organizer.requestApply() }
                            .disabled(organizer.busy || organizer.preview.isEmpty || organizer.undoCount > 0)
                        if organizer.busy { ProgressView().controlSize(.small) }
                    }
                    Text(organizer.message).font(.caption).textSelection(.enabled)
                    if organizer.undoCount > 0 {
                        Text("Thư mục gốc: \(organizer.undoRoot)").font(.caption).textSelection(.enabled)
                        Text("\(organizer.undoCount) tệp thuộc lần sắp xếp trước còn có thể hoàn tác, kể cả sau khi mở lại Xmac. Hoàn tác hoặc giữ thay đổi trước khi sắp xếp lần mới.")
                            .font(.caption).foregroundColor(.secondary)
                        HStack {
                            Button("Hoàn tác") { organizer.undo() }.disabled(organizer.busy)
                            Button("Giữ thay đổi…") { organizer.keepConfirmation = true }.disabled(organizer.busy)
                        }
                    }
                }
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(organizer.preview) { entry in
                        HStack {
                            Image(systemName: "doc")
                            Text(entry.source.lastPathComponent).lineLimit(1)
                            Spacer()
                            Text("→ \(entry.folder)/").foregroundColor(.secondary)
                        }.font(.system(size: 12)).padding(10)
                    }
                }
            }.padding(26)
        }
        .xmacPage()
        .onAppear { organizer.startWatching() }
        .onDisappear { organizer.stopWatching() }
        .alert("Di chuyển các tệp trong bản xem trước?", isPresented: $organizer.confirmation) {
            Button("Hủy", role: .cancel) { organizer.cancelApply() }
            Button("Sắp xếp") { organizer.apply() }
        } message: { Text("Không ghi đè tệp trùng tên. Tệp thay đổi sau bản xem trước sẽ được bỏ qua; các mục đã di chuyển có thể hoàn tác.") }
        .alert("Giữ thay đổi và bỏ khả năng hoàn tác?", isPresented: $organizer.keepConfirmation) {
            Button("Hủy", role: .cancel) {}
            Button("Giữ thay đổi") { organizer.keepChanges() }
        } message: { Text("Các tệp vẫn ở vị trí hiện tại. Nhật ký hoàn tác sẽ được xóa để bạn có thể sắp xếp lần mới.") }
    }
}
