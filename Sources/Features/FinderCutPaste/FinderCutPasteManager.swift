import Cocoa
import UserNotifications

public class FinderCutPasteManager: ObservableObject {
    public static let shared = FinderCutPasteManager()
    
    @Published public var cutFiles: [String] = []
    @Published public var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "CutPasteEnabled")
        }
    }
    
    private init() {
        if UserDefaults.standard.object(forKey: "CutPasteEnabled") != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: "CutPasteEnabled")
        } else {
            self.isEnabled = true
        }
    }
    
    public func handleCut() -> Bool {
        guard isEnabled else { return false }
        let selected = FinderBridge.getSelectedFiles()
        guard !selected.isEmpty else { return false }
        
        self.cutFiles = selected
        SoundEffectManager.shared.play(.cut)
        
        let count = selected.count
        let title = "Đã cắt \(count) mục"
        let subtitle = count == 1 ? (selected.first as NSString?)?.lastPathComponent ?? "" : "Sẵn sàng để dán (⌘V)"
        sendNotification(title: title, body: subtitle)
        return true
    }
    
    public func handlePaste() -> Bool {
        guard isEnabled, !cutFiles.isEmpty else { return false }
        guard let currentFolder = FinderBridge.getCurrentFolder() else { return false }
        
        let filesToMove = self.cutFiles
        self.cutFiles.removeAll()
        
        let moved = FileMover.shared.moveFiles(sources: filesToMove, destinationFolder: currentFolder)
        if !moved.isEmpty {
            SoundEffectManager.shared.play(.paste)
            let count = moved.count
            sendNotification(
                title: "Đã di chuyển \(count) mục",
                body: "Đến: \((currentFolder as NSString).lastPathComponent)"
            )
            return true
        }
        return false
    }
    
    public func handleUndo() -> Bool {
        guard isEnabled, FileMover.shared.canUndo else { return false }
        let count = FileMover.shared.undoLastMove()
        if count > 0 {
            SoundEffectManager.shared.play(.undo)
            sendNotification(title: "Đã hoàn tác", body: "Đã trả \(count) mục về vị trí ban đầu")
            return true
        }
        return false
    }
    
    public func handleCopy() {
        // Hủy trạng thái cut nếu người dùng copy file khác
        if !cutFiles.isEmpty {
            cutFiles.removeAll()
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil // Dùng âm thanh tuỳ chỉnh của SoundEffectManager
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
