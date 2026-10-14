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
    @Published public private(set) var isMoveInProgress: Bool = false

    private let operationQueue = DispatchQueue(label: "vn.xmac.finder-file-operations", qos: .userInitiated)
    private var cutSessionID: UUID?
    
    private init() {
        if UserDefaults.standard.object(forKey: "CutPasteEnabled") != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: "CutPasteEnabled")
        } else {
            self.isEnabled = true
        }
    }
    
    public func handleCut() -> Bool {
        guard isEnabled else { return false }
        let sessionID = UUID()
        cutSessionID = sessionID
        cutFiles.removeAll()

        // NSAppleScript is not thread-safe. Query Finder on the event tap's main
        // run loop, then reserve the operation queue for actual file I/O.
        let selected = FinderBridge.getSelectedFiles()
        guard cutSessionID == sessionID else { return true }
        guard !selected.isEmpty else {
            cutSessionID = nil
            cutFiles.removeAll()
            return true
        }
        cutFiles = selected
        SoundEffectManager.shared.play(.cut)

        let count = selected.count
        let title = "Đã cắt \(count) mục"
        let subtitle = count == 1
            ? (selected.first as NSString?)?.lastPathComponent ?? ""
            : "Sẵn sàng để dán (⌘V)"
        sendNotification(title: title, body: subtitle)
        return true
    }
    
    public func handlePaste() -> Bool {
        guard isEnabled, !cutFiles.isEmpty else { return false }
        if isMoveInProgress { return true }

        guard let currentFolder = FinderBridge.getCurrentFolder() else {
            sendNotification(
                title: "Không thể dán",
                body: "Không xác định được thư mục đích trong Finder."
            )
            return true
        }

        let filesToMove = cutFiles
        let sessionID = cutSessionID
        isMoveInProgress = true

        operationQueue.async {
            let moved = FileMover.shared.moveFiles(
                sources: filesToMove,
                destinationFolder: currentFolder
            )
            let movedSources = Set(moved.map(\.originalPath))

            DispatchQueue.main.async {
                self.isMoveInProgress = false
                if self.cutSessionID == sessionID {
                    self.cutFiles.removeAll { movedSources.contains($0) }
                    if self.cutFiles.isEmpty {
                        self.cutSessionID = nil
                    }
                }

                guard !moved.isEmpty else {
                    self.sendNotification(
                        title: "Không có mục nào được di chuyển",
                        body: "Danh sách cắt được giữ lại để bạn thử lại."
                    )
                    return
                }

                SoundEffectManager.shared.play(.paste)
                let failedCount = filesToMove.count - moved.count
                let body = failedCount == 0
                    ? "Đến: \((currentFolder as NSString).lastPathComponent)"
                    : "Còn \(failedCount) mục chưa di chuyển; bạn có thể thử lại."
                self.sendNotification(title: "Đã di chuyển \(moved.count) mục", body: body)
            }
        }
        return true
    }
    
    public func handleUndo() -> Bool {
        guard isEnabled, FileMover.shared.canUndo else { return false }
        if isMoveInProgress { return true }

        isMoveInProgress = true
        operationQueue.async {
            let count = FileMover.shared.undoLastMove()
            let hasFailures = FileMover.shared.canUndo
            DispatchQueue.main.async {
                self.isMoveInProgress = false
                if count > 0 {
                    SoundEffectManager.shared.play(.undo)
                    let body = hasFailures
                        ? "Đã trả \(count) mục; một số mục chưa thể hoàn tác."
                        : "Đã trả \(count) mục về vị trí ban đầu"
                    self.sendNotification(title: "Đã hoàn tác", body: body)
                } else if hasFailures {
                    self.sendNotification(
                        title: "Chưa thể hoàn tác",
                        body: "Trạng thái undo được giữ lại để bạn thử lại."
                    )
                }
            }
        }
        return true
    }
    
    public func handleCopy() {
        // Hủy trạng thái cut nếu người dùng copy file khác
        cutSessionID = nil
        cutFiles.removeAll()
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
