import SwiftUI

final class SmartProfilePickerState: ObservableObject {
    @Published var searchText = ""
}

struct SmartProfileApplicationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager: SmartProfilesManager
    @StateObject private var state = SmartProfilePickerState()
    let onSelect: (SmartProfileApplication) -> Void

    init(manager: SmartProfilesManager, onSelect: @escaping (SmartProfileApplication) -> Void) {
        self.manager = manager
        self.onSelect = onSelect
    }

    private var applications: [SmartProfileApplication] {
        let existing = Set(manager.profiles.map(\.bundleIdentifier))
        let available = manager.availableApplications.filter { !existing.contains($0.bundleIdentifier) }
        let query = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return available }
        return available.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Thêm ứng dụng"))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(L10n.text("Chọn ứng dụng đang chạy hoặc đã cài đặt trên máy Mac này."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(L10n.text("Đóng")) { dismiss() }
                    .buttonStyle(BrandSecondaryButtonStyle())
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L10n.text("Tìm ứng dụng đang chạy hoặc đã cài…"), text: $state.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(XmacTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(XmacTheme.cardStroke, lineWidth: 1)
            )

            if manager.availableApplications.isEmpty {
                VStack(spacing: 11) {
                    ProgressView()
                    Text(L10n.text("Đang tìm ứng dụng…"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if applications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary)
                    Text(L10n.text("Không còn ứng dụng phù hợp để thêm."))
                        .font(.system(size: 13, weight: .semibold))
                    if !state.searchText.isEmpty {
                        Button(L10n.text("Xóa tìm kiếm")) { state.searchText = "" }
                            .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(applications.enumerated()), id: \.element.id) { index, application in
                            Button {
                                onSelect(application)
                            } label: {
                                HStack(spacing: 11) {
                                    SmartProfileIcon(path: application.applicationURLPath, size: 38)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(application.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(application.bundleIdentifier)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if application.isRunning {
                                        Text(L10n.text("Đang chạy"))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.green)
                                    }
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(XmacTheme.blue)
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < applications.count - 1 {
                                Divider().opacity(0.55)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(XmacTheme.workspaceBackground)
        .onAppear { manager.refreshAvailableApplications() }
    }
}
