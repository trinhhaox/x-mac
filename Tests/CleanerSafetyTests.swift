import Foundation
import Testing
@testable import Xmac

@Suite(.serialized) struct CleanerSafetyTests {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("XmacCleanerSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func mkdir(_ home: URL, _ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func symlinkedCachesRootCannotSteerDeletionIntoDocuments() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let documents = try mkdir(home, "Documents")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Library/Caches"),
            withDestinationURL: documents
        )
        let victim = try mkdir(home, "Documents/thesis")
        #expect(!CleanerPathPolicy.isAllowed(itemPath: victim.path, homeDirectory: home.path))
        #expect(!CleanerPathPolicy.isAllowed(itemPath: home.path + "/Library/Caches/thesis", homeDirectory: home.path))
    }

    @Test func pathPolicyCoversDeveloperCachesAndLeftovers() {
        let home = "/Users/tester"
        #expect(CleanerPathPolicy.isAllowed(itemPath: "\(home)/.npm/_cacache", homeDirectory: home))
        #expect(!CleanerPathPolicy.isAllowed(itemPath: "\(home)/.npm", homeDirectory: home))
        #expect(!CleanerPathPolicy.isAllowed(itemPath: "\(home)/.npm/_logs", homeDirectory: home))
        #expect(CleanerPathPolicy.isAllowed(itemPath: "\(home)/Library/Developer/Xcode/iOS DeviceSupport/16.0 (20A362)", homeDirectory: home))
        #expect(CleanerPathPolicy.isAllowed(itemPath: "\(home)/Library/Application Support/com.vendor.gone", homeDirectory: home))
        #expect(CleanerPathPolicy.isAllowed(itemPath: "\(home)/Library/Preferences/com.vendor.gone.plist", homeDirectory: home))
        #expect(!CleanerPathPolicy.isAllowed(itemPath: "\(home)/Library/Application Support/Google", homeDirectory: home))
        #expect(!CleanerPathPolicy.isAllowed(itemPath: "\(home)/Library/Application Support/com.vendor.gone/db", homeDirectory: home))
        #expect(!CleanerPathPolicy.isAllowed(itemPath: "\(home)/Library/Caches/../../Documents", homeDirectory: home))
        #expect(!CleanerPathPolicy.isAllowed(itemPath: "\(home)/Documents/com.vendor.gone", homeDirectory: home))
    }

    @Test func bundleIdentifierNamesAreRecognised() {
        #expect(BundleIdentifierName.identifier(fromItemName: "com.vendor.app") == "com.vendor.app")
        #expect(BundleIdentifierName.identifier(fromItemName: "com.vendor.app.plist") == "com.vendor.app")
        #expect(BundleIdentifierName.identifier(fromItemName: "com.vendor.app.savedState") == "com.vendor.app")
        #expect(BundleIdentifierName.identifier(fromItemName: "Google") == nil)
        #expect(BundleIdentifierName.identifier(fromItemName: "vendor.app") == nil)
        #expect(BundleIdentifierName.identifier(fromItemName: "com..app") == nil)
    }

    @Test func openFileSnapshotMarksAncestorsInUse() {
        let output = "p123\nf4\nn/Users/t/Library/Caches/Google/Chrome/data_0\nf5\nn/Users/t/.npm/_cacache/index\nnpipe\n"
        let paths = OpenFileSnapshot.parse(lsofOutput: output)
        #expect(paths == ["/Users/t/Library/Caches/Google/Chrome/data_0", "/Users/t/.npm/_cacache/index"])
        let snapshot = OpenFileSnapshot(openPaths: paths)
        #expect(snapshot.isInUse("/Users/t/Library/Caches/Google"))
        #expect(snapshot.isInUse("/Users/t/.npm/_cacache"))
        #expect(!snapshot.isInUse("/Users/t/Library/Caches/Firefox"))
    }

    @Test func openFilePathsWithParenthesesAreNotTruncated() {
        let device = "/Users/t/Library/Developer/Xcode/iOS DeviceSupport/iPhone14,5 16.4.1 (20E252)"
        let paths = OpenFileSnapshot.parse(lsofOutput: "p9\nn\(device)/Symbols/usr/lib/dyld\n")
        #expect(paths == ["\(device)/Symbols/usr/lib/dyld"])
        let snapshot = OpenFileSnapshot(openPaths: paths)
        #expect(snapshot.isInUse(device))
        #expect(snapshot.isInUse(device.uppercased()))
        #expect(!snapshot.isInUse("/Users/t/Library/Developer/Xcode/iOS DeviceSupport/iPhone14,5 16.4.1"))
    }

    @Test func relativeComponentsAreRejectedBeforeNormalisation() {
        let home = "/Users/tester"
        #expect(!CleanerPathPolicy.isAllowed(itemPath: "\(home)/Library/Caches/lnk/../foo", homeDirectory: home))
        #expect(!CleanerPathPolicy.isAllowed(itemPath: "\(home)/Library/Caches/./foo", homeDirectory: home))
        #expect(!UninstallPathPolicy.isAllowed(path: "\(home)/Library/Caches/x/../y", bundlePath: "/Applications/A.app", homeDirectory: home))
    }

    @Test func protectedChildProtectsItsParent() {
        let protected = ["/Users/t/Library/Caches/com.x/keep"]
        #expect(CleanerWhitelist.isProtected("/Users/t/Library/Caches/com.x", by: protected))
        #expect(!CleanerWhitelist.isProtected("/Users/t/Library/Caches/com.y", by: protected))
    }

    @Test func scannerNeverOffersItemsUnderASymlinkedRoot() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let documents = try mkdir(home, "Documents")
        try Data(count: 100 * 1024).write(to: documents.appendingPathComponent("thesis.pdf"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches"), withDestinationURL: documents)
        let categories = JunkScanner(homeDirectory: home.path).scanAll()
        #expect(categories.allSatisfy { $0.items.isEmpty })
    }

    @Test func cleanerDecisionFailsClosed() {
        let home = "/Users/tester"
        let item = JunkItem(name: "Google", path: "\(home)/Library/Caches/Google", size: 1, isSelected: true)
        let idle = OpenFileSnapshot(openPaths: ["/Users/tester/Library/Caches/Other/x"])
        let busy = OpenFileSnapshot(openPaths: ["/Users/tester/Library/Caches/Google/x"])
        func decide(_ item: JunkItem, protected: [String] = [], open: OpenFileSnapshot?) -> CleanerEngine.Decision {
            CleanerEngine.decide(item: item, protectedPaths: protected, openFiles: open, runningBundleIdentifiers: [], homeDirectory: home)
        }
        #expect(decide(item, open: idle) == .trash)
        #expect(decide(item, open: busy) == .skip(reason: "in use"))
        #expect(decide(item, open: nil) == .skip(reason: "open-file check unavailable"))
        #expect(decide(item, protected: ["\(home)/Library/Caches"], open: idle) == .skip(reason: "whitelisted"))
        let trashed = JunkItem(name: "old", path: "\(home)/.Trash/old", size: 1, isSelected: true)
        #expect(decide(trashed, open: nil) == .deletePermanently)
        let outside = JunkItem(name: "x", path: "\(home)/Documents/x", size: 1, isSelected: true)
        #expect(decide(outside, open: idle) == .reject)
    }

    @Test func orphanDetectionKeepsAnythingThatMayStillExist() {
        let installed: Set<String> = ["com.vendor.editor"]
        func orphan(_ id: String, registered: Bool = false, running: Set<String> = []) -> Bool {
            OrphanedAppDataScanner.isOrphan(bundleIdentifier: id, installed: installed, running: running, isRegistered: { _ in registered })
        }
        #expect(orphan("com.gone.app"))
        #expect(!orphan("com.vendor.editor"))
        #expect(!orphan("com.vendor.editor.helper"))
        #expect(!orphan("com.vendor.office"))
        #expect(orphan("org.vendor.editor"))
        #expect(!orphan("COM.VENDOR.EDITOR"))
        #expect(!orphan("com.apple.Music"))
        #expect(!orphan("com.gone.app", registered: true))
        #expect(!orphan("com.gone.app", running: ["com.gone.app"]))
    }

    @Test func orphanScanRequiresThirtyIdleDays() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let longAgo = Date().addingTimeInterval(-40 * 86_400)
        let old = try mkdir(home, "Library/Application Support/com.gone.old")
        // Top folder looks old, but an app is still writing a nested database.
        let active = try mkdir(home, "Library/Application Support/net.active.app")
        let nested = try mkdir(home, "Library/Application Support/net.active.app/db")
        try Data("x".utf8).write(to: nested.appendingPathComponent("store.sqlite"))
        _ = try mkdir(home, "Library/Application Support/com.gone.fresh")
        _ = try mkdir(home, "Library/Application Support/Google")
        for url in [old, nested, active] {
            try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: url.path)
        }

        let found = OrphanedAppDataScanner.scan(homeDirectory: home.path, installed: [], running: [], isRegistered: { _ in false })
        #expect(found.map(\.bundleIdentifier) == ["com.gone.old"])
    }
}
