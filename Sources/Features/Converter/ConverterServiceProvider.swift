import AppKit

/// Receives files from Finder's right-click › Services › "Chuyển đổi bằng Xmac".
final class ConverterServiceProvider: NSObject {
    static let shared = ConverterServiceProvider()
    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    private override init() { super.init() }

    /// Both `public.file-url` items and the legacy filenames list (still sent by some file managers), deduplicated in order.
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let modern = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let legacy = (pasteboard.propertyList(forType: legacyFilenamesType) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
        var seen = Set<URL>()
        return (modern + legacy).map(\.standardizedFileURL).filter { seen.insert($0).inserted }
    }

    @objc func convertFiles(
        _ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        let urls = Self.fileURLs(from: pboard)
        guard !urls.isEmpty else {
            error?.pointee = L10n.text("Không đọc được tệp") as NSString
            return
        }
        let point = NSEvent.mouseLocation
        Task { @MainActor in ConverterTargetPanel.shared.show(urls: urls, near: point) }
    }
}
