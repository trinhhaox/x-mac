import AppKit
import SwiftUI

private enum DownloadFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case active = "Đang tải"
    case paused = "Tạm dừng"
    case completed = "Hoàn tất"
    case failed = "Lỗi"

    var id: String { rawValue }
    var title: String { L10n.text(rawValue) }
}

private final class DownloadsViewState: ObservableObject {
    @Published var filter: DownloadFilter = .all
    @Published var searchText = ""
    @Published var showingNewTask = false
    @Published var links = ""
    @Published var destinationDirectory = DownloadManager.shared.defaultDirectory
    @Published var validationMessage: String?
}

public struct DownloadsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var manager = DownloadManager.shared
    @StateObject private var viewState = DownloadsViewState()

    public init() {}

    private var visibleItems: [ManagedDownload] {
        manager.items.filter { item in
            let matchesFilter: Bool
            switch viewState.filter {
            case .all:
                matchesFilter = true
            case .active:
                matchesFilter = item.status == .downloading || item.status == .waitingForNetwork
            case .paused:
                matchesFilter = item.status == .paused
            case .completed:
                matchesFilter = item.status == .completed
            case .failed:
                matchesFilter = item.status == .failed || item.status == .cancelled
            }

            let query = viewState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || item.fileName.localizedCaseInsensitiveContains(query)
                || item.sourceURL.localizedCaseInsensitiveContains(query)
            return matchesFilter && matchesSearch
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 4)

            VStack(spacing: 14) {
                controls

                if manager.items.isEmpty {
                    emptyState
                } else if visibleItems.isEmpty {
                    noResults
                } else {
                    ScrollView {
                        ModernCard {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                    downloadRow(item)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    if index < visibleItems.count - 1 {
                                        Divider().opacity(0.55)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 24)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: visibleItems.map(\.id))
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 16)
        }
        .sheet(isPresented: $viewState.showingNewTask) {
            newTaskSheet
        }
        .xmacPage()
    }

    private var header: some View {
        BrandPageHeader(
            title: "Tải xuống",
            subtitle: "Quản lý tải tệp HTTP/HTTPS bằng engine native của macOS."
        ) {
            Button(action: openNewTask) {
                Label("Tác vụ mới", systemImage: "plus")
            }
            .buttonStyle(BrandPrimaryButtonStyle())
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Leading-aligned like the search field and list below it; the
            // label stays available to VoiceOver.
            Picker("Trạng thái", selection: $viewState.filter) {
                ForEach(DownloadFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(XmacTheme.blue)
                    TextField("Tìm tệp hoặc liên kết", text: $viewState.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(XmacTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(XmacTheme.cardStroke, lineWidth: 1)
                )

                Button("Xóa lịch sử") {
                    manager.clearFinished()
                }
                .buttonStyle(BrandDestructiveButtonStyle())
                .disabled(!manager.items.contains { $0.status != .downloading && $0.status != .paused && $0.status != .waitingForNetwork })
            }
        }
    }

    private var emptyState: some View {
        ModernCard {
            VStack(spacing: 14) {
                BrandIconTile(iconName: "arrow.down.circle.fill", size: 62)
                Text("Chưa có tác vụ tải xuống")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("Thêm tối đa 20 liên kết mỗi lần. Xmac sẽ lưu vào thư mục Downloads hoặc thư mục bạn chọn.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Button("Thêm tác vụ đầu tiên", action: openNewTask)
                    .buttonStyle(BrandPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 290)
        }
    }

    private var noResults: some View {
        ModernCard {
            VStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 34))
                    .foregroundColor(XmacTheme.blue)
                Text("Không có tác vụ phù hợp")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Thử thay đổi bộ lọc hoặc từ khóa tìm kiếm.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private func downloadRow(_ item: ManagedDownload) -> some View {
        BrandListRow {
            HStack(spacing: 14) {
                BrandIconTile(iconName: statusIcon(item.status), color: statusColor(item.status), size: 46)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(item.fileName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        statusBadge(item.status)
                        Spacer()
                        Text(progressLabel(item))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if item.status == .downloading || item.status == .paused || item.status == .waitingForNetwork {
                        ProgressView(value: item.progress)
                            .tint(XmacTheme.blue)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: item.progress)
                    }

                    Text(item.errorMessage.map { L10n.text($0) } ?? item.sourceURL)
                        .font(.system(size: 11))
                        .foregroundColor(item.errorMessage == nil ? .secondary : .red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                actions(for: item)
            }
        }
    }

    @ViewBuilder
    private func actions(for item: ManagedDownload) -> some View {
        HStack(spacing: 6) {
            switch item.status {
            case .downloading, .waitingForNetwork:
                downloadActionButton("pause.fill", label: L10n.format("Tạm dừng tải %@", item.fileName)) {
                    manager.pause(item.id)
                }
                downloadActionButton("xmark", label: L10n.format("Hủy tải %@", item.fileName), destructive: true) {
                    manager.cancel(item.id)
                }
            case .paused, .failed:
                downloadActionButton("play.fill", label: L10n.format("Tiếp tục tải %@", item.fileName)) {
                    manager.resume(item.id)
                }
                downloadActionButton("trash", label: L10n.format("Xóa %@ khỏi lịch sử tải", item.fileName), destructive: true) {
                    manager.remove(item.id)
                }
            case .completed:
                downloadActionButton("folder", label: L10n.format("Hiển thị %@ trong Finder", item.fileName)) {
                    manager.reveal(item.id)
                }
                downloadActionButton("trash", label: L10n.format("Xóa %@ khỏi lịch sử tải", item.fileName), destructive: true) {
                    manager.remove(item.id)
                }
            case .cancelled:
                downloadActionButton("arrow.clockwise", label: L10n.format("Tải lại %@", item.fileName)) {
                    manager.resume(item.id)
                }
                downloadActionButton("trash", label: L10n.format("Xóa %@ khỏi lịch sử tải", item.fileName), destructive: true) {
                    manager.remove(item.id)
                }
            }
        }
    }

    private func downloadActionButton(
        _ icon: String,
        label: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill((destructive ? Color.red : XmacTheme.blue).opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundColor(destructive ? .red : XmacTheme.blue)
        .help(label)
        .accessibilityLabel(label)
    }

    private var newTaskSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tác vụ tải xuống mới")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("Mỗi dòng một liên kết HTTP hoặc HTTPS, tối đa 20 liên kết.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                BrandIconTile(iconName: "arrow.down.circle.fill", size: 44)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Liên kết")
                    .font(.system(size: 12, weight: .semibold))
                TextEditor(text: $viewState.links)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(XmacTheme.workspaceBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(XmacTheme.cardStroke, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Lưu vào")
                    .font(.system(size: 12, weight: .semibold))
                HStack {
                    Text(viewState.destinationDirectory.path)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Chọn thư mục…", action: chooseDirectory)
                        .buttonStyle(BrandSecondaryButtonStyle())
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(XmacTheme.workspaceBackground)
                )
            }

            if let validationMessage = viewState.validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }

            HStack {
                Spacer()
                Button("Hủy") {
                    viewState.showingNewTask = false
                }
                .buttonStyle(BrandSecondaryButtonStyle())
                Button("Bắt đầu tải") {
                    submitDownloads()
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(viewState.links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(XmacTheme.cardBackground)
    }

    private func openNewTask() {
        viewState.links = ""
        viewState.validationMessage = nil
        viewState.destinationDirectory = manager.defaultDirectory
        viewState.showingNewTask = true
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Chọn thư mục lưu tệp"
        panel.directoryURL = viewState.destinationDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewState.destinationDirectory = url
        }
    }

    private func submitDownloads() {
        let rejected = manager.enqueue(rawLinks: viewState.links, directory: viewState.destinationDirectory)
        if rejected.isEmpty {
            viewState.showingNewTask = false
            viewState.links = ""
            viewState.validationMessage = nil
        } else {
            viewState.validationMessage = L10n.format("Không thể thêm: %@", rejected.joined(separator: ", "))
            viewState.links = rejected.filter { $0.contains("://") }.joined(separator: "\n")
        }
    }

    private func statusBadge(_ status: ManagedDownloadStatus) -> some View {
        Text(statusLabel(status))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(statusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(statusColor(status).opacity(0.12)))
    }

    private func statusLabel(_ status: ManagedDownloadStatus) -> String {
        switch status {
        case .downloading: return "Đang tải"
        case .waitingForNetwork: return "Chờ kết nối"
        case .paused: return "Tạm dừng"
        case .completed: return "Hoàn tất"
        case .failed: return "Lỗi"
        case .cancelled: return "Đã hủy"
        }
    }

    private func statusIcon(_ status: ManagedDownloadStatus) -> String {
        switch status {
        case .downloading: return "arrow.down"
        case .waitingForNetwork: return "wifi.slash"
        case .paused: return "pause.fill"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        }
    }

    private func statusColor(_ status: ManagedDownloadStatus) -> Color {
        switch status {
        case .downloading: return XmacTheme.blue
        case .waitingForNetwork: return .orange
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    private func progressLabel(_ item: ManagedDownload) -> String {
        let received = ByteSize.string(item.receivedBytes, countStyle: .file)
        guard item.expectedBytes > 0 else { return received }
        let expected = ByteSize.string(item.expectedBytes, countStyle: .file)
        return "\(received) / \(expected)"
    }
}
