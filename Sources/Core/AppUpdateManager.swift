import AppKit
import CryptoKit
import Foundation
import Security

struct XmacRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int64
        let digest: String?
    }
    let tag_name: String
    let html_url: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    var version: String { String(tag_name.dropFirst(tag_name.hasPrefix("v") ? 1 : 0)) }
    var installer: Asset? {
        assets.first {
            $0.name == "Xmac-\(version).dmg"
                && $0.browser_download_url.scheme == "https"
                && $0.browser_download_url.host == "github.com"
                && $0.browser_download_url.path == "/trinhhaox/x-mac/releases/download/\(tag_name)/\($0.name)"
        }
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        func parts(_ value: String) -> [Int]? {
            let fields = value.split(separator: ".", omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            let numbers = fields.compactMap { field -> Int? in
                guard !field.isEmpty, field.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
                return Int(field)
            }
            return numbers.count == 3 ? numbers : nil
        }
        guard let lhs = parts(candidate), let rhs = parts(installed) else { return false }
        return rhs.lexicographicallyPrecedes(lhs)
    }
}

@MainActor final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()
    @Published private(set) var release: XmacRelease?
    @Published private(set) var busy = false
    @Published private(set) var downloadProgress: Double?
    @Published var confirmInstallation = false
    @Published private(set) var message = L10n.text("Chưa kiểm tra bản cập nhật.")
    @Published var automaticChecks = UserDefaults.standard.bool(forKey: "Updates.AutomaticChecks") {
        didSet {
            UserDefaults.standard.set(automaticChecks, forKey: "Updates.AutomaticChecks")
            checkIfDue()
        }
    }
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        checkIfDue()
    }

    func checkIfDue() {
        guard automaticChecks,
              Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: "Updates.LastCheck") > 86400 else { return }
        Task { await check() }
    }

    func check() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        message = L10n.text("Đang kiểm tra GitHub Releases…")
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/trinhhaox/x-mac/releases/latest")!)
            request.timeoutInterval = 30
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateFailure(L10n.text("Không thể đọc bản phát hành. Vui lòng thử lại sau.")) }
            let latest = try JSONDecoder().decode(XmacRelease.self, from: data)
            guard !latest.draft, !latest.prerelease,
                  latest.html_url.scheme == "https", latest.html_url.host == "github.com",
                  latest.html_url.path == "/trinhhaox/x-mac/releases/tag/\(latest.tag_name)" else {
                throw UpdateFailure(L10n.text("Thông tin bản phát hành không hợp lệ."))
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Updates.LastCheck")
            if XmacRelease.isNewer(latest.version, than: AppVersionInfo.current.version) {
                release = latest
                message = L10n.format("Có Xmac %@.", latest.version)
            } else {
                release = nil
                message = L10n.text("Bạn đang dùng bản Xmac mới nhất.")
            }
        } catch { message = error.localizedDescription }
    }

    func install() async {
        guard !busy, let release, let asset = release.installer else { return }
        busy = true
        defer { busy = false; downloadProgress = nil }
        message = L10n.text("Đang tải và xác minh bản cập nhật…")
        do {
            guard let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71 else {
                throw UpdateFailure(L10n.text("Bản phát hành chưa có SHA-256 để xác minh. Hãy tải từ trang phát hành."))
            }
            let file = try await InstallerDownload().fetch(asset.browser_download_url) { [weak self] fraction in
                Task { @MainActor in self?.downloadProgress = fraction }
            }
            defer { try? FileManager.default.removeItem(at: file) }
            downloadProgress = nil
            let target = Bundle.main.bundleURL
            message = L10n.text("Đang kiểm tra và cài đặt. Xmac sẽ mở lại sau khi hoàn tất…")
            try await Task.detached {
                try UpdateInstaller.install(dmg: file, asset: asset, version: release.version, target: target)
            }.value
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            // The application path is passed as an argument, never shell code.
            relaunch.arguments = ["-c", "sleep 2; /usr/bin/open \"$1\"", "xmac-relaunch", target.path]
            try relaunch.run()
            NSApp.terminate(nil)
        } catch { message = error.localizedDescription }
    }
}

/// Code-signing identity of an app bundle, as far as the update decision needs it.
struct UpdateIdentity: Equatable {
    var bundleIdentifier: String?
    /// nil for ad-hoc or unsigned code.
    var teamIdentifier: String?
    /// false when Security could not read the signature at all; trust then fails closed
    /// instead of silently dropping to bundle-identifier-only checks.
    var signingInfoReadable = true

    static func read(from url: URL) -> UpdateIdentity {
        var teamID: String?
        var readable = false
        var code: SecStaticCode?
        if SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code {
            var info: CFDictionary?
            if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess {
                readable = true
                teamID = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
            }
        }
        return UpdateIdentity(
            bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
            teamIdentifier: teamID,
            signingInfoReadable: readable
        )
    }
}

enum UpdateTrust {
    enum Policy: Equatable {
        /// The running app has a Team ID: the update must be signed by Apple-issued certificate of that team.
        case teamPinned(String)
        /// Ad-hoc running app: only the bundle identifier can be compared (limited trust).
        case bundleIdentifierOnly
    }

    /// nil when the running app reports a Team ID that is not a well-formed 10-character identifier (fail closed).
    static func policy(runningTeamID: String?) -> Policy? {
        guard let team = runningTeamID, !team.isEmpty else { return .bundleIdentifierOnly }
        guard team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { return nil }
        return .teamPinned(team)
    }

