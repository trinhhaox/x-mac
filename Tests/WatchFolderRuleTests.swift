import Foundation
import Testing
@testable import Xmac

@Suite struct WatchFolderRuleTests {
    private func rule(_ folder: String = "/tmp/watch", subfolder: String? = nil) -> WatchFolderRule {
        WatchFolderRule(folderPath: folder, extensions: ["png", "jpg"], targetID: "image.jpg", targetTitle: "JPG", outputSubfolder: subfolder)
    }

    @Test func acceptsDirectChildrenWithMatchingExtensionOnly() {
        let rule = rule()
        #expect(rule.accepts(URL(fileURLWithPath: "/tmp/watch/a.PNG")))
        #expect(!rule.accepts(URL(fileURLWithPath: "/tmp/watch/a.pdf")))
        #expect(!rule.accepts(URL(fileURLWithPath: "/tmp/watch/sub/a.png")))
        #expect(!rule.accepts(URL(fileURLWithPath: "/tmp/other/a.png")))
    }

    @Test func outputSubfolderIsInsideWatchedFolder() {
        #expect(rule(subfolder: "Đã chuyển").outputDirectory?.path == "/tmp/watch/Đã chuyển")
        #expect(rule().outputDirectory == nil)
    }

    @Test func subfolderNamesAreNormalizedAndValidated() {
        #expect(WatchFolderRule.normalizedSubfolder("  Done ") == "Done")
        #expect(WatchFolderRule.normalizedSubfolder("   ") == nil)
        #expect(WatchFolderRule.normalizedSubfolder("../x") == nil)
        #expect(WatchFolderRule.normalizedSubfolder("a/b") == nil)
    }

    @Test func ignoresHiddenPartialAndUnfinishedDownloads() {
        for name in [".hidden.png", "a.png.crdownload", "a.png.part", "a.png.download", ".a.xmac-partial.png"] {
            #expect(WatchCandidateFilter.isIgnored(URL(fileURLWithPath: "/tmp/watch/\(name)")), "\(name)")
        }
        #expect(!WatchCandidateFilter.isIgnored(URL(fileURLWithPath: "/tmp/watch/photo.png")))
    }

    @Test func groupsOfferTargetsFromRegistry() {
        let registry = ConverterRegistry(converters: [ImageConverter()], locator: BinaryLocator())
        let ids = Set(WatchInputGroup.image.targets(in: registry).map(\.id))
        #expect(ids.contains("image.jpg") && ids.contains("image.heic"))
        #expect(WatchInputGroup.subtitle.targets(in: registry).isEmpty)
    }

    @Test func stabilityNeedsTwoEqualNonEmptyChecks() async {
        let steady = FileSnapshot(size: 10, modifiedMillis: 1)
        var answers = [FileSnapshot(size: 5, modifiedMillis: 1), FileSnapshot(size: 10, modifiedMillis: 1), steady, steady]
        var sleeps: [TimeInterval] = []
        let result = await WatchStability.waitUntilStable(
            URL(fileURLWithPath: "/x"), stat: { _ in answers.removeFirst() }, sleep: { sleeps.append($0) }
        )
        #expect(result == steady)
        #expect(sleeps == [2, 2])
    }

    @Test func stabilityGivesUpOnVanishedEmptyOrEndlessFiles() async {
        let url = URL(fileURLWithPath: "/x")
        #expect(await WatchStability.waitUntilStable(url, stat: { _ in nil }, sleep: { _ in }) == nil)
        let empty = FileSnapshot(size: 0, modifiedMillis: 1)
        #expect(await WatchStability.waitUntilStable(url, maxWait: 10, stat: { _ in empty }, sleep: { _ in }) == nil)
        var size: UInt64 = 0
        let growing = await WatchStability.waitUntilStable(url, maxWait: 10, stat: { _ in size += 1; return FileSnapshot(size: size, modifiedMillis: 1) }, sleep: { _ in })
        #expect(growing == nil)
    }

    @Test func processedSetKeepsRecentEntriesOnly() {
        var set = WatchProcessedSet()
        let rule = UUID()
        for index in 0..<(WatchProcessedSet.limit + 10) {
            set.markOutput("/p/\(index)", FileSnapshot(size: 1, modifiedMillis: 1))
        }
        #expect(set.keys.count == WatchProcessedSet.limit)
        #expect(!set.isOutput("/p/0", FileSnapshot(size: 1, modifiedMillis: 1)))
        #expect(set.isOutput("/p/\(WatchProcessedSet.limit + 9)", FileSnapshot(size: 1, modifiedMillis: 1)))
        set.markHandled(by: rule, "/p/a")
        #expect(set.wasHandled(by: rule, "/p/a") && set.wasHandled(by: rule, "/p/../p/a"))
        #expect(!set.wasHandled(by: UUID(), "/p/a"))
    }

    @MainActor @Test func rulesSwitchAndProcessedSurviveRelaunch() throws {
        let suite = "WatchFolderStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WatchFolderStore(defaults: defaults)
        #expect(!store.isEnabled && store.rules.isEmpty)
        let saved = rule(subfolder: "Done")
        store.rules = [saved]
        store.isEnabled = true
        store.updateProcessed { $0.markOutput("/tmp/watch/a.jpg", FileSnapshot(size: 3, modifiedMillis: 4)) }

        let reloaded = WatchFolderStore(defaults: defaults)
        #expect(reloaded.rules == [saved])
        #expect(reloaded.isEnabled)
        #expect(reloaded.processed.isOutput("/tmp/watch/a.jpg", FileSnapshot(size: 3, modifiedMillis: 4)))
    }

    @Test func tamperedOutputSubfolderIsRejected() {
        #expect(rule(subfolder: "../../x").outputDirectory == nil)
        #expect(rule(subfolder: " Done ").outputDirectory?.path == "/tmp/watch/Done")
    }

    @Test func pagesExtractionIsNotOfferedToWatchRules() {
        let registry = ConverterRegistry(converters: [PDFPagesConverter()], locator: BinaryLocator())
        let ids = WatchInputGroup.pdf.targets(in: registry).map(\.id)
        #expect(ids.contains(PDFPagesConverter.splitTargetID) && !ids.contains(PDFPagesConverter.extractTargetID))
    }
}
