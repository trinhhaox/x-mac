import Cocoa
import Foundation
import Testing
@testable import Xmac

@Suite struct IMETapThreadingTests {
    private func makeManagers() -> (SmartProfilesManager, MacroManager, () -> Void) {
        let suiteName = "XmacTests.TapSnapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let cleanup = { defaults.removePersistentDomain(forName: suiteName) }
        return (SmartProfilesManager(defaults: defaults), MacroManager(defaults: defaults), cleanup)
    }

    @Test func snapshotFlagsBrowsersAndExcludedApps() {
        let (profiles, macros, cleanup) = makeManagers()
        defer { cleanup() }

        let chrome = IMETapSnapshot.make(
            bundleIdentifier: "com.google.Chrome", processIdentifier: 10,
            hook: .shared, profiles: profiles, macroManager: macros, previous: IMETapSnapshot()
        )
        #expect(chrome.isBrowser)
        #expect(!chrome.isExcluded)
        #expect(chrome.macros["vn"] == "Việt Nam")

        let terminal = IMETapSnapshot.make(
            bundleIdentifier: "com.apple.Terminal", processIdentifier: 11,
            hook: .shared, profiles: profiles, macroManager: macros, previous: chrome
        )
        #expect(terminal.isExcluded)
        #expect(!terminal.isBrowser)

        let finder = IMETapSnapshot.make(
            bundleIdentifier: "com.apple.finder", processIdentifier: 12,
            hook: .shared, profiles: profiles, macroManager: macros,
            finderCutPasteEnabled: true, previous: terminal
        )
        #expect(finder.handlesFinderShortcuts)
        #expect(!chrome.handlesFinderShortcuts)
        let finderCutPasteOff = IMETapSnapshot.make(
            bundleIdentifier: "com.apple.finder", processIdentifier: 12,
            hook: .shared, profiles: profiles, macroManager: macros,
            finderCutPasteEnabled: false, previous: finder
        )
        #expect(!finderCutPasteOff.handlesFinderShortcuts)
    }

    @Test func snapshotBumpsResetGenerationOnlyWhenTheAppChanges() {
        let (profiles, macros, cleanup) = makeManagers()
        defer { cleanup() }

        let first = IMETapSnapshot.make(
            bundleIdentifier: "com.apple.Notes", processIdentifier: 20,
            hook: .shared, profiles: profiles, macroManager: macros, previous: IMETapSnapshot()
        )
        let sameApp = IMETapSnapshot.make(
            bundleIdentifier: "com.apple.Notes", processIdentifier: 20,
            hook: .shared, profiles: profiles, macroManager: macros, previous: first
        )
        let otherApp = IMETapSnapshot.make(
            bundleIdentifier: "com.apple.Safari", processIdentifier: 21,
            hook: .shared, profiles: profiles, macroManager: macros, previous: sameApp
        )
        #expect(sameApp.resetGeneration == first.resetGeneration)
        #expect(otherApp.resetGeneration == sameApp.resetGeneration + 1)
    }

    @Test func browserReplacementBreaksAutocompleteAndSendsOneCharacterPerKey() {
        let plan = SyntheticReplacementPlan.make(backspaceCount: 3, newText: "êng", isBrowser: true)
        #expect(plan.leadingText == [0x202F])
        #expect(plan.backspaceCount == 4)
        #expect(plan.textChunks == [[0x00EA], [0x006E], [0x0067]])
        #expect(plan.syntheticEventCount == (1 + 4 + 3) * 2)
    }

    @Test func browserAppendNeedsNoAutocompleteBreaker() {
        let plan = SyntheticReplacementPlan.make(backspaceCount: 0, newText: "Việt Nam ", isBrowser: true)
        #expect(plan.leadingText == nil)
        #expect(plan.backspaceCount == 0)
        #expect(plan.textChunks.count == 9)
    }

    @Test func nativeAppReplacementKeepsChunkedText() {
        let plan = SyntheticReplacementPlan.make(backspaceCount: 3, newText: "êng", isBrowser: false)
        #expect(plan.leadingText == nil)
        #expect(plan.backspaceCount == 3)
        #expect(plan.textChunks == [Array("êng".utf16)])
    }

    @Test func onlyCommandZXCVReachTheFinderMainThreadHop() {
        func keyDown(_ keyCode: CGKeyCode, _ flags: CGEventFlags) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
            event.flags = flags
            return event
        }
        #expect(EventTapManager.isShortcutCandidate(type: .keyDown, event: keyDown(7, .maskCommand)))
        #expect(EventTapManager.isShortcutCandidate(type: .keyDown, event: keyDown(9, [.maskCommand, .maskShift])))
        #expect(!EventTapManager.isShortcutCandidate(type: .keyDown, event: keyDown(7, [])))
        #expect(!EventTapManager.isShortcutCandidate(type: .keyDown, event: keyDown(0, .maskCommand)))
        #expect(!EventTapManager.isShortcutCandidate(type: .keyDown, event: keyDown(7, [.maskCommand, .maskAlternate])))
        #expect(!EventTapManager.isShortcutCandidate(type: .flagsChanged, event: keyDown(7, .maskCommand)))
    }

    @Test func spellLookupFromTheTapThreadNeverBlocksForLong() async {
        // Off the main thread the lookup is bounded by the timeout, whether or
        // not the main queue answers in time.
        let start = Date()
        _ = await Task.detached { EnglishLexicon.contains("throughput") }.value
        #expect(Date().timeIntervalSince(start) < 1)
    }
}
