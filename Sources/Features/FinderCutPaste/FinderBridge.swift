import Cocoa

public struct FinderBridge {
    public static func isFinderActive() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return app.bundleIdentifier == "com.apple.finder"
    }
    
    public static func getSelectedFiles() -> [String] {
        let script = """
        tell application "Finder"
            set selectedItems to selection
            set filePaths to {}
            repeat with anItem in selectedItems
                set end of filePaths to POSIX path of (anItem as alias)
            end repeat
            return filePaths
        end tell
        """
        return runAppleScript(script)
    }
    
    public static func getCurrentFolder() -> String? {
        let script = """
        tell application "Finder"
            try
                return POSIX path of (insertion location as alias)
            on error
                return POSIX path of (path to desktop folder)
            end try
        end tell
        """
        let results = runAppleScript(script)
        return results.first
    }
    
    public static func isRenamingFile() -> Bool {
        // Kiểm tra xem Finder có đang focus vào text field (đổi tên file) hay không
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.apple.finder" else {
            return false
        }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            return false
        }
        
        let axElement = element as! AXUIElement
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        
        if roleResult == .success, let role = roleValue as? String {
            if role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String) {
                return true
            }
        }
        
        return false
    }
    
    private static func runAppleScript(_ source: String) -> [String] {
        guard let script = NSAppleScript(source: source) else { return [] }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        
        if let error = error {
            NSLog("Xmac AppleScript error: \(error)")
            return []
        }
        
        if result.numberOfItems > 0 {
            var paths: [String] = []
            for i in 1...result.numberOfItems {
                if let item = result.atIndex(i) {
                    paths.append(item.stringValue ?? "")
                }
            }
            return paths.filter { !$0.isEmpty }
        }
        
        if let str = result.stringValue, !str.isEmpty {
            return [str]
        }
        
        return []
    }
}
