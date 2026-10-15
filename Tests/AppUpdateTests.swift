import Foundation
import Testing
@testable import Xmac

@Suite struct AppUpdateTests {
    @Test func versionsAreComparedNumericallyAndRejectInvalidTags() {
        #expect(XmacRelease.isNewer("1.10.0", than: "1.9.9"))
        #expect(!XmacRelease.isNewer("1.1.3", than: "1.1.3"))
        #expect(!XmacRelease.isNewer("1.0.0", than: "1.1.3"))
        #expect(!XmacRelease.isNewer("2.0.0-beta", than: "1.1.3"))
        #expect(!XmacRelease.isNewer("2..0", than: "1.1.3"))
    }

    @Test func installerMustBelongToTheExactOfficialRelease() {
        func release(_ url: String, name: String = "Xmac-1.2.0.dmg") -> XmacRelease {
            XmacRelease(tag_name: "v1.2.0", html_url: URL(string: "https://github.com/trinhhaox/x-mac/releases/tag/v1.2.0")!,
                        body: nil, draft: false, prerelease: false,
                        assets: [.init(name: name, browser_download_url: URL(string: url)!, size: 3, digest: nil)])
        }
        #expect(release("https://github.com/trinhhaox/x-mac/releases/download/v1.2.0/Xmac-1.2.0.dmg").installer != nil)
        #expect(release("https://example.com/Xmac-1.2.0.dmg").installer == nil)
        #expect(release("https://github.com/attacker/x-mac/releases/download/v1.2.0/Xmac-1.2.0.dmg").installer == nil)
        #expect(release("https://github.com/trinhhaox/x-mac/releases/download/v1.1.0/Xmac-1.2.0.dmg").installer == nil)
    }

    @Test func corruptedInstallerIsRejected() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        let digest = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try UpdateInstaller.verify(dmg: file, size: 3, digest: digest)
        #expect(throws: UpdateFailure.self) { try UpdateInstaller.verify(dmg: file, size: 4, digest: digest) }
        try Data("abd".utf8).write(to: file)
        #expect(throws: UpdateFailure.self) { try UpdateInstaller.verify(dmg: file, size: 3, digest: digest) }
    }

    @Test func failedReplacementRestoresOriginalBundle() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("XmacSwapTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("Xmac.app")
        let backup = root.appendingPathComponent("backup.app")
        let missing = root.appendingPathComponent("missing.app")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: target.appendingPathComponent("marker"))
        #expect(throws: (any Error).self) { try UpdateInstaller.replaceBundle(staged: missing, target: target, backup: backup) }
        #expect(try String(contentsOf: target.appendingPathComponent("marker")) == "original")
        #expect(!fm.fileExists(atPath: backup.path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["XMAC_TEST_APP"] != nil))
    func signedBundleCanBeInstalledAndOriginalIsRetained() throws {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["XMAC_TEST_APP"]))
        let version = try #require(Bundle(url: source)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let root = fm.temporaryDirectory.appendingPathComponent("XmacInstallSmoke-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("Xmac.app")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("marker"))
        try UpdateInstaller.installBundle(source: source, version: version, target: target)
        #expect(Bundle(url: target)?.bundleIdentifier == "vn.xmac.app")
        let backups = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("Xmac-before-update-") }
        #expect(backups.count == 1)
        #expect(try String(contentsOf: backups[0].appendingPathComponent("marker")) == "old")
        #expect(throws: UpdateFailure.self) { try UpdateInstaller.installBundle(source: source, version: "0.0.0", target: target) }
    }
}
