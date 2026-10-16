import Foundation
import SwiftUI

private final class LocalizationBundleToken: NSObject {}

public enum AppLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case english = "en"

    public var id: String { rawValue }
    public var locale: Locale { Locale(identifier: rawValue) }

    public var displayName: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        }
    }
}

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    private static let defaultsKey = "Xmac.AppLanguage"

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: .xmacLanguageDidChange, object: language)
        }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let language = AppLanguage(rawValue: stored) {
            self.language = language
        } else {
            self.language = .vietnamese
        }
    }
}

public enum L10n {
    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let selectedLanguage = language ?? LocalizationManager.shared.language
        guard let bundle = localizedBundle(for: selectedLanguage) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: LocalizationManager.shared.language.locale, arguments: arguments)
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle? {
        let bundles = [Bundle.main, Bundle(for: LocalizationBundleToken.self)] + Bundle.allBundles + Bundle.allFrameworks
        for base in bundles {
            if let path = base.path(forResource: language.rawValue, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
            if let resourceURL = base.resourceURL,
               let packageBundle = Bundle(url: resourceURL.appendingPathComponent("Xmac_Xmac.bundle")),
               let path = packageBundle.path(forResource: language.rawValue, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return nil
    }
}

public extension Notification.Name {
    static let xmacLanguageDidChange = Notification.Name("XmacLanguageDidChange")
}
