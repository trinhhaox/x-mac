import AppKit
import Foundation

public enum SmartProfileIMEPolicy: String, Codable, CaseIterable, Identifiable {
    case inherit
    case vietnamese
    case english

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inherit: return L10n.text("Kế thừa")
        case .vietnamese: return L10n.text("Tiếng Việt")
        case .english: return L10n.text("Tiếng Anh")
        }
    }
}

public enum SmartProfileTypingPolicy: String, Codable, CaseIterable, Identifiable {
    case inherit
    case telex
    case vni
    case simpleTelex

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inherit: return L10n.text("Kế thừa")
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .simpleTelex: return "Simple Telex"
        }
    }

    public var typingMethod: TypingMethod? {
        switch self {
        case .inherit: return nil
        case .telex: return .telex
        case .vni: return .vni
        case .simpleTelex: return .simpleTelex
        }
    }
}

public enum SmartProfileTogglePolicy: String, Codable, CaseIterable, Identifiable {
    case inherit
    case enabled
    case disabled

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inherit: return L10n.text("Kế thừa")
        case .enabled: return L10n.text("Bật")
        case .disabled: return L10n.text("Tắt")
        }
    }
}

public enum SmartProfileClipboardPolicy: String, Codable, CaseIterable, Identifiable {
    case inherit
    case allow
    case block

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inherit: return L10n.text("Kế thừa")
        case .allow: return L10n.text("Cho phép")
        case .block: return L10n.text("Chặn")
        }
    }
}

public struct SmartAppProfile: Codable, Identifiable, Equatable {
    public var id: String { bundleIdentifier }
    public var displayName: String
    public var bundleIdentifier: String
    public var applicationURLPath: String?
    public var imePolicy: SmartProfileIMEPolicy
    public var typingPolicy: SmartProfileTypingPolicy
    public var macroPolicy: SmartProfileTogglePolicy
    public var clipboardPolicy: SmartProfileClipboardPolicy

    public init(
        displayName: String,
        bundleIdentifier: String,
        applicationURLPath: String? = nil,
        imePolicy: SmartProfileIMEPolicy = .inherit,
        typingPolicy: SmartProfileTypingPolicy = .inherit,
        macroPolicy: SmartProfileTogglePolicy = .inherit,
        clipboardPolicy: SmartProfileClipboardPolicy = .inherit
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.applicationURLPath = applicationURLPath
        self.imePolicy = imePolicy
        self.typingPolicy = typingPolicy
        self.macroPolicy = macroPolicy
        self.clipboardPolicy = clipboardPolicy
    }
}

public struct SmartProfileApplication: Identifiable, Equatable {
    public var id: String { bundleIdentifier }
    public let displayName: String
    public let bundleIdentifier: String
    public let applicationURLPath: String?
    public let isRunning: Bool
}

public struct SmartProfileEffectiveConfiguration: Equatable {
    public let isVietnameseMode: Bool
    public let typingMethod: TypingMethod
    public let macrosEnabled: Bool
}

public final class SmartProfilesManager: ObservableObject {
    public static let shared = SmartProfilesManager(observeWorkspace: false)

    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var profiles: [SmartAppProfile]
    @Published public private(set) var activeBundleIdentifier: String?
    @Published public private(set) var availableApplications: [SmartProfileApplication] = []
    @Published public private(set) var loadFailed = false

    private let defaults: UserDefaults
    private let enabledKey = "SmartProfiles.Enabled"
    private let profilesKey = "SmartProfiles.Profiles"
    let unreadableBackupKey = "SmartProfiles.Profiles.unreadableBackup"
    private var activationObserver: NSObjectProtocol?

    public var activeProfile: SmartAppProfile? {
        guard isEnabled, let activeBundleIdentifier else { return nil }
        return profile(for: activeBundleIdentifier)
    }

