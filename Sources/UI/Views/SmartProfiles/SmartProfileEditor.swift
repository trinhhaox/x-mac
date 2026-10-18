import SwiftUI

final class SmartProfileEditorState: ObservableObject {
    @Published var draft: SmartAppProfile
    @Published var showingDeleteConfirmation = false

    init(profile: SmartAppProfile) {
        self.draft = profile
    }
}

struct SmartProfileEditor: View {
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
                SmartProfileIcon(path: state.draft.applicationURLPath, size: 48)
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
