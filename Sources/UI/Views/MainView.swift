import SwiftUI

public struct MainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var appState = AppState.shared
    @ObservedObject var ime = InputHookManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject private var localization = LocalizationManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 228)

            Group {
                switch appState.selectedTab {
                case .overview: OverviewView()
                case .systemMonitor: SystemMonitorView()
                case .downloads: DownloadsView()
                case .fileSearch: FileSearchView()
                case .clipboard: ClipboardHistoryView()
                case .organizer: DownloadsOrganizerView()
                case .cutPaste: CutPasteView()
                case .diskNTFS: DiskNTFSView()
                case .vietnameseIME: VietnameseIMEView()
                case .smartProfiles: SmartProfilesView()
                case .junkCleaner: JunkCleanerView()
                case .appUninstaller: AppUninstallerView()
                case .settings: SettingsView()
                }
            }
            // Top-aligned so short pages keep their header where every other page has it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(XmacTheme.workspaceBackground)
        }
        .frame(minWidth: 900, minHeight: 600)
        .environment(\.locale, localization.language.locale)
        .id(localization.language)
        .onChange(of: localization.language) { _ in
            appState.updateSystemStats()
        }
        .onAppear {
            appState.updateSystemStats()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .shadow(color: XmacTheme.cyan.opacity(0.28), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Xmac")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(L10n.text("BỘ CÔNG CỤ MAC"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.52))
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 14)

            ScrollView {
                // Rows stay compact so all 13 destinations fit the 600pt minimum
                // window; the scroll view is only a fallback for large text.
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sidebarSections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L10n.text(section.title))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(.white.opacity(0.62))
                                .padding(.horizontal, 10)
                                .padding(.bottom, 3)

                            ForEach(section.tabs) { tab in
                                sidebarButton(for: tab)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }

            VStack(spacing: 8) {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 1)

                Button(action: { ime.toggleLanguage() }) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(XmacTheme.cyan.opacity(0.16))
                            Text(permissions.isAccessibilityGranted ? (ime.isVietnameseMode ? "V" : "E") : "!")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(XmacTheme.cyan)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.text(
                                permissions.isAccessibilityGranted
                                    ? (ime.isVietnameseMode ? "Tiếng Việt" : "English")
                                    : "Cần Trợ năng"
                            ))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Control + Shift")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.62))
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .disabled(!permissions.isAccessibilityGranted)
                .accessibilityLabel(L10n.text(permissions.isAccessibilityGranted ? "Chuyển bộ gõ giữa Tiếng Việt và English" : "Bộ gõ cần quyền Trợ năng"))
                .accessibilityHint(L10n.text(permissions.isAccessibilityGranted ? "Nhấn để chuyển ngôn ngữ nhập" : "Mở mục Tổng quan để cấp quyền Trợ năng"))

                HStack(spacing: 4) {
                    sidebarButton(for: .settings)
                        .layoutPriority(1)
                    Text("Xmac \(L10n.text(AppVersionInfo.current.version))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.58))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("Thoát Xmac"))
                    .accessibilityLabel(L10n.text("Thoát Xmac"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(XmacTheme.sidebarGradient.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
    }

    private var sidebarSections: [(title: String, tabs: [NavigationTab])] {
        [
            ("TỔNG QUAN", [.overview, .systemMonitor]),
            ("CÔNG VIỆC", [.downloads, .fileSearch, .clipboard, .organizer]),
            ("HỆ THỐNG", [.cutPaste, .diskNTFS, .vietnameseIME, .smartProfiles, .junkCleaner, .appUninstaller])
        ]
    }

    private func sidebarButton(for tab: NavigationTab) -> some View {
        let isSelected = appState.selectedTab == tab
        return Button(action: {
            if reduceMotion {
                appState.selectedTab = tab
            } else {
                withAnimation(.easeOut(duration: 0.22)) {
                    appState.selectedTab = tab
                }
            }
        }) {
            HStack(spacing: 11) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? XmacTheme.cyan : .white.opacity(0.58))
                    .frame(width: 22)
                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.68))
                Spacer()
                if isSelected {
                    Circle()
                        .fill(XmacTheme.cyan)
                        .frame(width: 5, height: 5)
                        .shadow(color: XmacTheme.cyan, radius: 5)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 27)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? .white.opacity(0.12) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isSelected ? XmacTheme.cyan.opacity(0.18) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
