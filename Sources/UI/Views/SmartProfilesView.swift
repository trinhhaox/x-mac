import AppKit
import SwiftUI

private final class SmartProfilesViewState: ObservableObject {
    @Published var selectedBundleIdentifier: String? = nil
    @Published var searchText = ""
    @Published var showingApplicationPicker = false
}

public struct SmartProfilesView: View {
    @ObservedObject private var manager: SmartProfilesManager
    @StateObject private var viewState = SmartProfilesViewState()

    public init(manager: SmartProfilesManager = .shared) {
        self.manager = manager
    }

    private var filteredProfiles: [SmartAppProfile] {
        let query = viewState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return manager.profiles }
        return manager.profiles.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedProfile: SmartAppProfile? {
        guard let selectedBundleIdentifier = viewState.selectedBundleIdentifier else { return nil }
        return manager.profile(for: selectedBundleIdentifier)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandPageHeader(
                title: "Smart Profiles",
                subtitle: "Tự động áp dụng bộ gõ và quyền clipboard theo ứng dụng."
            ) {
                HStack(spacing: 9) {
                    Button {
                        manager.setEnabled(!manager.isEnabled)
                    } label: {
                        Label(
                            manager.isEnabled ? L10n.text("Tạm dừng") : L10n.text("Tiếp tục"),
                            systemImage: manager.isEnabled ? "pause.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())

                    Button {
                        manager.refreshAvailableApplications()
                        viewState.showingApplicationPicker = true
                    } label: {
                        Label(L10n.text("Thêm ứng dụng"), systemImage: "plus")
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                }
            }

            activeStatusCard

            if manager.loadFailed {
                loadFailureCard
            } else {
                HStack(alignment: .top, spacing: 16) {
                    profileList
                        .frame(width: 286)

                    Group {
                        if let selectedProfile {
                            SmartProfileEditor(profile: selectedProfile, manager: manager)
                                .id(selectedProfile.bundleIdentifier)
                        } else {
                            emptyDetail
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 430, alignment: .top)
                }
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .xmacPage()
        .onAppear {
            selectFirstProfileIfNeeded()
        }
        .onChange(of: manager.profiles) { _ in
            selectFirstProfileIfNeeded()
        }
        .sheet(isPresented: $viewState.showingApplicationPicker) {
            SmartProfileApplicationPicker(manager: manager) { application in
                let profile = manager.addProfile(for: application)
                viewState.selectedBundleIdentifier = profile.bundleIdentifier
                viewState.showingApplicationPicker = false
            }
        }
    }

    private var activeStatusCard: some View {
        ModernCard {
            HStack(spacing: 12) {
                Circle()
                    .fill(manager.isEnabled ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                    .shadow(color: (manager.isEnabled ? Color.green : Color.orange).opacity(0.36), radius: 5)

                VStack(alignment: .leading, spacing: 3) {
                    if let profile = manager.activeProfile {
                        Text(L10n.format("Đang áp dụng: %@", profile.displayName))
                            .font(.system(size: 13, weight: .semibold))
                        Text(profileSummary(profile))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text(L10n.text(manager.isEnabled ? "Smart Profiles đang bật" : "Smart Profiles đang tạm dừng"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.text(manager.isEnabled
                            ? "Ứng dụng không có profile sẽ giữ cài đặt toàn cục hiện tại."
                            : "Xmac đang giữ nguyên cài đặt bộ gõ và clipboard toàn cục."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { manager.isEnabled },
                    set: { manager.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(XmacTheme.blue)
                .accessibilityLabel(L10n.text("Bật Smart Profiles"))
            }
        }
    }

    private var profileList: some View {
        ModernCard {
            HStack {
                BrandSectionTitle("Ứng dụng")
                Spacer()
                Text(L10n.format("%lld profile", Int64(manager.profiles.count)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField(L10n.text("Tìm theo tên ứng dụng…"), text: $viewState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(XmacTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(XmacTheme.cardStroke, lineWidth: 1)
            )

            if manager.profiles.isEmpty {
                VStack(spacing: 10) {
                    BrandIconTile(iconName: "app.badge", color: XmacTheme.blue, size: 42)
                    Text(L10n.text("Chưa có profile ứng dụng"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("Thêm ứng dụng để Xmac tự chọn cấu hình phù hợp."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button(L10n.text("Thêm ứng dụng")) {
                        manager.refreshAvailableApplications()
                        viewState.showingApplicationPicker = true
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else if filteredProfiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                    Text(L10n.text("Không tìm thấy ứng dụng phù hợp."))
                        .font(.system(size: 12, weight: .medium))
                    Button(L10n.text("Xóa tìm kiếm")) { viewState.searchText = "" }
                        .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredProfiles) { profile in
                            profileRow(profile)
                        }
                    }
                }
                .frame(maxHeight: 430)
            }
        }
    }

    private func profileRow(_ profile: SmartAppProfile) -> some View {
        let isSelected = viewState.selectedBundleIdentifier == profile.bundleIdentifier
        let isActive = manager.activeProfile?.bundleIdentifier == profile.bundleIdentifier
        return Button {
            viewState.selectedBundleIdentifier = profile.bundleIdentifier
        } label: {
            HStack(spacing: 10) {
                applicationIcon(for: profile, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(profile.imePolicy.title)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isActive {
                    Text(L10n.text("Đang dùng"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.1)))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? XmacTheme.blue.opacity(0.10) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(XmacTheme.blue)
                        .frame(width: 3, height: 28)
                        .padding(.leading, 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyDetail: some View {
        ModernCard {
            VStack(spacing: 12) {
                BrandIconTile(iconName: "slider.horizontal.3", color: XmacTheme.blue, size: 52)
                Text(L10n.text("Chọn một ứng dụng"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(L10n.text("Chọn profile bên trái hoặc thêm ứng dụng mới để cấu hình."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 390)
        }
    }

    private var loadFailureCard: some View {
        ModernCard {
            VStack(spacing: 12) {
                BrandIconTile(iconName: "exclamationmark.triangle", color: .orange, size: 52)
                Text(L10n.text("Không thể tải Smart Profiles"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(L10n.text("Cấu hình toàn cục vẫn được giữ nguyên và không profile nào được tự động áp dụng."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
        }
    }

    private func selectFirstProfileIfNeeded() {
        if let selectedBundleIdentifier = viewState.selectedBundleIdentifier,
           manager.profile(for: selectedBundleIdentifier) != nil {
            return
        }
        viewState.selectedBundleIdentifier = manager.profiles.first?.bundleIdentifier
    }

    private func profileSummary(_ profile: SmartAppProfile) -> String {
        [profile.imePolicy.title, profile.typingPolicy.title, profile.clipboardPolicy.title]
            .joined(separator: " · ")
    }
}

private final class SmartProfileEditorState: ObservableObject {
    @Published var draft: SmartAppProfile
    @Published var showingDeleteConfirmation = false

    init(profile: SmartAppProfile) {
        self.draft = profile
    }
}

private struct SmartProfileEditor: View {
    @ObservedObject private var manager: SmartProfilesManager
    @ObservedObject private var clipboard = ClipboardHistory.shared
    @StateObject private var state: SmartProfileEditorState

    init(profile: SmartAppProfile, manager: SmartProfilesManager) {
        self.manager = manager
        _state = StateObject(wrappedValue: SmartProfileEditorState(profile: profile))
    }

    var body: some View {
        ModernCard {
            HStack(spacing: 12) {
                applicationIcon(for: state.draft, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.draft.displayName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(state.draft.bundleIdentifier)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    state.showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(BrandDestructiveButtonStyle())
                .help(L10n.text("Xóa profile"))
                .accessibilityLabel(L10n.text("Xóa profile"))
            }

            Divider()

            BrandSectionTitle(
                "Quy tắc khi ứng dụng hoạt động",
                subtitle: "Kế thừa sẽ dùng cài đặt toàn cục hiện tại của Xmac."
            )

            ruleRow(
                title: "Bộ gõ",
                subtitle: "Chọn ngôn ngữ nhập khi ứng dụng lên foreground."
            ) {
                Picker("", selection: $state.draft.imePolicy) {
                    ForEach(SmartProfileIMEPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            Divider().opacity(0.6)

            ruleRow(
                title: "Kiểu gõ",
                subtitle: "Chỉ có hiệu lực khi profile sử dụng Tiếng Việt."
            ) {
                Picker("", selection: $state.draft.typingPolicy) {
                    ForEach(SmartProfileTypingPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }

            Divider().opacity(0.6)

            ruleRow(
                title: "Gõ tắt",
                subtitle: "Dùng bảng gõ tắt riêng của Xmac."
            ) {
                Picker("", selection: $state.draft.macroPolicy) {
                    ForEach(SmartProfileTogglePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            Divider().opacity(0.6)

            ruleRow(
                title: "Lịch sử clipboard",
                subtitle: "Secure Input và dữ liệu nhạy cảm luôn bị chặn."
            ) {
                Picker("", selection: $state.draft.clipboardPolicy) {
                    ForEach(SmartProfileClipboardPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "shield.checkered")
                    .foregroundColor(XmacTheme.blue)
                Text(L10n.text(clipboard.enabled
                    ? "Profile không thể vượt qua Secure Input hoặc danh sách ứng dụng nhạy cảm."
                    : "Clipboard History đang tắt toàn cục; profile này không thể tự bật việc thu thập."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(XmacTheme.blue.opacity(0.07))
            )

            HStack(spacing: 9) {
                Text(L10n.text("Thay đổi chỉ áp dụng sau khi lưu."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button(L10n.text("Hoàn tác")) {
                    if let profile = manager.profile(for: state.draft.bundleIdentifier) {
                        state.draft = profile
                    }
                }
                .buttonStyle(BrandSecondaryButtonStyle())
                .disabled(!hasChanges)

                Button(L10n.text("Lưu thay đổi")) {
                    manager.save(state.draft)
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(!hasChanges)
            }
        }
        .alert(L10n.format("Xóa profile %@?", state.draft.displayName), isPresented: $state.showingDeleteConfirmation) {
            Button(L10n.text("Hủy"), role: .cancel) {}
            Button(L10n.text("Xóa"), role: .destructive) {
                manager.removeProfile(bundleIdentifier: state.draft.bundleIdentifier)
            }
        } message: {
            Text(L10n.text("Ứng dụng sẽ quay lại dùng cài đặt toàn cục."))
        }
    }

    private var hasChanges: Bool {
        manager.profile(for: state.draft.bundleIdentifier) != state.draft
    }

    private func ruleRow<Control: View>(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(title))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.text(subtitle))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, 2)
    }
}

private final class SmartProfilePickerState: ObservableObject {
    @Published var searchText = ""
}

private struct SmartProfileApplicationPicker: View {
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
                                    applicationIcon(for: application, size: 38)
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

@ViewBuilder
private func applicationIcon(for profile: SmartAppProfile, size: CGFloat) -> some View {
    if let path = profile.applicationURLPath,
       FileManager.default.fileExists(atPath: path) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    } else {
        BrandIconTile(iconName: "app", color: XmacTheme.blue, size: size)
    }
}

@ViewBuilder
private func applicationIcon(for application: SmartProfileApplication, size: CGFloat) -> some View {
    if let path = application.applicationURLPath,
       FileManager.default.fileExists(atPath: path) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    } else {
        BrandIconTile(iconName: "app", color: XmacTheme.blue, size: size)
    }
}