    static func requirement(teamID: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    static func isAcceptable(policy: Policy, runningBundleID: String?, candidateBundleID: String?, candidateMeetsTeamRequirement: Bool) -> Bool {
        guard let running = runningBundleID, !running.isEmpty, running == candidateBundleID else { return false }
        switch policy {
        case .teamPinned: return candidateMeetsTeamRequirement
        case .bundleIdentifierOnly: return true
        }
    }

    static func verify(candidate: URL, running: UpdateIdentity) throws {
        let failure = UpdateFailure(L10n.text("Chữ ký của bản cập nhật không khớp với ứng dụng đang chạy. Đã hủy cài đặt."))
        guard running.signingInfoReadable,
              let policy = policy(runningTeamID: running.teamIdentifier) else { throw failure }
        var meetsTeam = false
        if case .teamPinned(let team) = policy {
            meetsTeam = candidateSatisfies(requirement(teamID: team), at: candidate)
        } else {
            NSLog("Xmac update: running app is ad-hoc signed; only the bundle identifier is checked (limited trust).")
        }
        let candidateID = UpdateIdentity.read(from: candidate).bundleIdentifier
        guard isAcceptable(policy: policy, runningBundleID: running.bundleIdentifier,
                           candidateBundleID: candidateID, candidateMeetsTeamRequirement: meetsTeam) else { throw failure }
    }

    private static func candidateSatisfies(_ requirementText: String, at url: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }
}

struct UpdateFailure: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

enum UpdateInstaller {
    static func verify(dmg: URL, size: Int64, digest: String) throws {
        let handle = try FileHandle(forReadingFrom: dmg)
        defer { try? handle.close() }
        var hash = SHA256()
        var count: Int64 = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            count += Int64(chunk.count)
            hash.update(data: chunk)
        }
        let actual = "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == size, actual == digest else { throw UpdateFailure(L10n.text("Tệp cập nhật sai kích thước hoặc SHA-256. Đã hủy cài đặt.")) }
    }

    static func install(dmg: URL, asset: XmacRelease.Asset, version: String, target: URL) throws {
        try verify(dmg: dmg, size: asset.size, digest: asset.digest ?? "")
        let fm = FileManager.default
        let parentDirectory = target.deletingLastPathComponent().standardizedFileURL
        let allowedParents = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        guard target.pathExtension == "app", target.lastPathComponent == "Xmac.app",
              allowedParents.contains(where: { $0.standardizedFileURL == parentDirectory }),
              (try fm.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType) == .typeDirectory,
              fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateFailure(L10n.text("Hãy đặt Xmac trong thư mục Applications có quyền ghi trước khi cập nhật."))
        }
        let root = fm.temporaryDirectory.appendingPathComponent("XmacUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let mount = root.appendingPathComponent("volume")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
        let source = mount.appendingPathComponent("Xmac.app")
        try installBundle(source: source, version: version, target: target)
    }

    /// `running` is the identity of the app being replaced; defaults to the current process's bundle.
    static func installBundle(source: URL, version: String, target: URL, running: UpdateIdentity? = nil) throws {
        let fm = FileManager.default
        guard (try fm.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType) == .typeDirectory,
              let bundle = Bundle(url: source), bundle.bundleIdentifier == "vn.xmac.app",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            throw UpdateFailure(L10n.text("Ứng dụng trong bản cập nhật không đúng định danh hoặc phiên bản."))
        }
        let identity = running ?? UpdateIdentity.read(from: Bundle.main.bundleURL)
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
        try UpdateTrust.verify(candidate: source, running: identity)
        let parent = target.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".Xmac-update-\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent("Xmac-before-update-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: staged) }
        try fm.copyItem(at: source, to: staged)
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        try UpdateTrust.verify(candidate: staged, running: identity)
        try replaceBundle(staged: staged, target: target, backup: backup)
        // The new bundle is in place and verified; the backup is only needed while a rollback is still possible.
        discardBackup(backup)
    }

    private static func discardBackup(_ backup: URL) {
        let fm = FileManager.default
        do { try fm.trashItem(at: backup, resultingItemURL: nil) }
        catch {
            do { try fm.removeItem(at: backup) }
            catch { NSLog("Xmac update: could not remove backup %@: %@", backup.path, error.localizedDescription) }
        }
    }

    static func replaceBundle(staged: URL, target: URL, backup: URL) throws {
        let fm = FileManager.default
        try fm.moveItem(at: target, to: backup)
        do { try fm.moveItem(at: staged, to: target) }
        catch {
            try fm.moveItem(at: backup, to: target)
            throw error
        }
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure(L10n.format("Không thể xác minh hoặc mở bộ cài đặt (%@).", URL(fileURLWithPath: path).lastPathComponent)) }
    }
}

private final class InstallerDownload: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: ((Double) -> Void)?
    private var downloadedFile: URL?

    func fetch(_ url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        self.progress = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress?(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("XmacInstaller-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: file)
            downloadedFile = file
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil; session.finishTasksAndInvalidate() }
        if let error { continuation?.resume(throwing: error) }
        else if let downloadedFile { continuation?.resume(returning: downloadedFile) }
        else { continuation?.resume(throwing: UpdateFailure(L10n.text("Tải bản cập nhật thất bại."))) }
    }
}
