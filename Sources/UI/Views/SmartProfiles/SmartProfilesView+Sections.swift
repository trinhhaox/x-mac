import SwiftUI

extension SmartProfilesView {
    var profileList: some View {
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
                Spacer(minLength: 0)
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
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredProfiles) { profile in
                            profileRow(profile)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    func profileRow(_ profile: SmartAppProfile) -> some View {
        let isSelected = viewState.selectedBundleIdentifier == profile.bundleIdentifier
        let isActive = manager.activeProfile?.bundleIdentifier == profile.bundleIdentifier
        return Button {
            viewState.selectedBundleIdentifier = profile.bundleIdentifier
        } label: {
            HStack(spacing: 10) {
                SmartProfileIcon(path: profile.applicationURLPath, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(profile.imePolicy.title)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isActive {
                    Text(L10n.text("Đang dùng"))
                        .font(.system(size: 10, weight: .bold))
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

    var emptyDetail: some View {
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
            .frame(maxWidth: .infinity, minHeight: 390, maxHeight: .infinity)
        }
    }

    var loadFailureCard: some View {
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
}
