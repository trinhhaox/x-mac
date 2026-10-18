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
    private var cutPasteboardChange: Int?

    private init() {
        if UserDefaults.standard.object(forKey: "CutPasteEnabled") != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: "CutPasteEnabled")
        } else {
            self.isEnabled = true
        }
    }
    
    /// Called from the event tap: must return immediately. Finder is queried on
    /// `FinderScriptThread`, and results are applied back on the main queue.
    public func handleCut() -> Bool {
        guard isEnabled else { return false }
        let sessionID = UUID()
        cutSessionID = sessionID
        cutFiles.removeAll()
        // Xmac never writes the pasteboard during a cut, so any later change
        // means the user copied something else (menu, other app).
        let pasteboardChange = NSPasteboard.general.changeCount

        FinderScriptThread.shared.async {
            let selected = FinderBridge.getSelectedFiles()
            DispatchQueue.main.async {
                self.finishCut(selected: selected, sessionID: sessionID, pasteboardChange: pasteboardChange)
            }
        }
        return true
    }

    private func finishCut(selected: [String], sessionID: UUID, pasteboardChange: Int) {
        guard cutSessionID == sessionID else { return }
        guard !selected.isEmpty else {
            cutSessionID = nil
            return
        }
        cutFiles = selected
        cutPasteboardChange = pasteboardChange
        SoundEffectManager.shared.play(.cut)

        let count = selected.count
        let title = L10n.format("Đã cắt %lld mục", Int64(count))
        let subtitle = count == 1
            ? (selected.first as NSString?)?.lastPathComponent ?? ""
            : L10n.text("Sẵn sàng để dán (⌘V)")
        sendNotification(title: title, body: subtitle)
    }

    /// A pending cut (selection still being read) also claims ⌘V. The script
    /// thread is serial, so this paste's Finder query finishes after the cut's,
    /// and its main-queue completion sees the final `cutFiles`.
    public func handlePaste() -> Bool {
        guard isEnabled, cutSessionID != nil else { return false }
        if isMoveInProgress { return true }
        if cutIsStale() {
            discardCut()
            return false // Let Finder paste what the user copied later.
        }
        isMoveInProgress = true

        FinderScriptThread.shared.async {
            let folder = FinderBridge.getCurrentFolder()
            DispatchQueue.main.async {
                self.performPaste(into: folder)
            }
        }
        return true
    }

    private func performPaste(into folder: String?) {
        let filesToMove = cutFiles
        let sessionID = cutSessionID
        guard sessionID != nil, !filesToMove.isEmpty else {
            // The pending cut came back empty: hand the swallowed ⌘V to Finder.
            isMoveInProgress = false
            replayFinderPaste()
            return
        }
        if cutIsStale() {
            discardCut()
            isMoveInProgress = false
            replayFinderPaste()
            return
        }
        guard let currentFolder = folder else {
            isMoveInProgress = false
            sendNotification(
                title: L10n.text("Không thể dán"),
                body: L10n.text("Không xác định được thư mục đích trong Finder.")
            )
            return
        }

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
                        title: L10n.text("Không có mục nào được di chuyển"),
                        body: L10n.text("Danh sách cắt được giữ lại để bạn thử lại.")
                    )
                    return
                }

                SoundEffectManager.shared.play(.paste)
                let failedCount = filesToMove.count - moved.count
                let body = failedCount == 0
                    ? L10n.format("Đến: %@", (currentFolder as NSString).lastPathComponent)
                    : L10n.format("Còn %lld mục chưa di chuyển; bạn có thể thử lại.", Int64(failedCount))
                self.sendNotification(title: L10n.format("Đã di chuyển %lld mục", Int64(moved.count)), body: body)
            }
        }
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
                        ? L10n.format("Đã trả %lld mục; một số mục chưa thể hoàn tác.", Int64(count))
                        : L10n.format("Đã trả %lld mục về vị trí ban đầu", Int64(count))
                    self.sendNotification(title: L10n.text("Đã hoàn tác"), body: body)
                } else if hasFailures {
                    self.sendNotification(
                        title: L10n.text("Chưa thể hoàn tác"),
                        body: L10n.text("Trạng thái undo được giữ lại để bạn thử lại.")
                    )
                }
            }
        }
        return true
    }
    
    public func handleCopy() {
        // Hủy trạng thái cut nếu người dùng copy file khác
        discardCut()
    }

    private func cutIsStale() -> Bool {
        guard let recorded = cutPasteboardChange else { return false }
        return NSPasteboard.general.changeCount != recorded
    }

    private func discardCut() {
        cutSessionID = nil
        cutPasteboardChange = nil
        cutFiles.removeAll()
    }
    
    /// Re-posts ⌘V once Xmac holds no cut, so the event tap lets it through to Finder.
    private func replayFinderPaste() {
        guard cutSessionID == nil, FinderBridge.isFinderActive() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
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
