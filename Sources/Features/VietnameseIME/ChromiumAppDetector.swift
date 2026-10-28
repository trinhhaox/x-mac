import Foundation

/// Recognises apps whose text fields run on Chromium: Electron apps, Chromium
/// browsers and browser PWAs. Their editors map one key event to one input
/// event, so they need the paced single-character replacement. A fixed bundle
/// list missed most of them (Claude, Postman, Cursor, Chrome PWAs, ...).
enum ChromiumAppDetector {
    /// Chrome, Edge and Brave PWAs run in shims named `<browser id>.app.<hash>`.
    private static let progressiveWebAppPrefixes = [
        "com.google.Chrome.app.", "com.microsoft.edgemac.app.", "com.brave.Browser.app."
    ]

    static func isProgressiveWebApp(bundleIdentifier: String) -> Bool {
        progressiveWebAppPrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }

    /// Every Chromium app ships Electron/CEF or a "<Name> Helper (Renderer)"
    /// process next to its frameworks. A bundle without Frameworks is native.
    static func bundleUsesChromium(at bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks").path
        guard let entries = try? fileManager.contentsOfDirectory(atPath: frameworks) else { return false }
        return entries.contains { name in
            name == "Electron Framework.framework"
                || name == "Chromium Embedded Framework.framework"
                || name.hasSuffix(" Helper (Renderer).app")
        }
    }
}
