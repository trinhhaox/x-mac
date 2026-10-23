import SwiftUI

/// Cleanup journal and the list of protected paths, shown from the junk cleaner.
struct CleanupHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var whitelist = CleanerWhitelist.shared
    @State private var entries: [CleanupLogEntry] = []
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Lịch sử dọn & mục được bảo vệ")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Đóng") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("Mục được bảo vệ")
                .font(.system(size: 13, weight: .semibold))
            if whitelist.paths.isEmpty {
                Text("Chưa có mục nào. Nhấp phải vào một mục trong danh sách dọn rác để bảo vệ nó.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(whitelist.paths, id: \.self) { path in
                    HStack {
                        Text(path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Bỏ bảo vệ") { unprotect(path) }
                            .buttonStyle(.link)
                    }
                }
            }
            if let errorText {
                Text(errorText).font(.system(size: 12)).foregroundColor(.red)
            }

            Divider()
            Text("Thao tác gần đây")
                .font(.system(size: 13, weight: .semibold))
            if entries.isEmpty {
                Text("Chưa có thao tác dọn hoặc gỡ ứng dụng nào được ghi lại.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                List(entries) { entry in
                    CleanupHistoryRow(entry: entry)
                }
                .listStyle(.plain)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
        .task {
            entries = await Task.detached(priority: .userInitiated) { CleanupOperationLog.shared.recent() }.value
        }
    }

    private func unprotect(_ path: String) {
        do {
            try whitelist.remove(path)
            errorText = nil
        } catch {
            errorText = L10n.text("Không lưu được danh sách mục được bảo vệ.")
        }
    }
}

private struct CleanupHistoryRow: View {
    let entry: CleanupLogEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text((entry.path as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                Text(entry.path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(outcomeTitle).font(.system(size: 11)).foregroundColor(color)
                Text(entry.date, style: .date).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Text(ByteSize.string(entry.bytes, countStyle: .file))
                .font(.system(size: 11))
                .frame(width: 70, alignment: .trailing)
        }
        .help(entry.reason ?? entry.path)
        .contextMenu {
            Button("Sao chép đường dẫn") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.path, forType: .string)
            }
        }
    }

    private var outcomeTitle: String {
        switch entry.outcome {
        case .trashed: return L10n.text("Đã chuyển vào Thùng rác")
        case .deleted: return L10n.text("Đã xóa vĩnh viễn")
        case .skipped: return L10n.text("Bỏ qua")
        case .failed: return L10n.text("Thất bại")
        }
    }

    private var icon: String {
        switch entry.outcome {
        case .trashed: return "trash"
        case .deleted: return "xmark.bin"
        case .skipped: return "shield"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch entry.outcome {
        case .trashed, .deleted: return .primary
        case .skipped: return .secondary
        case .failed: return .orange
        }
    }
}
