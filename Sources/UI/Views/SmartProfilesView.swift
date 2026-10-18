import AppKit
import SwiftUI

final class SmartProfilesViewState: ObservableObject {
    @Published var selectedBundleIdentifier: String? = nil
    @Published var searchText = ""
    @Published var showingApplicationPicker = false
}

public struct SmartProfilesView: View {
    @ObservedObject var manager: SmartProfilesManager
    @StateObject var viewState = SmartProfilesViewState()

    public init(manager: SmartProfilesManager = .shared) {
        self.manager = manager
    }

    var filteredProfiles: [SmartAppProfile] {
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

                    // With no profiles the empty list already offers "Thêm ứng dụng";
                    // one entry point avoids two identical buttons on screen.
                    if !manager.profiles.isEmpty {
                        Button {
                            manager.refreshAvailableApplications()
                            viewState.showingApplicationPicker = true
                        } label: {
                            Label(L10n.text("Thêm ứng dụng"), systemImage: "plus")
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                    }
                }
            }

            activeStatusCard

            if manager.loadFailed {
                loadFailureCard
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Both columns fill the remaining height so their bottoms line up.
                    profileList
                        .frame(width: 286)
                        .frame(maxHeight: .infinity, alignment: .top)

                    Group {
                        if let selectedProfile {
                            SmartProfileEditor(profile: selectedProfile, manager: manager)
                                .id(selectedProfile.bundleIdentifier)
                        } else {
                            emptyDetail
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 430, maxHeight: .infinity, alignment: .top)
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
