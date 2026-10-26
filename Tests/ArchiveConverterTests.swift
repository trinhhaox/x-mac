import Testing
import Foundation
@testable import Xmac

@Suite struct ArchiveConverterTests {
    private let converter = ArchiveConverter()

    private func run(_ tool: String, _ arguments: [String]) async throws {
        try await ConverterWorkspace.run(URL(fileURLWithPath: tool), arguments)
    }

    /// Minimal ustar archive with a single file, built by hand so the entry name can be hostile.
    private func tarBytes(entryName: String, content: String) -> Data {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, at offset: Int) { for (i, byte) in text.utf8.enumerated() { header[offset + i] = byte } }
        let body = Data(content.utf8)
        put(entryName, at: 0)
        put("0000644\0", at: 100)
        put("0000000\0", at: 108)
        put("0000000\0", at: 116)
        put(String(format: "%011o\0", body.count), at: 124)
        put("00000000000\0", at: 136)
        put("        ", at: 148)
        header[156] = UInt8(ascii: "0")
        put("ustar\0", at: 257)
        put("00", at: 263)
        let checksum = header.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o\0 ", checksum), at: 148)
        var data = Data(header) + body
        data.append(Data(repeating: 0, count: (512 - body.count % 512) % 512))
        data.append(Data(repeating: 0, count: 1024))
        return data
    }

    @Test func offersExtractOnlyForArchives() {
        func ids(_ name: String) -> [String] { converter.targets(for: URL(fileURLWithPath: "/x/\(name)")).map(\.id) }
        #expect(ids("a.zip") == ["archive.extract", "archive.zip"])
        #expect(ids("a.TAR.GZ") == ["archive.extract", "archive.zip"])
        #expect(ids("a.7z") == ["archive.extract", "archive.zip"])
        #expect(ids("photo.jpg") == ["archive.zip"])
        let zip = converter.targets(for: URL(fileURLWithPath: "/x/p.jpg"))[0]
        #expect(zip.combinesInputs && zip.fileExtension == "zip")
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.zip"))[0].fileExtension.isEmpty)
    }

    @Test func detectsUnsafeEntries() {
        let listing = "ok/file.txt\n../evil\n/etc/passwd\na/../../b\nfine..name\n"
        #expect(ArchiveConverter.unsafeEntries(in: listing) == ["../evil", "/etc/passwd", "a/../../b"])
        #expect(ArchiveConverter.unsafeEntries(in: "").isEmpty)
    }

    @Test func zipsMultipleInputsAndExtractsThemBack() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("a.txt")
        let folder = dir.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: folder.appendingPathComponent("b.txt"))

        let target = try #require(converter.targets(for: first).first { $0.id == "archive.zip" })
        let zipURL = dir.appendingPathComponent("bundle.zip")
        try await converter.convert(
            ConversionRequest(inputs: [first, folder, first], target: target, preset: ConversionPreset(), outputURL: zipURL)
        ) { _ in }

        let extract = try ConverterToolTestSupport.request(converter, input: zipURL, targetID: "archive.extract", outputIn: dir)
        try await converter.convert(extract) { _ in }
        let root = extract.outputURL
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt")) == "one")
        #expect(try String(contentsOf: root.appendingPathComponent("a 2.txt")) == "one")
        #expect(try String(contentsOf: root.appendingPathComponent("docs/b.txt")) == "two")
    }

    @Test func zipsSingleFileKeepingItsName() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("solo.txt")
        try Data("solo".utf8).write(to: file)
        let request = try ConverterToolTestSupport.request(converter, input: file, targetID: "archive.zip", outputIn: dir)
        try await converter.convert(request) { _ in }
        let listing = try await ConverterWorkspace.run(URL(fileURLWithPath: "/usr/bin/zipinfo"), ["-1", request.outputURL.path])
        #expect(String(decoding: listing.stdout, as: UTF8.self).contains("solo.txt"))
    }

    @Test func extractsTarGz() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = dir.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: payload.appendingPathComponent("h.txt"))
        let archive = dir.appendingPathComponent("p.tar.gz")
        try await run("/usr/bin/tar", ["-czf", archive.path, "-C", payload.path, "h.txt"])

        let request = try ConverterToolTestSupport.request(converter, input: archive, targetID: "archive.extract", outputIn: dir)
        try await converter.convert(request) { _ in }
        #expect(try String(contentsOf: request.outputURL.appendingPathComponent("h.txt")) == "hello")
    }

    @Test(arguments: ["../evil.txt", "/tmp/xmac-evil.txt", "ok/../../evil.txt"])
    func rejectsMaliciousTarEntries(entry: String) async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = dir.appendingPathComponent("evil.tar")
        try tarBytes(entryName: entry, content: "boom").write(to: archive)
        let request = try ConverterToolTestSupport.request(converter, input: archive, targetID: "archive.extract", outputIn: dir)
        await #expect(throws: ConversionError.self) { try await converter.convert(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: request.outputURL.path))
        #expect(!FileManager.default.fileExists(atPath: "/tmp/xmac-evil.txt"))
    }

    @Test func corruptZipThrowsAndLeavesNoOutput() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = dir.appendingPathComponent("bad.zip")
        try Data("PK not really".utf8).write(to: archive)
        let request = try ConverterToolTestSupport.request(converter, input: archive, targetID: "archive.extract", outputIn: dir)
        await #expect(throws: ConversionError.self) { try await converter.convert(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: request.outputURL.path))
    }
}
