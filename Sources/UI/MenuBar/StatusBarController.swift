import Cocoa
import SwiftUI

public class StatusBarController: NSObject, NSMenuDelegate {
    public static let shared = StatusBarController()
    
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    
    override private init() {
        super.init()
    }
    
    public func setup() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu?.delegate = self
        statusItem?.menu = menu
        
        updateStatusBarTitle()
        
        // Đăng ký observer khi chế độ gõ hoặc số file cut thay đổi
        NotificationCenter.default.addObserver(self, selector: #selector(onStateChanged), name: UserDefaults.didChangeNotification, object: nil)
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
        
        var title = hasAccessibility
            ? (ime.isVietnameseMode ? "🇻🇳 V" : "🇺🇸 E")
            : "⚠︎ Xmac"
        if !cutPaste.cutFiles.isEmpty {
            title += " [✂︎\(cutPaste.cutFiles.count)]"
        }
        
        button.title = title
        button.toolTip = "Xmac - Tiện ích thiết yếu cho macOS"
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let ime = InputHookManager.shared
        let cutPaste = FinderCutPasteManager.shared
        let diskManager = DiskManager.shared
        let downloads = DownloadManager.shared
        let hasAccessibility = PermissionsManager.shared.isAccessibilityGranted
        
        // 1. Chuyển đổi ngôn ngữ gõ
        let langTitle = hasAccessibility
            ? (ime.isVietnameseMode ? "🇻🇳 Đang gõ: Tiếng Việt (Nhấn để đổi E)" : "🇺🇸 Đang gõ: Tiếng Anh (Nhấn để đổi V)")
            : "⚠ Bộ gõ cần quyền Trợ năng"
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
        let typingItem = NSMenuItem(title: "Kiểu gõ: \(ime.typingMethod.rawValue)", action: nil, keyEquivalent: "")
        typingItem.submenu = methodMenu
        menu.addItem(typingItem)
        
        menu.addItem(NSMenuItem.separator())

        let downloadTitle = downloads.activeCount > 0
            ? "↓ Tải xuống: \(downloads.activeCount) tác vụ đang chạy"
            : "↓ Mở Trung tâm tải xuống"
        let downloadItem = NSMenuItem(title: downloadTitle, action: #selector(openDownloads), keyEquivalent: "")
        downloadItem.target = self
        menu.addItem(downloadItem)

        let searchItem = NSMenuItem(title: "⌕ Tìm tệp nhanh", action: #selector(openFileSearch), keyEquivalent: "f")
        searchItem.keyEquivalentModifierMask = [.command, .option]
        searchItem.target = self
        menu.addItem(searchItem)

        menu.addItem(NSMenuItem.separator())
        
        // 2. Finder Cut & Paste
        let cutPasteTitle = hasAccessibility
            ? (cutPaste.isEnabled ? "✂︎ Finder Cut & Paste: Đang bật" : "✂︎ Finder Cut & Paste: Đã tắt")
            : "✂︎ Finder Cut & Paste: Cần quyền Trợ năng"
        let cutPasteItem = NSMenuItem(title: cutPasteTitle, action: #selector(toggleCutPaste), keyEquivalent: "")
        cutPasteItem.target = self
        cutPasteItem.state = hasAccessibility && cutPaste.isEnabled ? .on : .off
        cutPasteItem.isEnabled = hasAccessibility
        menu.addItem(cutPasteItem)
        
        if !cutPaste.cutFiles.isEmpty {
            let pasteNow = NSMenuItem(title: "   ↳ Dán \(cutPaste.cutFiles.count) tệp ngay (⌘V)", action: #selector(pasteNowAction), keyEquivalent: "")
            pasteNow.target = self
            menu.addItem(pasteNow)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Ổ đĩa ngoại vi & NTFS
        let extDisks = diskManager.volumes.filter { $0.isExternal }
        if !extDisks.isEmpty {
            let diskHeader = NSMenuItem(title: "Ổ cứng ngoại vi (\(extDisks.count)):", action: nil, keyEquivalent: "")
            diskHeader.isEnabled = false
            menu.addItem(diskHeader)
            
            for disk in extDisks {
                let fsText = disk.isNTFS ? "NTFS (\(disk.isWritable ? "R/W" : "Chỉ đọc"))" : disk.fileSystem
                let diskItem = NSMenuItem(title: "   • \(disk.name) - \(fsText)", action: #selector(openDiskAction(_:)), keyEquivalent: "")
                diskItem.target = self
                diskItem.representedObject = disk
                menu.addItem(diskItem)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        // 4. Quick Clean Memory
        let purgeItem = NSMenuItem(title: "⚡️ Giải phóng bộ nhớ RAM", action: #selector(purgeMemoryAction), keyEquivalent: "")
        purgeItem.target = self
        menu.addItem(purgeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Mở Dashboard
        let openItem = NSMenuItem(title: "Mở Bảng điều khiển Xmac...", action: #selector(openMainWindow), keyEquivalent: "m")
        openItem.target = self
        menu.addItem(openItem)

        let updateItem = NSMenuItem(title: "Kiểm tra cập nhật…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 6. Thoát
        let quitItem = NSMenuItem(title: "Thoát Xmac", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func checkForUpdates() {
        AppState.shared.selectedTab = .settings
        AppDelegate.shared.createMainWindow()
        Task { @MainActor in await AppUpdateManager.shared.check() }
    }

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
