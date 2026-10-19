import Cocoa
import Combine
import os

/// Everything the event tap thread needs to handle one keystroke. Built on the
/// main thread from the @Published managers and copied under one unfair lock
/// by the tap thread, so typing never waits for the UI.
struct IMETapSnapshot: Equatable {
    var processIdentifier: pid_t?
    var bundleIdentifier: String?
    var isExcluded = false
    var isBrowser = false
    /// Finder is frontmost and Cut/Paste is on: only then may Cmd+X/C/V/Z
    /// block the tap thread on a main-thread hop.
    var handlesFinderShortcuts = false
    var configuration = SmartProfileEffectiveConfiguration(
        isVietnameseMode: true,
        typingMethod: .telex,
        macrosEnabled: true
    )
    var modernOrthography = true
    var macros: [String: String] = [:]
    /// Bumped whenever the composition buffer must be dropped (app switch,
    /// language toggle). The tap thread compares it to the last value it saw.
    var resetGeneration = 0

    /// Browsers inline-autocomplete URL bars and search fields: the suggested
    /// tail is selected, so the first synthetic Backspace only clears the
    /// selection. Replacements there need the empty-character workaround.
    static let browserBundleIdentifiers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "com.coccoc.Coccoc",
        "org.chromium.Chromium"
    ]

    static func make(
        bundleIdentifier: String?,
        processIdentifier: pid_t?,
        hook: InputHookManager,
        profiles: SmartProfilesManager,
        macroManager: MacroManager,
        finderCutPasteEnabled: Bool = false,
        previous: IMETapSnapshot
    ) -> IMETapSnapshot {
        var snapshot = IMETapSnapshot()
        snapshot.processIdentifier = processIdentifier
        snapshot.bundleIdentifier = bundleIdentifier
        snapshot.configuration = profiles.effectiveConfiguration(
            for: bundleIdentifier,
            globalVietnameseMode: hook.isVietnameseMode,
            globalTypingMethod: hook.typingMethod,
            globalMacrosEnabled: macroManager.isMacroEnabled
        )
        if let bundleIdentifier {
            let hasExplicitProfile = profiles.isEnabled && profiles.profile(for: bundleIdentifier) != nil
            snapshot.isExcluded = hook.excludedApps.contains(bundleIdentifier) && !hasExplicitProfile
            snapshot.isBrowser = browserBundleIdentifiers.contains(bundleIdentifier)
        }
        snapshot.handlesFinderShortcuts = finderCutPasteEnabled && bundleIdentifier == "com.apple.finder"
        snapshot.modernOrthography = hook.modernOrthography
        snapshot.macros = Dictionary(
            macroManager.macros.map { ($0.shortcut, $0.expansion) },
            uniquingKeysWith: { first, _ in first }
        )
        snapshot.resetGeneration = previous.resetGeneration
            + (previous.processIdentifier != processIdentifier ? 1 : 0)
        return snapshot
    }
}

/// Keeps `IMETapSnapshot` current. All mutation happens on the main thread;
/// `snapshot` may be read from any thread.
final class IMEConfigurationStore {
    static let shared = IMEConfigurationStore()

    private let state = OSAllocatedUnfairLock(initialState: IMETapSnapshot())
    private var subscriptions: Set<AnyCancellable> = []
    private var activationObserver: NSObjectProtocol?

    private init() {}

    var snapshot: IMETapSnapshot { state.withLock { $0 } }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard subscriptions.isEmpty else { return }
        // objectWillChange fires before the new value is stored; hopping to the
        // next main-queue turn reads the updated value.
        let changes: [ObservableObjectPublisher] = [
            InputHookManager.shared.objectWillChange,
            SmartProfilesManager.shared.objectWillChange,
            MacroManager.shared.objectWillChange,
            FinderCutPasteManager.shared.objectWillChange
        ]
        for publisher in changes {
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &subscriptions)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        let app = NSWorkspace.shared.frontmostApplication
        state.withLock { current in
            current = IMETapSnapshot.make(
                bundleIdentifier: app?.bundleIdentifier,
                processIdentifier: app?.processIdentifier,
                hook: InputHookManager.shared,
                profiles: SmartProfilesManager.shared,
                macroManager: MacroManager.shared,
                finderCutPasteEnabled: FinderCutPasteManager.shared.isEnabled,
                previous: current
            )
        }
    }

    /// Asks the tap thread to drop its composition before the next keystroke.
    func requestReset() {
        state.withLock { $0.resetGeneration += 1 }
    }
}
