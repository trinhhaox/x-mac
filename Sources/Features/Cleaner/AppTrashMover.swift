import Foundation

/// Chuyển một mục vào Thùng rác. App từ App Store / app iOS được cài với chủ sở hữu root,
/// và container của app sandbox được macOS bảo vệ, nên `FileManager.trashItem` báo
/// "không có quyền". Khi đó nhờ Finder xoá: Finder tự hỏi mật khẩu quản trị và giữ được "Đưa lại".
enum AppTrashMover {
    static func trash(_ url: URL, fileManager: FileManager = .default) throws {
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        } catch where isPermissionDenied(error) {
            try trashWithFinder(url, fileManager: fileManager)
        }
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
            return true
        }
        let posix = (nsError.domain == NSPOSIXErrorDomain ? nsError : nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
        guard let posix, posix.domain == NSPOSIXErrorDomain else { return false }
        return posix.code == Int(EACCES) || posix.code == Int(EPERM)
    }

    static func finderDeleteScript(path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"Finder\" to delete (POSIX file \"\(escaped)\" as alias)"
    }

    /// Chạy trên luồng AppleScript chung và chờ kết quả; người dùng có thể đang nhập mật khẩu.
    private static func trashWithFinder(_ url: URL, fileManager: FileManager) throws {
        var scriptError: NSDictionary?
        let done = DispatchSemaphore(value: 0)
        FinderScriptThread.shared.async {
            NSAppleScript(source: finderDeleteScript(path: url.path))?.executeAndReturnError(&scriptError)
            done.signal()
        }
        done.wait()

        if let scriptError {
            let code = scriptError[NSAppleScript.errorNumber] as? Int ?? -1
            let message = scriptError[NSAppleScript.errorMessage] as? String ?? "Finder could not move the item to the Trash."
            throw NSError(domain: "vn.xmac.trash", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
        if fileManager.fileExists(atPath: url.path) {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
