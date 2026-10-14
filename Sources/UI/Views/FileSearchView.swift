import AppKit
import SwiftUI

private final class FileSearchViewState: ObservableObject {
    @Published var query = ""
    @Published var scope: FileSearchScope = .home
    @Published var kind: FileSearchKind = .all
    @Published var includeContents = false
}

public struct FileSearchView: View {
    @ObservedObject private var engine = FileSearchEngine.shared
    @StateObject private var viewState = FileSearchViewState()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 18)

            Divider().opacity(0.45)

            VStack(spacing: 14) {
                searchPanel

                HStack {
                    HStack(spacing: 7) {
                        if engine.isSearching {
                            ProgressView().controlSize(.small)
                        } else {
                            Circle()
                                .fill(engine.results.isEmpty ? Color.secondary.opacity(0.42) : Color.green)
                                .frame(width: 7, height: 7)
                        }
                        Text(engine.statusMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Tối đa 200 kết quả")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.72))
                }
                .padding(.horizontal, 2)

                if engine.results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 16)
        }
        .onChange(of: viewState.query) { _ in scheduleSearch() }
        .onChange(of: viewState.scope) { scope in
            if scope == .custom, engine.customScopeURL == nil {
                engine.chooseCustomScope()
            }
            scheduleSearch(delay: 0)
        }
        .onChange(of: viewState.kind) { _ in scheduleSearch(delay: 0) }
        .onChange(of: viewState.includeContents) { _ in scheduleSearch(delay: 0) }
        .xmacPage()
    }

    private var header: some View {
        BrandPageHeader(
            eyebrow: "SPOTLIGHT SEARCH",
            title: "Tìm tệp nhanh",
            subtitle: "Tìm tên tệp hoặc nội dung đã được macOS lập chỉ mục, không cần daemon nền."
        ) {
            Button(action: chooseFolder) {
                Label("Chọn thư mục", systemImage: "folder.badge.plus")
            }
            .buttonStyle(BrandSecondaryButtonStyle())
        }
    }

    private var searchPanel: some View {
        ModernCard {
            VStack(spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(XmacTheme.blue)

                    TextField("Tên tệp, ext:pdf, type:image, mtime:<7d…", text: $viewState.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .onSubmit { scheduleSearch(delay: 0) }

                    if !viewState.query.isEmpty {
                        Button(action: { viewState.query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Xóa từ khóa")
                    }
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(XmacTheme.workspaceBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(XmacTheme.blue.opacity(0.22), lineWidth: 1)
                )

                HStack(spacing: 12) {
                    Picker("Phạm vi", selection: $viewState.scope) {
                        ForEach(FileSearchScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Picker("Loại", selection: $viewState.kind) {
                        ForEach(FileSearchKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Toggle("Trong nội dung", isOn: $viewState.includeContents)
                        .toggleStyle(.switch)
                        .help("Chỉ tìm trong nội dung mà Spotlight đã lập chỉ mục")
                }

                HStack(spacing: 6) {
                    queryHint("^bao-cao", "bắt đầu bằng")
                    queryHint("final$", "kết thúc bằng")
                    queryHint("!draft", "loại trừ")
                    queryHint("\"kế hoạch quý\"", "cụm từ")
                    Spacer()
                }
            }
        }
    }

    private var emptyState: some View {
        ModernCard {
            VStack(spacing: 13) {
                BrandIconTile(iconName: "doc.text.magnifyingglass", color: XmacTheme.cyan, size: 62)
                Text(viewState.query.isEmpty ? "Tìm đúng tệp, ít thao tác hơn" : "Chưa có kết quả")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(viewState.query.isEmpty
                     ? "Nhập tên, phần mở rộng hoặc loại tệp. Kết quả dùng chỉ mục Spotlight có sẵn trên máy Mac."
                     : "Thử bỏ bớt bộ lọc, đổi phạm vi hoặc bật tìm trong nội dung.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 470)
            }
            .frame(maxWidth: .infinity, minHeight: 250)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(engine.results) { result in
                    resultRow(result)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.bottom, 24)
            .animation(.easeOut(duration: 0.2), value: engine.results.map(\.id))
        }
    }

    private func resultRow(_ result: FileSearchResult) -> some View {
        ModernCard {
            HStack(spacing: 13) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: result.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(result.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if result.isDirectory {
                            Text("THƯ MỤC")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(XmacTheme.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(XmacTheme.blue.opacity(0.1)))
                        }
                    }
                    Text(result.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        Text(result.kind)
                        if !result.isDirectory, result.size > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: result.size, countStyle: .file))
                        }
                        if let modified = result.modifiedAt {
                            Text(modified, style: .relative)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.78))
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    iconButton("doc.on.doc", help: "Sao chép đường dẫn") { engine.copyPath(result) }
                    iconButton("folder", help: "Hiện trong Finder") { engine.reveal(result) }
                    iconButton("arrow.up.forward.app", help: "Mở") { engine.open(result) }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { engine.open(result) }
        .contextMenu {
            Button("Mở") { engine.open(result) }
            Button("Hiện trong Finder") { engine.reveal(result) }
            Button("Sao chép đường dẫn") { engine.copyPath(result) }
        }
    }

    private func queryHint(_ token: String, _ meaning: String) -> some View {
        Text("\(token) · \(meaning)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.07)))
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 27, height: 27)
                .background(Circle().fill(XmacTheme.blue.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .foregroundColor(XmacTheme.blue)
        .help(help)
    }

    private func chooseFolder() {
        engine.chooseCustomScope()
        if engine.customScopeURL != nil {
            viewState.scope = .custom
            scheduleSearch(delay: 0)
        }
    }

    private func scheduleSearch(delay: TimeInterval = 0.24) {
        engine.scheduleSearch(
            text: viewState.query,
            scope: viewState.scope,
            kind: viewState.kind,
            includeContents: viewState.includeContents,
            delay: delay
        )
    }
}
