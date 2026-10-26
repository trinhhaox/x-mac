import Cocoa
import UserNotifications

/// Routes notification clicks: `paths` reveals files in Finder, `tab` opens that tab.
public final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationRouter()

    public static let categoryIdentifier = "XMAC_FILE_RESULT"
    static let revealActionIdentifier = "XMAC_REVEAL_IN_FINDER"

    public enum Action: Equatable {
        case reveal([URL])
        case openTab(NavigationTab)
    }

    private override init() { super.init() }

    /// Wires the delegate and the "Hiện trong Finder" category; call once at launch.
    public func register(center: UNUserNotificationCenter = .current()) {
        center.delegate = self
        let reveal = UNNotificationAction(
            identifier: Self.revealActionIdentifier,
            title: L10n.text("Hiện trong Finder"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [reveal],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// `paths` takes precedence over `tab`; malformed or empty values yield nil.
    public static func action(for userInfo: [AnyHashable: Any]) -> Action? {
        if let paths = userInfo["paths"] as? [String] {
            let urls = paths.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty { return .reveal(urls) }
        }
        if let raw = userInfo["tab"] as? String, let tab = NavigationTab(rawValue: raw) {
            return .openTab(tab)
        }
        return nil
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        if identifier == Self.revealActionIdentifier || identifier == UNNotificationDefaultActionIdentifier,
           let action = Self.action(for: userInfo) {
            DispatchQueue.main.async { Self.perform(action) }
        }
        completionHandler()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private static func perform(_ action: Action) {
        switch action {
        case .reveal(let urls):
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .openTab(let tab):
            AppState.shared.selectedTab = tab
            AppDelegate.shared.createMainWindow()
        }
    }
}
