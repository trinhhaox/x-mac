import SwiftUI

public struct MainView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var ime = InputHookManager.shared
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 6) {
                // App Logo / Title in Sidebar
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 28, height: 28)
                    Text("Xmac")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
                // Tabs List
                List(NavigationTab.allCases, selection: $appState.selectedTab) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.rawValue, systemImage: tab.iconName)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .listStyle(.sidebar)
                
                Spacer()
                
                // Sidebar Footer Quick Widget
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        Button(action: {
                            ime.toggleLanguage()
                        }) {
                            HStack(spacing: 6) {
                                Text(ime.isVietnameseMode ? "🇻🇳 Tiếng Việt" : "🇺🇸 Tiếng Anh")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(ime.isVietnameseMode ? "(V)" : "(E)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button(action: {
                            NSApplication.shared.terminate(nil)
                        }) {
                            Image(systemName: "power")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Thoát Xmac")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // Content detail
            Group {
                switch appState.selectedTab {
                case .overview:
                    OverviewView()
                case .cutPaste:
                    CutPasteView()
                case .diskNTFS:
                    DiskNTFSView()
                case .vietnameseIME:
                    VietnameseIMEView()
                case .junkCleaner:
                    JunkCleanerView()
                case .appUninstaller:
                    AppUninstallerView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(minWidth: 540, minHeight: 460)
        }
    }
}
