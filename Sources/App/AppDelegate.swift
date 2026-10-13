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
        StatusBarController.shared.setup()
        
        // 2. Khởi động các Engine nền
        GlobalEventTap.shared.start()
        
        // 3. Yêu cầu quyền thông báo
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                NSLog("Xmac Notification Auth error: \(error)")
            }
        }
        
        // 4. Mở cửa sổ chính khi lần đầu khởi động
        createMainWindow()
        
        // 5. Kiểm tra quyền Accessibility
        PermissionsManager.shared.checkPermissions()
    }
    
    public func createMainWindow() {
        if let win = mainWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = MainView()
        let hostingController = NSHostingController(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.setFrameAutosaveName("XmacMainWindow")
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
    }
}
