import Cocoa
import SwiftUI

public class StatusBarController: NSObject, NSMenuDelegate {
    public static let shared = StatusBarController()
    
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private let dashboard = NSPopover()
    
    override private init() {
        super.init()
    }
    
    public func setup() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu?.delegate = self
        dashboard.behavior = .transient
        let dashboardController = NSHostingController(rootView: MenuBarDashboard())
        dashboardController.sizingOptions = [.preferredContentSize]
        dashboard.contentViewController = dashboardController
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(toggleDashboard)
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        updateStatusBarTitle()
        
        // Đăng ký observer khi chế độ gõ hoặc số file cut thay đổi
        NotificationCenter.default.addObserver(self, selector: #selector(onStateChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    func closeDashboard() { dashboard.performClose(nil) }

    @objc private func toggleDashboard() {
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp, let menu {
            closeDashboard()
            menuWillOpen(menu)
            statusItem?.menu = menu
            button.performClick(nil)
            statusItem?.menu = nil
        } else if dashboard.isShown {
            closeDashboard()
        } else {
            QuickLauncher.shared.hide()
            PermissionsManager.shared.checkPermissions()
            DiskManager.shared.refreshVolumes()
            dashboard.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    @objc private func onStateChanged() {
        DispatchQueue.main.async {
            self.updateStatusBarTitle()
        }
    }
    
    public func updateStatusBarTitle() {
        guard let button = statusItem?.button else { return }
        
        let ime = InputHookManager.shared
        let cutPaste = FinderCutPasteManager.shared
        let hasAccessibility = PermissionsManager.shared.isAccessibilityGranted
        let smartProfiles = SmartProfilesManager.shared
        let effectiveIME = smartProfiles.effectiveConfiguration(
            for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            globalVietnameseMode: ime.isVietnameseMode,
            globalTypingMethod: ime.typingMethod,
            globalMacrosEnabled: MacroManager.shared.isMacroEnabled
        )
        
        var title = hasAccessibility
            ? (effectiveIME.isVietnameseMode ? "🇻🇳 V" : "🇺🇸 E")
            : "⚠︎ Xmac"
        if smartProfiles.activeProfile != nil {
            title += " •"
        }
        if !cutPaste.cutFiles.isEmpty {
            title += " [✂︎\(cutPaste.cutFiles.count)]"
        }
        
        button.title = title
        button.toolTip = L10n.text("Xmac - Tiện ích thiết yếu cho macOS")
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let launcherItem = NSMenuItem(title: L10n.format("Mở nhanh Xmac (%@)", QuickLauncher.shared.shortcut.title), action: #selector(openLauncher), keyEquivalent: "")
        launcherItem.target = self
        menu.addItem(launcherItem)
        menu.addItem(NSMenuItem.separator())
        
        let ime = InputHookManager.shared
        let cutPaste = FinderCutPasteManager.shared
        let diskManager = DiskManager.shared
        let downloads = DownloadManager.shared
        let hasAccessibility = PermissionsManager.shared.isAccessibilityGranted
        
        // 1. Chuyển đổi ngôn ngữ gõ
        let langTitle = hasAccessibility
            ? (ime.isVietnameseMode ? L10n.text("🇻🇳 Đang gõ: Tiếng Việt (Nhấn để đổi E)") : L10n.text("🇺🇸 Đang gõ: Tiếng Anh (Nhấn để đổi V)"))
            : L10n.text("⚠ Bộ gõ cần quyền Trợ năng")
        let langItem = NSMenuItem(title: langTitle, action: #selector(toggleLanguage), keyEquivalent: "")
        langItem.target = self
        langItem.isEnabled = hasAccessibility
        menu.addItem(langItem)
        
        // Submenu chọn kiểu gõ
        let methodMenu = NSMenu()
        for method in TypingMethod.allCases {
            let item = NSMenuItem(title: method.rawValue, action: #selector(changeTypingMethod(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = method
            item.state = (ime.typingMethod == method) ? .on : .off
            methodMenu.addItem(item)
        }
        let typingItem = NSMenuItem(title: L10n.format("Kiểu gõ: %@", ime.typingMethod.rawValue), action: nil, keyEquivalent: "")
        typingItem.submenu = methodMenu
        menu.addItem(typingItem)

        let smartProfiles = SmartProfilesManager.shared
        let profileTitle = smartProfiles.isEnabled
            ? L10n.text("Smart Profiles: Đang bật")
            : L10n.text("Smart Profiles: Đã tạm dừng")
        let profileItem = NSMenuItem(title: profileTitle, action: #selector(toggleSmartProfiles), keyEquivalent: "")
        profileItem.target = self
        profileItem.state = smartProfiles.isEnabled ? .on : .off
        menu.addItem(profileItem)

        let manageProfilesItem = NSMenuItem(title: L10n.text("Quản lý Smart Profiles…"), action: #selector(openSmartProfiles), keyEquivalent: "")
        manageProfilesItem.target = self
        menu.addItem(manageProfilesItem)
        
        menu.addItem(NSMenuItem.separator())

        let downloadTitle = downloads.activeCount > 0
            ? L10n.format("↓ Tải xuống: %lld tác vụ đang chạy", Int64(downloads.activeCount))
            : L10n.text("↓ Mở Trung tâm tải xuống")
        let downloadItem = NSMenuItem(title: downloadTitle, action: #selector(openDownloads), keyEquivalent: "")
        downloadItem.target = self
        menu.addItem(downloadItem)

        let searchItem = NSMenuItem(title: L10n.text("⌕ Tìm tệp nhanh"), action: #selector(openFileSearch), keyEquivalent: "f")
        searchItem.keyEquivalentModifierMask = [.command, .option]
        searchItem.target = self
        menu.addItem(searchItem)

        menu.addItem(NSMenuItem.separator())
        
        // 2. Finder Cut & Paste
        let cutPasteTitle = hasAccessibility
            ? (cutPaste.isEnabled ? L10n.text("✂︎ Finder Cut & Paste: Đang bật") : L10n.text("✂︎ Finder Cut & Paste: Đã tắt"))
            : L10n.text("✂︎ Finder Cut & Paste: Cần quyền Trợ năng")
        let cutPasteItem = NSMenuItem(title: cutPasteTitle, action: #selector(toggleCutPaste), keyEquivalent: "")
        cutPasteItem.target = self
        cutPasteItem.state = hasAccessibility && cutPaste.isEnabled ? .on : .off
        cutPasteItem.isEnabled = hasAccessibility
        menu.addItem(cutPasteItem)
        
        if !cutPaste.cutFiles.isEmpty {
            let pasteNow = NSMenuItem(title: L10n.format("   ↳ Dán %lld tệp ngay (⌘V)", Int64(cutPaste.cutFiles.count)), action: #selector(pasteNowAction), keyEquivalent: "")
            pasteNow.target = self
            menu.addItem(pasteNow)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Ổ đĩa ngoại vi & NTFS
        let extDisks = diskManager.volumes.filter { $0.isExternal }
        if !extDisks.isEmpty {
            let diskHeader = NSMenuItem(title: L10n.format("Ổ cứng ngoại vi (%lld):", Int64(extDisks.count)), action: nil, keyEquivalent: "")
            diskHeader.isEnabled = false
            menu.addItem(diskHeader)
            
            for disk in extDisks {
                let fsText = disk.isNTFS ? "NTFS (\(disk.isWritable ? "R/W" : L10n.text("Chỉ đọc")))" : disk.fileSystem
                let diskItem = NSMenuItem(title: "   • \(disk.name) - \(fsText)", action: #selector(openDiskAction(_:)), keyEquivalent: "")
                diskItem.target = self
                diskItem.representedObject = disk
                diskItem.isEnabled = disk.isMounted
                menu.addItem(diskItem)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        // 4. Quick Clean Memory
        let purgeItem = NSMenuItem(title: L10n.text("⚡️ Giải phóng bộ nhớ RAM"), action: #selector(purgeMemoryAction), keyEquivalent: "")
        purgeItem.target = self
        menu.addItem(purgeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Mở Dashboard
        let openItem = NSMenuItem(title: L10n.text("Mở Bảng điều khiển Xmac..."), action: #selector(openMainWindow), keyEquivalent: "m")
        openItem.target = self
        menu.addItem(openItem)

        let updateItem = NSMenuItem(title: L10n.text("Kiểm tra cập nhật…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 6. Thoát
        let quitItem = NSMenuItem(title: L10n.text("Thoát Xmac"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func checkForUpdates() {
        AppState.shared.selectedTab = .settings
        AppDelegate.shared.createMainWindow()
        Task { @MainActor in await AppUpdateManager.shared.check() }
    }

    @objc private func openLauncher() { QuickLauncher.shared.show() }

    @objc private func toggleLanguage() {
        InputHookManager.shared.toggleLanguage()
        updateStatusBarTitle()
    }
    
    @objc private func changeTypingMethod(_ sender: NSMenuItem) {
        if let method = sender.representedObject as? TypingMethod {
            InputHookManager.shared.typingMethod = method
        }
    }
    
    @objc private func toggleCutPaste() {
        FinderCutPasteManager.shared.isEnabled.toggle()
        updateStatusBarTitle()
    }

    @objc private func toggleSmartProfiles() {
        SmartProfilesManager.shared.setEnabled(!SmartProfilesManager.shared.isEnabled)
    }

    @objc private func openSmartProfiles() {
        AppState.shared.selectedTab = .smartProfiles
        openMainWindow()
    }
    
    @objc private func pasteNowAction() {
        _ = FinderCutPasteManager.shared.handlePaste()
        updateStatusBarTitle()
    }
    
    @objc private func openDiskAction(_ sender: NSMenuItem) {
        if let disk = sender.representedObject as? DiskVolume {
            NTFSMountHelper.shared.openInFinder(volume: disk)
        }
    }
    
    @objc private func purgeMemoryAction() {
        CleanerEngine.shared.purgeMemory()
    }

    @objc private func openDownloads() {
        AppState.shared.selectedTab = .downloads
        openMainWindow()
    }

    @objc private func openFileSearch() {
        AppState.shared.selectedTab = .fileSearch
        openMainWindow()
    }
    
    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Xmac" || $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            AppDelegate.shared.createMainWindow()
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
