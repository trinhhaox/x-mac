import Testing
import Foundation
@testable import Xmac

@Suite struct BinaryLocatorTests {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeFile(_ name: String, in dir: URL, executable: Bool) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "locator-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func findsExecutableInExtraCandidates() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = try makeFile("ffmpeg", in: dir, executable: true)
        let locator = BinaryLocator(defaults: isolatedDefaults(), extraCandidates: [.ffmpeg: [fake.path]])
        #expect(locator.locate(.ffmpeg) == fake)
    }

    @Test func rejectsNonExecutableAndDirectories() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = try makeFile("ffprobe", in: dir, executable: false)
        let locator = BinaryLocator(defaults: isolatedDefaults(), extraCandidates: [.ffprobe: [plain.path, dir.path]])
        let located = locator.locate(.ffprobe)
        #expect(located != plain)
        #expect(located != dir)
    }

    @Test func overrideTakesPrecedence() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let extra = try makeFile("extra", in: dir, executable: true)
        let chosen = try makeFile("chosen", in: dir, executable: true)
        let defaults = isolatedDefaults()
        defaults.set(chosen.path, forKey: ExternalTool.soffice.overrideDefaultsKey)
        let locator = BinaryLocator(defaults: defaults, extraCandidates: [.soffice: [extra.path]])
        #expect(locator.locate(.soffice) == chosen)
    }

    @Test func invalidOverrideIsNotReplacedByCandidates() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let extra = try makeFile("extra", in: dir, executable: true)
        let defaults = isolatedDefaults()
        defaults.set(dir.appendingPathComponent("missing").path, forKey: ExternalTool.ffmpeg.overrideDefaultsKey)
        let locator = BinaryLocator(defaults: defaults, extraCandidates: [.ffmpeg: [extra.path]])
        #expect(locator.locate(.ffmpeg) == nil)
    }

    @Test func followsSymlinkToExecutable() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = try makeFile("real", in: dir, executable: true)
        let link = dir.appendingPathComponent("ffmpeg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let locator = BinaryLocator(defaults: isolatedDefaults(), extraCandidates: [.ffmpeg: [link.path]])
        #expect(locator.locate(.ffmpeg) == link)
    }
}
