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

        let zalo = IMETapSnapshot.make(
            bundleIdentifier: "com.vng.zalo", processIdentifier: 13,
            hook: .shared, profiles: profiles, macroManager: macros, previous: chrome
        )
        #expect(zalo.isElectronOrChatApp)
        #expect(!zalo.isBrowser)
        #expect(!zalo.isExcluded)

        let terminal = IMETapSnapshot.make(
            bundleIdentifier: "com.apple.Terminal", processIdentifier: 11,
            hook: .shared, profiles: profiles, macroManager: macros, previous: zalo
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

    @Test func browserReplacementSendsOneCharacterPerKeyWithoutIntrusiveBreakerByDefault() {
        let plan = SyntheticReplacementPlan.make(backspaceCount: 3, newText: "êng", isBrowser: true)
        #expect(plan.leadingText == nil)
        #expect(plan.backspaceCount == 3)
        #expect(plan.textChunks == [[0x00EA], [0x006E], [0x0067]])
        #expect(plan.syntheticEventCount == (3 + 3) * 2)
    }

    @Test func browserReplacementSupportsOptionalAutocompleteBreaker() {
        let plan = SyntheticReplacementPlan.make(
            backspaceCount: 3, newText: "êng", isBrowser: true, useAutocompleteBreaker: true
        )
        #expect(plan.leadingText == [0x202F])
        #expect(plan.backspaceCount == 4)
        #expect(plan.textChunks == [[0x00EA], [0x006E], [0x0067]])
        #expect(plan.syntheticEventCount == (1 + 4 + 3) * 2)
    }

    @Test func electronOrChatAppUsesSingleCharacterEventsForCleanRendering() {
        let plan = SyntheticReplacementPlan.make(
            backspaceCount: 3, newText: "êng", isBrowser: false, isElectronOrChatApp: true
        )
        #expect(plan.leadingText == nil)
        #expect(plan.backspaceCount == 3)
        #expect(plan.textChunks == [[0x00EA], [0x006E], [0x0067]])
        #expect(plan.syntheticEventCount == (3 + 3) * 2)
    }

    @Test func browserAppendNeedsNoAutocompleteBreaker() {
        let plan = SyntheticReplacementPlan.make(backspaceCount: 0, newText: "Việt Nam ", isBrowser: true)
        #expect(plan.leadingText == nil)
        #expect(plan.backspaceCount == 0)
        #expect(plan.textChunks.count == 9)
    }

    @Test func nativeAppWordEditSendsOneCharacterPerKey() {
        let plan = SyntheticReplacementPlan.make(backspaceCount: 3, newText: "êng", isBrowser: false)
        #expect(plan.leadingText == nil)
        #expect(plan.backspaceCount == 3)
        #expect(plan.textChunks == [[0x00EA], [0x006E], [0x0067]])
    }

    @Test func nativeAppMacroTextKeepsChunks() {
        let plan = SyntheticReplacementPlan.make(
            backspaceCount: 2, newText: "Việt Nam ", isBrowser: false, isBulkText: true
        )
        #expect(plan.textChunks == [Array("Việt Nam ".utf16)])
    }

    @Test func webMacroTextStillGoesOneCharacterPerKey() {
        let plan = SyntheticReplacementPlan.make(
            backspaceCount: 2, newText: "được ", isBrowser: false, isElectronOrChatApp: true, isBulkText: true
        )
        #expect(plan.textChunks.count == 5)
    }

    @Test func symbolsEndTheSyllableButDigitsDoNot() {
        for symbol: Character in ["-", "/", "@", "_", "=", "+", "<", "#", ".", " ", "\n"] {
            #expect(!InputHookManager.continuesWord(symbol), "\(symbol)")
        }
        for key: Character in ["a", "Đ", "ư", "w", "1", "9"] {
            #expect(InputHookManager.continuesWord(key), "\(key)")
        }
    }

    @Test func macroLookupMatchesShortcutsWithSymbols() {
        let expansion = InputHookManager.macroExpansion(
            for: "v/v", boundaryKeyCode: 49, character: " ", macros: ["v/v": "về việc"], enabled: true
        )
        #expect(expansion == "về việc")
    }

    @Test func snapshotTreatsDetectedChromiumAppsAsElectron() {
        let (profiles, macros, cleanup) = makeManagers()
        defer { cleanup() }
        let claude = IMETapSnapshot.make(
            bundleIdentifier: "com.anthropic.claudefordesktop", processIdentifier: 30,
            hook: .shared, profiles: profiles, macroManager: macros,
            usesChromiumEngine: true, previous: IMETapSnapshot()
        )
        #expect(claude.isElectronOrChatApp)
        #expect(!claude.isBrowser)

        let chrome = IMETapSnapshot.make(
            bundleIdentifier: "com.google.Chrome", processIdentifier: 31,
            hook: .shared, profiles: profiles, macroManager: macros,
            usesChromiumEngine: true, previous: claude
        )
        #expect(chrome.isBrowser)
        #expect(!chrome.isElectronOrChatApp)

        let notes = IMETapSnapshot.make(
            bundleIdentifier: "com.apple.Notes", processIdentifier: 32,
            hook: .shared, profiles: profiles, macroManager: macros, previous: chrome
        )
        #expect(!notes.isElectronOrChatApp)
    }

    @Test func detectorRecognisesChromiumBundlesAndPWAs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("XmacChromiumDetector-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        func makeBundle(_ name: String, frameworks: [String]) throws -> URL {
            let bundle = root.appendingPathComponent("\(name).app")
            let dir = bundle.appendingPathComponent("Contents/Frameworks")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for entry in frameworks {
                try FileManager.default.createDirectory(
                    at: dir.appendingPathComponent(entry), withIntermediateDirectories: true
                )
            }
            return bundle
        }

        let electron = try makeBundle("Electron", frameworks: ["Electron Framework.framework", "Squirrel.framework"])
        let cef = try makeBundle("CEF", frameworks: ["Chromium Embedded Framework.framework"])
        let chromeLike = try makeBundle("Chromey", frameworks: ["Chromey Helper (Renderer).app"])
        let native = try makeBundle("Native", frameworks: ["Sparkle.framework"])
        let noFrameworks = root.appendingPathComponent("Bare.app")

        #expect(ChromiumAppDetector.bundleUsesChromium(at: electron))
        #expect(ChromiumAppDetector.bundleUsesChromium(at: cef))
        #expect(ChromiumAppDetector.bundleUsesChromium(at: chromeLike))
        #expect(!ChromiumAppDetector.bundleUsesChromium(at: native))
        #expect(!ChromiumAppDetector.bundleUsesChromium(at: noFrameworks))

        #expect(ChromiumAppDetector.isProgressiveWebApp(bundleIdentifier: "com.google.Chrome.app.fmpnliohjhemenmnlpbfagaolkdacoja"))
        #expect(!ChromiumAppDetector.isProgressiveWebApp(bundleIdentifier: "com.google.Chrome"))
        #expect(!ChromiumAppDetector.isProgressiveWebApp(bundleIdentifier: "com.apple.Notes"))
    }

    @Test func pacingWaitsOnlyForTheRemainderOfTheGap() {
        #expect(ReplacementPacing.remainingWait(elapsed: 0, beforeReturn: false) == 600_000)
        #expect(ReplacementPacing.remainingWait(elapsed: 200_000, beforeReturn: false) == 400_000)
        #expect(ReplacementPacing.remainingWait(elapsed: 600_000, beforeReturn: false) == 0)
        #expect(ReplacementPacing.remainingWait(elapsed: 5_000_000, beforeReturn: false) == 0)
        #expect(ReplacementPacing.remainingWait(elapsed: 5_000_000, beforeReturn: true) == 3_000_000)
        #expect(ReplacementPacing.remainingWait(elapsed: 20_000_000, beforeReturn: true) == 0)
    }

    @Test func pacingClockIsInNanoseconds() {
        let start = ReplacementPacing.now()
        ReplacementPacing.sleep(nanoseconds: 2_000_000)
        let elapsed = ReplacementPacing.now() - start
        #expect(elapsed >= 2_000_000)
        #expect(elapsed < 500_000_000)
    }

    @Test func autocompleteBreakerOnlyTargetsSingleLineFields() {
        func single(_ role: String?, _ subrole: String? = nil, editableAncestor: Bool = false) -> Bool {
            FocusedFieldInspector.isSingleLine(role: role, subrole: subrole, hasEditableAncestor: editableAncestor)
        }
        #expect(single("AXTextField"))
        #expect(single("AXComboBox"))
        #expect(single("AXTextField", "AXSearchField"))
        #expect(!single("AXTextArea"))
        #expect(!single("AXWebArea"))
        #expect(!single(nil))
        // ARIA textbox/combobox inside a rich editor.
        #expect(!single("AXTextField", editableAncestor: true))
        #expect(!single("AXComboBox", "AXContentEditable"))
    }

    @Test func focusProbeOnlyRunsInWebKitBrowsers() {
        #expect(!FocusedFieldInspector.canProbe(bundleIdentifier: "com.google.Chrome"))
        #expect(FocusedFieldInspector.canProbe(bundleIdentifier: "com.apple.Safari"))
        #expect(FocusedFieldInspector.canProbe(bundleIdentifier: "com.apple.SafariTechnologyPreview"))
        #expect(!FocusedFieldInspector.canProbe(bundleIdentifier: "org.mozilla.firefox"))
        #expect(!FocusedFieldInspector.canProbe(bundleIdentifier: nil))
    }

    @Test func macroAfterASymbolStillExpandsAndKeepsTheSymbol() {
        let macros = ["btw": "by the way", "v/v": "về việc"]
        func match(_ prefix: String, _ segment: String) -> (shortcut: String, expansion: String)? {
            InputHookManager.macroMatch(
                prefix: prefix, segment: segment, boundaryKeyCode: 49, character: " ",
                macros: macros, enabled: true
            )
        }
        #expect(match("(", "btw")?.shortcut == "btw")
        #expect(match("\"", "btw")?.expansion == "by the way")
        #expect(match("v/", "v")?.shortcut == "v/v")
        #expect(match("", "btw")?.shortcut == "btw")
        #expect(match("(", "xyz") == nil)
        #expect(match("", "") == nil)
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
