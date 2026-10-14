import Foundation
import Testing
@testable import Xmac

@Suite(.serialized) struct RegressionTests {
    @Test func cleanerReportsDiscoveredBytesAndHonorsIndividualSelection() {
        let category = JunkCategory(
            name: "Caches",
            description: "Test",
            iconName: "archivebox",
            items: [
                JunkItem(name: "selected", path: "/tmp/selected", size: 120, isSelected: true),
                JunkItem(name: "unselected", path: "/tmp/unselected", size: 80, isSelected: false)
            ],
            isSelected: false
        )

        #expect(category.totalSize == 200)
        #expect(category.rawTotalSize == 200)
        #expect(category.selectedSize == 120)
        #expect(CleanerEngine.selectedSize(in: [category]) == 120)
        #expect(CleanerEngine.discoveredSize(in: [category]) == 200)
        #expect(CleanerEngine.selectedItems(in: [category]).map(\.name) == ["selected"])
    }

    @Test func macroEnabledPreferencePersists() {
        let suiteName = "XmacTests.MacroManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "XmacMacroEnabled")
        let manager = MacroManager(defaults: defaults)
        #expect(!manager.isMacroEnabled)

        manager.isMacroEnabled = true
        #expect(defaults.bool(forKey: "XmacMacroEnabled"))

        let restored = MacroManager(defaults: defaults)
        #expect(restored.isMacroEnabled)
    }

    @Test func appVersionUsesBundleMetadataWithoutDuplicatingBuild() {
        let release = AppVersionInfo.from(infoDictionary: [
            "CFBundleShortVersionString": "1.1.0",
            "CFBundleVersion": "1.1.0"
        ])
        #expect(release.version == "1.1.0")
        #expect(release.settingsDescription == "Phiên bản 1.1.0")

        let numberedBuild = AppVersionInfo.from(infoDictionary: [
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "42"
        ])
        #expect(numberedBuild.settingsDescription == "Phiên bản 1.2.0 (Build 42)")
    }

    @Test func finderFilenameFieldIsNotMistakenForRenameEditor() {
        #expect(!FinderBridge.isRenameEditor(role: "AXTextField", hasFileURL: true))
        #expect(FinderBridge.isRenameEditor(role: "AXTextField", hasFileURL: false))
        #expect(FinderBridge.isRenameEditor(role: "AXTextArea", hasFileURL: false))
        #expect(!FinderBridge.isRenameEditor(role: "AXRow", hasFileURL: false))
    }
}
