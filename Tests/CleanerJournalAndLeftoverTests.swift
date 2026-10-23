import Foundation
import Testing
@testable import Xmac

@Suite(.serialized) struct CleanerJournalAndLeftoverTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("XmacCleanerJournal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ root: URL, _ relative: String, contents: Data = Data()) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
    }

    @Test func journalRoundTripsAndSkipsCorruptLines() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = CleanupOperationLog(fileURL: dir.appendingPathComponent("Logs/operations.log"))
        let first = CleanupLogEntry(date: Date(timeIntervalSince1970: 1_000), action: .clean, path: "/a", bytes: 10, outcome: .trashed)
        log.append([first])
        let handle = try FileHandle(forWritingTo: log.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n".utf8))
        try handle.close()
        let second = CleanupLogEntry(date: Date(timeIntervalSince1970: 2_000), action: .uninstall, path: "/b", bytes: 0, outcome: .skipped, reason: "in use")
        log.append([second])

        let recent = log.recent()
        #expect(recent.map(\.path) == ["/b", "/a"])
        #expect(recent.first?.reason == "in use")
    }

    @Test func whitelistFailsClosedWhenUnreadable() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let whitelist = CleanerWhitelist(fileURL: dir.appendingPathComponent("whitelist.json"))
        #expect(try whitelist.load() == [])

        try whitelist.add("/Users/t/Library/Caches/Keep")
        try whitelist.add("/Users/t/Library/Caches/Keep")
        #expect(try whitelist.load() == ["/Users/t/Library/Caches/Keep"])
        #expect(CleanerWhitelist.isProtected("/Users/t/Library/Caches/Keep/sub", by: try whitelist.load()))
        #expect(!CleanerWhitelist.isProtected("/Users/t/Library/Caches/Keeper", by: try whitelist.load()))
        try whitelist.remove("/Users/t/Library/Caches/Keep")
        #expect(try whitelist.load() == [])

        try Data("{broken".utf8).write(to: whitelist.fileURL)
        #expect(throws: CleanerWhitelist.UnreadableError.self) { try whitelist.load() }
    }

    @Test func locatorFindsGroupContainersLaunchAgentsAndByHostPrefs() throws {
        let library = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let id = "com.vendor.app"
        let bundlePath = "/Applications/Vendor.app"
        try touch(library, "Group Containers/ABCDE12345.\(id)/data")
        try touch(library, "Group Containers/group.\(id).shared/data")
        try touch(library, "Group Containers/ABCDE12345.com.other.app/data")
        try touch(library, "LaunchAgents/\(id).updater.plist")
        let agent = try PropertyListSerialization.data(
            fromPropertyList: ["Label": "x", "ProgramArguments": ["\(bundlePath)/Contents/MacOS/agent"]],
            format: .xml, options: 0
        )
        try touch(library, "LaunchAgents/net.renamed.agent.plist", contents: agent)
        try touch(library, "LaunchAgents/com.unrelated.plist")
        try touch(library, "Preferences/ByHost/\(id).0A1B2C.plist")
        try touch(library, "Logs/Vendor/log.txt")

        let found = AppLeftoverLocator(library: library.path)
            .candidates(bundleIdentifier: id, appName: "Vendor", bundlePath: bundlePath)
        let names = Set(found.map { ($0.path as NSString).lastPathComponent })
        #expect(names == [
            "ABCDE12345.\(id)", "group.\(id).shared", "\(id).updater.plist",
            "net.renamed.agent.plist", "\(id).0A1B2C.plist", "Vendor"
        ])
        #expect(found.first { $0.path.hasSuffix("/Logs/Vendor") }?.confidence == .inferred)
        // Prefix matches may belong to a sibling app (com.vendor.app.ce) and are not preselected.
        #expect(found.first { $0.path.hasSuffix("\(id).updater.plist") }?.confidence == .inferred)
        #expect(found.first { $0.path.hasSuffix("group.\(id).shared") }?.confidence == .inferred)
        #expect(found.first { $0.path.hasSuffix("net.renamed.agent.plist") }?.confidence == .verified)
        #expect(found.first { $0.path.hasSuffix("ABCDE12345.\(id)") }?.confidence == .verified)
        #expect(found.filter { $0.type == AppLeftoverLocator.launchAgentType }.count == 2)
    }

    @Test func uninstallUnloadsLaunchAgentsBeforeTrashingAndJournals() {
        let home = NSHomeDirectory()
        let bundle = "/Applications/Demo.app"
        let agentPath = "\(home)/Library/LaunchAgents/com.example.demo.helper.plist"
        let files = [
            AppAssociatedFile(name: "Demo.app", path: bundle, fileType: "Application Bundle", size: 5, confidence: .verified, isSelected: true),
            AppAssociatedFile(name: "agent", path: agentPath, fileType: AppLeftoverLocator.launchAgentType, size: 1, confidence: .verified, isSelected: true)
        ]
        let app = InstalledAppItem(name: "Demo", bundleIdentifier: "com.example.demo", bundlePath: bundle, version: "1", isSystemApp: false, associatedFiles: files, isSelected: false)
        var events: [String] = []
        var journal: [(String, CleanupLogEntry.Outcome)] = []
        let result = AppUninstallerEngine.performUninstall(
            app,
            trash: { events.append("trash \($0.path)") },
            unloadLaunchAgent: { events.append("unload \($0.path)") },
            record: { file, outcome, _ in journal.append((file.path, outcome)) }
        )
        #expect(result == .ok)
        #expect(events == ["trash \(bundle)", "unload \(agentPath)", "trash \(agentPath)"])
        #expect(journal.map(\.0) == [bundle, agentPath])
        #expect(journal.allSatisfy { $0.1 == .trashed })
    }

    @Test func uninstallPolicyAllowsNewLeftoverLocations() {
        let home = "/Users/tester"
        let bundle = "/Applications/Demo.app"
        for relative in ["Group Containers/group.x.y.z", "LaunchAgents/x.y.z.plist", "Application Scripts/x.y.z", "Logs/x.y.z", "Cookies/x.y.z.binarycookies"] {
            #expect(UninstallPathPolicy.isAllowed(path: "\(home)/Library/\(relative)", bundlePath: bundle, homeDirectory: home))
        }
        #expect(!UninstallPathPolicy.isAllowed(path: "\(home)/Library/LaunchAgents", bundlePath: bundle, homeDirectory: home))
        #expect(!UninstallPathPolicy.isAllowed(path: "\(home)/Library/Keychains/login.keychain-db", bundlePath: bundle, homeDirectory: home))
    }
}
