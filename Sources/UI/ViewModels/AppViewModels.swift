import Cocoa
import SwiftUI

public class DiskNTFSViewModel: ObservableObject {
    public static let shared = DiskNTFSViewModel()
    @Published public var mountStatusMessage: String? = nil
    @Published public var isProcessing: Bool = false
    private init() {}
}

public class VietnameseIMEViewModel: ObservableObject {
    public static let shared = VietnameseIMEViewModel()
    @Published public var newShortcut: String = ""
    @Published public var newExpansion: String = ""
    private init() {}
}

public class JunkCleanerViewModel: ObservableObject {
    public static let shared = JunkCleanerViewModel()
    @Published public var cleanResultText: String? = nil
    @Published public var expandedCategories: Set<String> = []
    @Published public var showCleanConfirmation: Bool = false
    
    private init() {}
    
    public func toggleExpand(categoryName: String) {
        if expandedCategories.contains(categoryName) {
            expandedCategories.remove(categoryName)
        } else {
            expandedCategories.insert(categoryName)
        }
    }
    
    public func isExpanded(categoryName: String) -> Bool {
        return expandedCategories.contains(categoryName)
    }
}

public class AppUninstallerViewModel: ObservableObject {
    public static let shared = AppUninstallerViewModel()
    @Published public var searchText: String = ""
    @Published public var selectedApp: InstalledAppItem? = nil
    @Published public var uninstallResultText: String? = nil
    @Published public var uninstallSucceeded: Bool = true
    @Published public var showConfirmAlert: Bool = false
    private init() {}
}

public class SettingsViewModel: ObservableObject {
    public static let shared = SettingsViewModel()
    @Published public var enableSoundEffects: Bool = true {
        didSet {
            UserDefaults.standard.set(enableSoundEffects, forKey: "EnableSoundEffects")
        }
    }
    
    private init() {
        if UserDefaults.standard.object(forKey: "EnableSoundEffects") != nil {
            self.enableSoundEffects = UserDefaults.standard.bool(forKey: "EnableSoundEffects")
        } else {
            self.enableSoundEffects = true
        }
    }
}
