import AppKit
import Testing
@testable import Xmac

@MainActor @Suite(.serialized) struct SmartProfilesTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "SmartProfilesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func profileOverridesRuntimeConfigurationWithoutChangingGlobals() {
        let defaults = makeDefaults()
        let manager = SmartProfilesManager(defaults: defaults, observeWorkspace: false)
        manager.save(SmartAppProfile(
            displayName: "Writer",
            bundleIdentifier: "test.writer",
            imePolicy: .vietnamese,
            typingPolicy: .vni,
            macroPolicy: .disabled,
            clipboardPolicy: .inherit
        ))

        let effective = manager.effectiveConfiguration(
            for: "test.writer",
            globalVietnameseMode: false,
            globalTypingMethod: .telex,
            globalMacrosEnabled: true
        )

        #expect(effective.isVietnameseMode)
        #expect(effective.typingMethod == .vni)
        #expect(!effective.macrosEnabled)

        let fallback = manager.effectiveConfiguration(
            for: "test.other",
            globalVietnameseMode: false,
            globalTypingMethod: .telex,
            globalMacrosEnabled: true
        )
        #expect(!fallback.isVietnameseMode)
        #expect(fallback.typingMethod == .telex)
        #expect(fallback.macrosEnabled)
    }

    @Test func pausedProfilesFailBackToGlobalSettings() {
        let defaults = makeDefaults()
        let manager = SmartProfilesManager(defaults: defaults, observeWorkspace: false)
        manager.save(SmartAppProfile(
            displayName: "Terminal",
            bundleIdentifier: "test.terminal",
            imePolicy: .english,
            clipboardPolicy: .block
        ))
        manager.setEnabled(false)

        let effective = manager.effectiveConfiguration(
            for: "test.terminal",
            globalVietnameseMode: true,
            globalTypingMethod: .simpleTelex,
            globalMacrosEnabled: true
        )

        #expect(effective.isVietnameseMode)
        #expect(effective.typingMethod == .simpleTelex)
        #expect(effective.macrosEnabled)
        #expect(manager.isClipboardCaptureAllowed(for: "test.terminal"))
    }

    @Test func profilesPersistAndCorruptDataFailsClosed() {
        let defaults = makeDefaults()
        let writer = SmartProfilesManager(defaults: defaults, observeWorkspace: false)
        writer.save(SmartAppProfile(
            displayName: "Notes",
            bundleIdentifier: "test.notes",
            clipboardPolicy: .block
        ))

        let reader = SmartProfilesManager(defaults: defaults, observeWorkspace: false)
        #expect(reader.profiles.count == 1)
        #expect(!reader.isClipboardCaptureAllowed(for: "test.notes"))

        defaults.set(Data("not-json".utf8), forKey: "SmartProfiles.Profiles")
        let corrupt = SmartProfilesManager(defaults: defaults, observeWorkspace: false)
        #expect(corrupt.loadFailed)
        #expect(corrupt.profiles.isEmpty)
        #expect(corrupt.isClipboardCaptureAllowed(for: "test.notes"))
    }

    @Test func clipboardProfileBlockPreventsCapture() {
        let defaults = makeDefaults()
        let board = NSPasteboard(name: NSPasteboard.Name("SmartProfilesTests.\(UUID().uuidString)"))
        let store = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartProfilesTests-\(UUID().uuidString).json")
        let history = ClipboardHistory(
            defaults: defaults,
            store: store,
            board: board,
            onCopy: {},
            profileAllowsCapture: { $0 != "test.blocked" }
        )
        history.enabled = true
        board.clearContents()
        board.setString("private value", forType: .string)

        history.poll(source: "test.blocked")

        #expect(history.items.isEmpty)
    }
}
