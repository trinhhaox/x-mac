import Cocoa
import SwiftUI
import UserNotifications

public class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public static var shared: AppDelegate!
    
    public var mainWindow: NSWindow?
    
    override public init() {
        super.init()
        AppDelegate.shared = self
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Cấu hình Menu Bar
        DockIconManager.shared.apply()
        StatusBarController.shared.setup()
        
        // 2. Kiểm tra quyền và chỉ khởi động event tap khi được phép.
        PermissionsManager.shared.checkPermissions()

        // Nạp từ điển tiếng Anh trước, để lần tra đầu tiên lúc gõ không làm chậm event tap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            EnglishLexicon.warmUp()
        }
        
        DispatchQueue.global(qos: .utility).async {
            ConverterWorkspace.sweepStaleTempDirectories()
            BrowserDropCoordinator.sweepStaleScratch()
        }

        // 3. Yêu cầu quyền thông báo và định tuyến thao tác bấm thông báo
        NotificationRouter.shared.register()
        NSApp.servicesProvider = ConverterServiceProvider.shared
        NSUpdateDynamicServices()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                NSLog("Xmac Notification Auth error: \(error)")
            }
        }
        
        // 4. Mở cửa sổ chính khi lần đầu khởi động
        createMainWindow()
        AppUpdateManager.shared.start()
        QuickLauncher.shared.start()
        SmartProfilesManager.shared.start()
        ClipboardHistory.shared.start()
        DeduplicatorScheduler.shared.start()
        DonutController.shared.start()
        WatchFolderMonitor.shared.start()
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        // Người dùng có thể vừa cấp/thu hồi quyền trong System Settings.
        PermissionsManager.shared.checkPermissions()
        StatusBarController.shared.updateStatusBarTitle()
    }
    
    public func createMainWindow() {
        if let win = mainWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = MainView()
        let hostingController = NSHostingController(rootView: contentView)
        
        let visibleSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1060, height: 700)
        let contentSize = NSSize(
            width: min(1060, max(900, visibleSize.width - 24)),
            height: min(700, max(600, visibleSize.height - 24))
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("XmacMainWindow")
        window.setContentSize(contentSize)
        window.center()
        window.contentViewController = hostingController
        window.title = "Xmac"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        
        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Khi bấm nút X đỏ, chỉ ẩn cửa sổ để app tiếp tục chạy trên Menu Bar
        sender.orderOut(nil)
        return false
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            createMainWindow()
        }
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        GlobalEventTap.shared.stop()
        QuickLauncher.shared.stop()
        SmartProfilesManager.shared.stop()
        ClipboardHistory.shared.stop()
        DonutController.shared.stop()
        WatchFolderMonitor.shared.stop()
        DownloadsOrganizer.shared.stopWatching()
        DownloadManager.shared.shutdown()
        DownloadEnvironment.shared.stop()
        ConverterManager.shared.shutdown()
    }
}
