import Foundation
import Testing
@testable import Xmac

@MainActor
@Suite struct WatchFolderMonitorTests {
    private struct Setup {
        let folder: URL
        let store: WatchFolderStore
        let manager: ConverterManager
        let monitor: WatchFolderMonitor
        let defaults: UserDefaults
        let suite: String
    }

    private func makeSetup() throws -> Setup {
        let suite = "WatchFolderMonitorTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let folder = try ConverterFixtures.makeTempDirectory()
        let store = WatchFolderStore(defaults: defaults)
        store.isEnabled = true
        let registry = ConverterRegistry(converters: [ImageConverter()], locator: BinaryLocator(defaults: defaults))
        let manager = ConverterManager(registry: registry, defaults: defaults, notify: { _, _ in }, playSound: { _ in })
        let monitor = WatchFolderMonitor(store: store, manager: manager, sleep: { _ in })
        return Setup(folder: folder, store: store, manager: manager, monitor: monitor, defaults: defaults, suite: suite)
    }

    private func rule(_ folder: URL, from: String, to: String, subfolder: String? = nil) -> WatchFolderRule {
        WatchFolderRule(
            folderPath: folder.path, extensions: [from], targetID: "image.\(to)", targetTitle: to.uppercased(),
            outputSubfolder: subfolder
        )
    }

    private func settle(_ manager: ConverterManager) async {
        for _ in 0..<500 {
            if !manager.jobs.isEmpty, manager.jobs.allSatisfy({ $0.state.isFinished }) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test func convertsNewFileAndKeepsOriginal() async throws {
        let s = try makeSetup()
        defer { s.defaults.removePersistentDomain(forName: s.suite) }
        s.store.rules = [rule(s.folder, from: "png", to: "jpg")]
        let png = try ConverterFixtures.writeImage(to: s.folder.appendingPathComponent("a.png"))

        await s.monitor.process(png)
        await settle(s.manager)

        #expect(FileManager.default.fileExists(atPath: s.folder.appendingPathComponent("a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: png.path))
    }

    @Test func outputSubfolderIsCreatedAndOutOfScope() async throws {
        let s = try makeSetup()
        defer { s.defaults.removePersistentDomain(forName: s.suite) }
        s.store.rules = [rule(s.folder, from: "png", to: "jpg", subfolder: "Done")]
        let png = try ConverterFixtures.writeImage(to: s.folder.appendingPathComponent("a.png"))

        await s.monitor.process(png)
        await settle(s.manager)

        #expect(FileManager.default.fileExists(atPath: s.folder.appendingPathComponent("Done/a.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: s.folder.appendingPathComponent("a.jpg").path))
    }

    @Test func oppositeRulesDoNotPingPong() async throws {
        let s = try makeSetup()
        defer { s.defaults.removePersistentDomain(forName: s.suite) }
        s.store.rules = [rule(s.folder, from: "png", to: "jpg"), rule(s.folder, from: "jpg", to: "png")]
        let png = try ConverterFixtures.writeImage(to: s.folder.appendingPathComponent("a.png"))

        await s.monitor.process(png)
        await settle(s.manager)
        let produced = s.folder.appendingPathComponent("a.jpg")
        #expect(FileManager.default.fileExists(atPath: produced.path))

        await s.monitor.process(produced)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(s.manager.jobs.count == 1)
    }

    @Test func sameFileIsNotConvertedTwiceEvenWhenItsSnapshotChanges() async throws {
        let s = try makeSetup()
        defer { s.defaults.removePersistentDomain(forName: s.suite) }
        s.store.rules = [rule(s.folder, from: "png", to: "jpg")]
        let png = try ConverterFixtures.writeImage(to: s.folder.appendingPathComponent("a.png"))

        await s.monitor.process(png)
        await s.monitor.process(png)
        #expect(s.manager.jobs.count == 1)

        try ConverterFixtures.writeImage(to: png, width: 80, height: 40)
        await s.monitor.process(png)
        #expect(s.manager.jobs.count == 1)
    }

    @Test func disabledSwitchOrRuleAndIgnoredNamesQueueNothing() async throws {
        let s = try makeSetup()
        defer { s.defaults.removePersistentDomain(forName: s.suite) }
        var disabled = rule(s.folder, from: "png", to: "jpg")
        disabled.enabled = false
        s.store.rules = [disabled]
        let png = try ConverterFixtures.writeImage(to: s.folder.appendingPathComponent("a.png"))
        await s.monitor.process(png)

        s.store.rules[0].enabled = true
        s.store.isEnabled = false
        await s.monitor.process(png)

        s.store.isEnabled = true
        let hidden = try ConverterFixtures.writeImage(to: s.folder.appendingPathComponent(".b.png"))
        await s.monitor.process(hidden)
        #expect(s.manager.jobs.isEmpty)
    }
}