    init(defaults: UserDefaults = .standard, observeWorkspace: Bool = false) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: enabledKey) == nil
            ? true
            : defaults.bool(forKey: enabledKey)

        if let data = defaults.data(forKey: profilesKey) {
            let decoded = Self.decodeLossy(data)
            self.profiles = decoded.profiles
            if decoded.hadFailures {
                // Giữ bản gốc để không bị ghi đè khi lưu lần đầu
                // Một bản sao lưu cũ khác nội dung được giữ nguyên; bản mới lưu
                // thêm khóa có dấu thời gian để không mất dữ liệu của lần lỗi trước.
                let existing = defaults.data(forKey: unreadableBackupKey)
                if existing == nil {
                    defaults.set(data, forKey: unreadableBackupKey)
                } else if existing != data {
                    let stamp = Int(Date().timeIntervalSince1970)
                    defaults.set(data, forKey: "\(unreadableBackupKey).\(stamp)")
                }
                self.loadFailed = true
            }
        } else {
            self.profiles = []
        }

        if observeWorkspace {
            start()
        }
    }

    deinit {
        stop()
    }

    public func start() {
        guard activationObserver == nil else { return }
        updateActiveApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateActiveApplication(application)
        }
        refreshAvailableApplications()
    }

    public func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        StatusBarController.shared.updateStatusBarTitle()
    }

    public func profile(for bundleIdentifier: String) -> SmartAppProfile? {
        profiles.first { $0.bundleIdentifier == bundleIdentifier }
    }

    public func save(_ profile: SmartAppProfile) {
        if let index = profiles.firstIndex(where: { $0.bundleIdentifier == profile.bundleIdentifier }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        persist()
        StatusBarController.shared.updateStatusBarTitle()
    }

    @discardableResult
    public func addProfile(for application: SmartProfileApplication) -> SmartAppProfile {
        if let existing = profile(for: application.bundleIdentifier) {
            return existing
        }
        let usesSafetyDefault = InputHookManager.shared.excludedApps.contains(application.bundleIdentifier)
        let profile = SmartAppProfile(
            displayName: application.displayName,
            bundleIdentifier: application.bundleIdentifier,
            applicationURLPath: application.applicationURLPath,
            imePolicy: usesSafetyDefault ? .english : .inherit
        )
        save(profile)
        return profile
    }

    public func removeProfile(bundleIdentifier: String) {
        profiles.removeAll { $0.bundleIdentifier == bundleIdentifier }
        persist()
        StatusBarController.shared.updateStatusBarTitle()
    }

    public func effectiveConfiguration(
        for bundleIdentifier: String?,
        globalVietnameseMode: Bool,
        globalTypingMethod: TypingMethod,
        globalMacrosEnabled: Bool
    ) -> SmartProfileEffectiveConfiguration {
        guard isEnabled, let bundleIdentifier, let profile = profile(for: bundleIdentifier) else {
            return SmartProfileEffectiveConfiguration(
                isVietnameseMode: globalVietnameseMode,
                typingMethod: globalTypingMethod,
                macrosEnabled: globalMacrosEnabled
            )
        }

        let isVietnameseMode: Bool
        switch profile.imePolicy {
        case .inherit: isVietnameseMode = globalVietnameseMode
        case .vietnamese: isVietnameseMode = true
        case .english: isVietnameseMode = false
        }

        let macrosEnabled: Bool
        switch profile.macroPolicy {
        case .inherit: macrosEnabled = globalMacrosEnabled
        case .enabled: macrosEnabled = true
        case .disabled: macrosEnabled = false
        }

        return SmartProfileEffectiveConfiguration(
            isVietnameseMode: isVietnameseMode,
            typingMethod: profile.typingPolicy.typingMethod ?? globalTypingMethod,
            macrosEnabled: macrosEnabled
        )
    }

    public func isClipboardCaptureAllowed(for bundleIdentifier: String) -> Bool {
        guard isEnabled, let profile = profile(for: bundleIdentifier) else { return true }
        return profile.clipboardPolicy != .block
    }

    public func refreshAvailableApplications() {
        DispatchQueue.global(qos: .utility).async {
            var applications: [String: SmartProfileApplication] = [:]

            for running in NSWorkspace.shared.runningApplications {
                guard let bundleIdentifier = running.bundleIdentifier,
                      !bundleIdentifier.hasPrefix("vn.xmac") else { continue }
                applications[bundleIdentifier] = SmartProfileApplication(
                    displayName: running.localizedName ?? bundleIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    applicationURLPath: running.bundleURL?.path,
                    isRunning: true
                )
            }

            let roots = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
                URL(fileURLWithPath: "/System/Applications", isDirectory: true)
            ]
            let keys: [URLResourceKey] = [.isDirectoryKey, .isApplicationKey]
            for root in roots {
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for case let url as URL in enumerator {
                    guard url.pathExtension == "app" else { continue }
                    enumerator.skipDescendants()
                    guard let bundle = Bundle(url: url),
                          let bundleIdentifier = bundle.bundleIdentifier,
                          !bundleIdentifier.hasPrefix("vn.xmac") else { continue }
                    let current = applications[bundleIdentifier]
                    applications[bundleIdentifier] = SmartProfileApplication(
                        displayName: current?.displayName
                            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                            ?? url.deletingPathExtension().lastPathComponent,
                        bundleIdentifier: bundleIdentifier,
                        applicationURLPath: url.path,
                        isRunning: current?.isRunning ?? false
                    )
                }
            }

            let sorted = applications.values.sorted {
                if $0.isRunning != $1.isRunning { return $0.isRunning && !$1.isRunning }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            DispatchQueue.main.async {
                self.availableApplications = sorted
            }
        }
    }

    private func updateActiveApplication(_ application: NSRunningApplication?) {
        activeBundleIdentifier = application?.bundleIdentifier
        InputHookManager.shared.resetForApplicationChange()
        StatusBarController.shared.updateStatusBarTitle()
    }

    /// Giải mã từng phần tử; phần tử lỗi bị bỏ qua thay vì làm mất cả danh sách.
    static func decodeLossy(_ data: Data) -> (profiles: [SmartAppProfile], hadFailures: Bool) {
        guard let elements = try? JSONDecoder().decode([LossyElement].self, from: data) else {
            return ([], true)
        }
        let profiles = elements.compactMap(\.profile)
        return (profiles, profiles.count != elements.count)
    }

    private struct LossyElement: Decodable {
        let profile: SmartAppProfile?

        init(from decoder: Decoder) throws {
            profile = try? SmartAppProfile(from: decoder)
        }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(profiles), forKey: profilesKey)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}
