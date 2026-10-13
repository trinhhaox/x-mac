import Cocoa
import ApplicationServices

public class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()
    
    @Published public var isAccessibilityGranted: Bool = false
    @Published public var isFullDiskAccessGranted: Bool = false
    
    private init() {
        checkPermissions()
    }
    
    public func checkPermissions() {
        self.isAccessibilityGranted = AXIsProcessTrusted()
        self.isFullDiskAccessGranted = checkFullDiskAccess()
    }
    
    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.isAccessibilityGranted = trusted
    }
    
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func checkFullDiskAccess() -> Bool {
        // Kiểm tra quyền đọc một thư mục nhạy cảm (như TCC database hoặc Safari Library)
        let testPath = ("~/Library/Safari" as NSString).expandingTildeInPath
        let fm = FileManager.default
        return fm.isReadableFile(atPath: testPath)
    }
}
