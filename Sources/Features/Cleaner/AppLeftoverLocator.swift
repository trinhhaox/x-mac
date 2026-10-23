import Foundation

/// Finds the support files an app leaves in ~/Library.
///
/// `verified` = named exactly after the bundle id (or a launch agent that runs code from the
/// bundle) and is preselected; `inferred` = matched by display name and left for the user.
struct AppLeftoverLocator {
    struct Candidate: Equatable {
        let path: String
        let type: String
        let confidence: AssociationConfidence
    }

    static let launchAgentType = "Launch Agent"

    let library: String
    var fileManager: FileManager = .default

    /// Callers must pass only ids/names accepted by `AppUninstallPolicy.isSafePathComponent`.
    func candidates(bundleIdentifier id: String, appName: String, bundlePath: String) -> [Candidate] {
        var found: [Candidate] = []
        func add(_ relative: String, _ type: String, _ confidence: AssociationConfidence = .verified) {
            let path = (library as NSString).appendingPathComponent(relative)
            guard fileManager.fileExists(atPath: path), !found.contains(where: { $0.path == path }) else { return }
            found.append(Candidate(path: path, type: type, confidence: confidence))
        }

        add("Application Support/\(id)", "Application Support")
        add("Application Support/\(appName)", "Application Support", .inferred)
        add("Caches/\(id)", "Caches")
        add("Caches/\(appName)", "Caches", .inferred)
        add("Preferences/\(id).plist", "Preferences")
        add("Saved Application State/\(id).savedState", "Saved State")
        add("Containers/\(id)", "Sandbox Container")
        add("WebKit/\(id)", "WebKit Data")
        add("HTTPStorages/\(id)", "HTTP Storages")
        add("HTTPStorages/\(id).binarycookies", "HTTP Storages")
        add("Cookies/\(id).binarycookies", "Cookies")
        add("Application Scripts/\(id)", "Application Scripts")
        add("Logs/\(id)", "Logs")
        add("Logs/\(appName)", "Logs", .inferred)

        // A plain "<id>." prefix also matches a sibling app whose id extends this one
        // (com.jetbrains.intellij vs com.jetbrains.intellij.ce), so such matches are only inferred.
        for name in children("Preferences/ByHost") where name.hasPrefix(id + ".") && name.hasSuffix(".plist") {
            let host = name.dropFirst(id.count + 1).dropLast(".plist".count)
            add("Preferences/ByHost/\(name)", "Preferences", host.contains(".") ? .inferred : .verified)
        }
        for name in children("Group Containers") {
            if let confidence = Self.groupContainerConfidence(name, of: id) {
                add("Group Containers/\(name)", "Group Container", confidence)
            }
        }
        for name in children("LaunchAgents") where name.hasSuffix(".plist") {
            let path = (library as NSString).appendingPathComponent("LaunchAgents/\(name)")
            if name == "\(id).plist" || Self.launchAgent(atPath: path, runsCodeFrom: bundlePath) {
                add("LaunchAgents/\(name)", Self.launchAgentType)
            } else if name.hasPrefix(id + ".") {
                add("LaunchAgents/\(name)", Self.launchAgentType, .inferred)
            }
        }
        return found
    }

    /// `group.<id>` or `<TEAMID>.<id>` are verified; `group.<id>.*` may belong to a sibling app.
    static func groupContainerConfidence(_ name: String, of id: String) -> AssociationConfidence? {
        if name == "group.\(id)" { return .verified }
        if name.hasPrefix("group.\(id).") { return .inferred }
        guard name.hasSuffix(".\(id)") else { return nil }
        let prefix = name.dropLast(id.count + 1)
        return prefix.count == 10 && prefix.allSatisfy { $0.isUppercase || $0.isNumber } ? .verified : nil
    }

    static func launchAgent(atPath path: String, runsCodeFrom bundlePath: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        guard let program else { return false }
        return program.hasPrefix(bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/")
    }

    private func children(_ relative: String) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: (library as NSString).appendingPathComponent(relative))) ?? []
    }
}

enum LaunchAgentControl {
    /// Unloads a user launch agent so it does not respawn from the Trash. Failure (not loaded) is fine.
    static func bootOut(_ plist: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", plist.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            NSLog("Xmac Uninstall: launchctl bootout failed for \(plist.path): \(error)")
            return
        }
        // bootout waits for the job to stop; do not let a stuck job hang the uninstall.
        if exited.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            NSLog("Xmac Uninstall: launchctl bootout timed out for \(plist.path)")
        }
    }
}
