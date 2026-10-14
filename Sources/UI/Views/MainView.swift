import SwiftUI

public struct MainView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var ime = InputHookManager.shared
    @ObservedObject var permissions = PermissionsManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 228)

            Group {
                switch appState.selectedTab {
                case .overview: OverviewView()
                case .downloads: DownloadsView()
                case .fileSearch: FileSearchView()
                case .cutPaste: CutPasteView()
                case .diskNTFS: DiskNTFSView()
                case .vietnameseIME: VietnameseIMEView()
                case .junkCleaner: JunkCleanerView()
                case .appUninstaller: AppUninstallerView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(XmacTheme.workspaceBackground)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 42, height: 42)
                    .shadow(color: XmacTheme.cyan.opacity(0.28), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Xmac")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("CONTROL DECK")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.52))
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 24)

            Text("TIỆN ÍCH")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.42))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 5) {
                ForEach(NavigationTab.allCases) { tab in
                    sidebarButton(for: tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(spacing: 10) {
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
                            Text(
                                permissions.isAccessibilityGranted
                                    ? (ime.isVietnameseMode ? "Tiếng Việt" : "English")
                                    : "Cần Trợ năng"
                            )
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Control + Shift")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.46))
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .disabled(!permissions.isAccessibilityGranted)

                HStack {
                    Text("Xmac \(AppVersionInfo.current.version)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.38))
                    Spacer()
                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.58))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Thoát Xmac")
                }
            }
            .padding(14)
        }
        .background(XmacTheme.sidebarGradient.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
    }

    private func sidebarButton(for tab: NavigationTab) -> some View {
        let isSelected = appState.selectedTab == tab
        return Button(action: {
            withAnimation(.easeOut(duration: 0.22)) {
                appState.selectedTab = tab
            }
        }) {
            HStack(spacing: 11) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? XmacTheme.cyan : .white.opacity(0.58))
                    .frame(width: 22)
                Text(tab.rawValue)
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
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(isSelected ? .white.opacity(0.12) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(isSelected ? XmacTheme.cyan.opacity(0.18) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
