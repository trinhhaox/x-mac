import AppKit

/// Cache icon theo đường dẫn để tránh gọi NSWorkspace.icon(forFile:) lặp lại mỗi lần vẽ lại view.
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
    }

    func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
