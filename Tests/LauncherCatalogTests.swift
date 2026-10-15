import Foundation
import Testing
@testable import Xmac

@Suite struct LauncherCatalogTests {
    @Test func commandsCanBeFoundWithoutVietnameseDiacritics() {
        let matches = LauncherEntry.matching(LauncherEntry.commands, query: "  O DIA  ")
        #expect(matches.first?.destination == .tab(.diskNTFS))
        #expect(LauncherEntry.matching(LauncherEntry.commands, query: "go tieng viet").contains { $0.destination == .tab(.vietnameseIME) })
        #expect(LauncherEntry.matching(LauncherEntry.commands, query: "not-a-command").isEmpty)
    }

    @Test func rankingPrefersExactThenPrefixAndUsesAllWords() {
        let entries = [
            LauncherEntry(id: "1", title: "My Downloads", subtitle: "App", icon: "app", destination: .application("/a")),
            LauncherEntry(id: "2", title: "Downloads Helper", subtitle: "App", icon: "app", destination: .application("/b")),
            LauncherEntry(id: "3", title: "Downloads", subtitle: "App", icon: "app", destination: .application("/c"))
        ]
        #expect(LauncherEntry.matching(entries, query: "downloads").map(\.id) == ["3", "2", "1"])
        #expect(LauncherEntry.matching(entries, query: "downloads helper").map(\.id) == ["2"])
        #expect(LauncherEntry.matching(entries, query: "", limit: 2).count == 2)
    }

    @Test func applicationDiscoveryStopsAtBundlesAndFindsUtilities() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("XmacLauncherTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("Utilities/Tool.app/Contents/Helper.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".Hidden.app"), withIntermediateDirectories: true)
        let apps = LauncherEntry.applications(in: [root, root])
        #expect(apps.count == 1)
        guard case .application(let path) = apps[0].destination else { Issue.record("Expected an application result"); return }
        #expect(URL(fileURLWithPath: path).resolvingSymlinksInPath() == root.appendingPathComponent("Utilities/Tool.app").resolvingSymlinksInPath())
    }

    @MainActor @Test func cancellingLauncherSearchDoesNotCancelMainSearch() async throws {
        let launcher = FileSearchEngine()
        let main = FileSearchEngine()
        let initialMessage = main.statusMessage
        main.scheduleSearch(text: "report", scope: .documents, kind: .documents, includeContents: false, delay: 0.01)
        launcher.scheduleSearch(text: "image", scope: .home, kind: .images, includeContents: false, delay: 0.05)
        launcher.cancelSearch()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!launcher.isSearching)
        #expect(launcher.results.isEmpty)
        #expect(main.statusMessage != initialMessage)
        main.cancelSearch()
    }
}
