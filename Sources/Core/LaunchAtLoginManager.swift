import Cocoa
import ServiceManagement

public class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()
    
    @Published public var isEnabled: Bool = false
    
    private init() {
        checkStatus()
    }
    
    public func checkStatus() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
    
    public func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                isEnabled = enabled
            } catch {
                NSLog("Xmac LaunchAtLogin error: \(error)")
                checkStatus()
            }
        }
    }
}
