import AppKit
import UserNotifications

/// Select a screen region, OCR it on device, put the text on the clipboard.
@MainActor
final class ScreenTextCapture {
    static let shared = ScreenTextCapture()
    private static let launcherHideDelay: Duration = .milliseconds(200)
    private var isRunning = false

    /// Gives the launcher panel time to leave the screen before the selection overlay starts.
    func captureAfterDelay() {
        guard !isRunning else { return }
        isRunning = true
        Task {
            try? await Task.sleep(for: Self.launcherHideDelay)
            await run()
            isRunning = false
        }
    }

    private func run() async {
        guard ScreenTextRecognizer.isCaptureAvailable else {
            Self.notify(L10n.text("Không tìm thấy công cụ chụp màn hình của macOS"))
            return
        }
        guard Self.hasScreenAccess() else {
            Self.notifyPermissionNeeded()
            return
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("xmac-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await ProcessRunner.run(executable: ScreenTextRecognizer.screencapture,
                                            arguments: ScreenTextRecognizer.captureArguments(output: file))
            guard FileManager.default.fileExists(atPath: file.path) else { return }  // Esc: cancelled
            let outcome = try await Task.detached(priority: .userInitiated) { try Self.recognize(file) }.value
            finish(outcome)
        } catch {
            NSLog("ScreenTextCapture failed: \(error)")
            Self.notify(L10n.text("Không nhận được chữ từ vùng màn hình"))
        }
    }

    private enum Outcome { case text(String), blank }

    private nonisolated static func recognize(_ file: URL) throws -> Outcome {
        let image = try ImageIOSupport.loadImage(file, maxPixel: nil)
        if ScreenTextRecognizer.isBlank(image) { return .blank }
        return .text(try ScreenTextRecognizer.recognizeText(in: image))
    }

    private func finish(_ outcome: Outcome) {
        switch outcome {
        case .blank:
            Self.notifyPermissionNeeded()
        case .text(let text) where text.isEmpty:
            Self.notify(L10n.text("Không tìm thấy chữ"))
        case .text(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            SoundEffectManager.shared.play(.done)
            Self.notify(L10n.format("Đã chép %lld ký tự", Int64(text.count)))
        }
    }

    /// True when capture is allowed; otherwise asks macOS to show its permission prompt and returns false.
    nonisolated static func hasScreenAccess(
        preflight: () -> Bool = CGPreflightScreenCaptureAccess, request: () -> Bool = CGRequestScreenCaptureAccess
    ) -> Bool {
        if preflight() { return true }
        _ = request()
        return false
    }

    private static func notifyPermissionNeeded() {
        notify(L10n.text("Cần cấp quyền Ghi màn hình cho Xmac"),
               body: L10n.text("Mở Cài đặt hệ thống > Quyền riêng tư & Bảo mật > Ghi màn hình, bật Xmac rồi thử lại."))
    }

    private static func notify(_ title: String, body: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("ScreenTextCapture: notification failed: \(error)") }
        }
    }
}
