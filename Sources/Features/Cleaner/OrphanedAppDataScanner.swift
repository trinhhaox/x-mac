import Cocoa

/// Finds ~/Library entries named after apps that are no longer installed.
///
/// Every result is a guess, so it is offered unselected. An entry is kept when any signal
/// says its owner may still exist: any installed bundle (app, input method, preference pane,
/// plug-in) or running app from the same vendor, a Launch Services registration, Apple's own
/// domain, or any change inside it within 30 days.
enum OrphanedAppDataScanner {
    /// ~/Library/Containers is skipped: reading other apps' containers raises a privacy prompt.
    /// ~/Library/Caches is skipped: every entry there is already offered under User Caches.
    static let scannedFolders = [
        "Library/Application Support",
        "Library/Preferences",
        "Library/Saved Application State",
        "Library/HTTPStorages",
        "Library/WebKit"
    ]

    static let minimumIdleDays: Double = 30

    struct Candidate: Equatable {
        let bundleIdentifier: String
        let path: String
        let folder: String
    }

    /// `com.vendor` of `com.vendor.app`: data of a vendor that still has software installed is
    /// never offered, because suites share folders across ids (`com.microsoft.office` / `com.microsoft.Word`).
    static func vendor(of id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    static func isOrphan(
        bundleIdentifier id: String,
        installed: Set<String>,
        running: Set<String>,
        isRegistered: (String) -> Bool
    ) -> Bool {
        let candidateVendor = vendor(of: id)
        if candidateVendor == "com.apple" { return false }
        if installed.union(running).contains(where: { !$0.isEmpty && vendor(of: $0) == candidateVendor }) {
            return false
        }
        return !isRegistered(id)
    }

    static let maxEntriesInspected = 2_000
    static let maxDepthInspected = 3

    /// Newest modification date of the entry and of what is inside it (bounded walk).
    /// A folder's own date only changes when direct children are added or removed, so an app
    /// writing `db/store.sqlite` daily would otherwise look idle. Nil when the walk hits its limit.
    static func newestModification(atPath path: String, fileManager: FileManager = .default) -> Date? {
        let root = URL(fileURLWithPath: path)
        guard var newest = (try? root.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return nil
        }
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return newest
        }
        var inspected = 0
        for case let url as URL in enumerator {
            inspected += 1
            if inspected > maxEntriesInspected { return nil }
            if enumerator.level >= maxDepthInspected { enumerator.skipDescendants() }
            if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, date > newest {
                newest = date
            }
        }
        return newest
    }

    static func isIdle(modifiedAt date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) >= minimumIdleDays * 86_400
    }

    static func scan(
        homeDirectory: String = NSHomeDirectory(),
        installed: Set<String>,
        running: Set<String>,
        isRegistered: (String) -> Bool,
        fileManager: FileManager = .default
    ) -> [Candidate] {
        var results: [Candidate] = []
        for folder in scannedFolders {
            let directory = (homeDirectory as NSString).appendingPathComponent(folder)
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for name in names {
                guard let id = BundleIdentifierName.identifier(fromItemName: name),
                      isOrphan(bundleIdentifier: id, installed: installed, running: running, isRegistered: isRegistered)
                else { continue }
                let path = (directory as NSString).appendingPathComponent(name)
                guard isIdle(modifiedAt: newestModification(atPath: path, fileManager: fileManager)) else { continue }
                results.append(Candidate(bundleIdentifier: id, path: path, folder: (folder as NSString).lastPathComponent))
            }
        }
        return results
    }

    /// Places software is installed, searched two levels deep (Setapp, Utilities, vendor folders).
    static var installRoots: [String] {
        let home = NSHomeDirectory()
        return [
            "/Applications", "/System/Applications", "\(home)/Applications",
            "/Library/Input Methods", "\(home)/Library/Input Methods",
            "/Library/PreferencePanes", "\(home)/Library/PreferencePanes",
            "/Library/Application Support", "/Library/Internet Plug-Ins", "/Library/Screen Savers"
        ]
    }

    static let bundleExtensions: Set<String> = ["app", "prefpane", "bundle", "plugin", "saver", "component", "appex"]

    /// Bundle ids of everything installed in `installRoots`, including input methods and preference panes.
    static func installedBundleIdentifiers(roots: [String] = installRoots, fileManager: FileManager = .default) -> Set<String> {
        var ids = Set<String>()
        func visit(_ directory: String, depth: Int) {
            guard depth <= 2, let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
            for name in names where !name.hasPrefix(".") {
                let path = (directory as NSString).appendingPathComponent(name)
                if bundleExtensions.contains((name as NSString).pathExtension.lowercased()) {
                    if let id = Bundle(path: path)?.bundleIdentifier { ids.insert(id) }
                } else {
                    visit(path, depth: depth + 1)
                }
            }
        }
        for root in roots { visit(root, depth: 1) }
        return ids
    }

    static func isRegisteredWithLaunchServices(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}
