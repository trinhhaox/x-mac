import Cocoa

/// Shows or hides the Dock icon. Xmac lives in the menu bar, so the icon is
/// hidden by default (LSUIElement); turning it on switches to a regular app.
public final class DockIconManager: ObservableObject {
    public static let shared = DockIconManager()

    private static let key = "XmacShowDockIcon"
    private let defaults: UserDefaults

    @Published public var showsDockIcon: Bool {
        didSet {
            defaults.set(showsDockIcon, forKey: Self.key)
            apply()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsDockIcon = defaults.bool(forKey: Self.key)
    }

    public func apply() {
        let policy: NSApplication.ActivationPolicy = showsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let visibleWindows = NSApp.windows.filter(\.isVisible)
        NSApp.setActivationPolicy(policy)
        // Changing policy deactivates the app; keep an open Xmac window in front.
        if !visibleWindows.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            visibleWindows.forEach { $0.orderFrontRegardless() }
        }
    }
}
