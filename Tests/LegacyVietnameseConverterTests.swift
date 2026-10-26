import Foundation
import Testing
@testable import Xmac

@Suite struct LegacyVietnameseConverterTests {
    private let converter = LegacyVietnameseConverter()

    private func convert(_ data: Data, ext: String, targetSuffix: String) async throws -> String {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("file.\(ext)")
        try data.write(to: input)
        let target = try #require(converter.targets(for: input).first { $0.id.hasSuffix(targetSuffix) })
        let output = dir.appendingPathComponent("out.\(ext)")
        try await converter.convert(ConverterFixtures.request([input], target, output: output), progress: { _ in })
        return try String(contentsOf: output, encoding: .utf8)
    }

    private func latin1(_ text: String) throws -> Data { try #require(text.data(using: .isoLatin1)) }

    @Test func offersTwoTargetsKeepingTheInputExtension() {
        let targets = converter.targets(for: URL(fileURLWithPath: "/tmp/a.SRT"))
        #expect(targets.map(\.id) == ["vn-legacy.tcvn3", "vn-legacy.vni"])
        #expect(targets.map(\.fileExtension) == ["srt", "srt"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.docx")).isEmpty)
        for ext in ["txt", "vtt", "ass", "csv", "html", "htm", "md"] {
            #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.\(ext)")).count == 2)
        }
    }

    @Test func tcvn3TextFileBecomesUTF8() async throws {
        let result = try await convert(latin1("ViÖt Nam\nHµ Néi\n"), ext: "txt", targetSuffix: "tcvn3")
        #expect(result == "Việt Nam\nHà Nội\n")
    }

    @Test func vniSubtitleKeepsStructure() async throws {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nVieät Nam\n"
        let result = try await convert(latin1(srt), ext: "srt", targetSuffix: "vni")
        #expect(result == "1\n00:00:01,000 --> 00:00:02,000\nViệt Nam\n")
    }

    @Test func utf8InputWithLegacyGlyphsIsConverted() async throws {
        let result = try await convert(Data("Vieät Nam".utf8), ext: "md", targetSuffix: "vni")
        #expect(result == "Việt Nam")
    }

    @Test func alreadyUnicodeFileIsKept() async throws {
        let result = try await convert(Data("Việt Nam".utf8), ext: "txt", targetSuffix: "tcvn3")
        #expect(result == "Việt Nam")
    }

    @Test func htmlCharsetDeclarationBecomesUTF8() async throws {
        let html = "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=windows-1252\"></head><body>ViÖt</body></html>"
        let result = try await convert(latin1(html), ext: "html", targetSuffix: "tcvn3")
        #expect(result.contains("charset=utf-8"))
        #expect(!result.contains("windows-1252"))
        #expect(result.contains("<body>Việt</body>"))
    }

    @Test func utf8BOMIsDropped() async throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("Vieät".utf8)
        #expect(try await convert(data, ext: "txt", targetSuffix: "vni") == "Việt")
    }

    @Test func rejectsUnknownTarget() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: input)
        let bogus = ConversionTarget(id: "vn-legacy.other", title: "x", fileExtension: "txt", group: .document)
        await #expect(throws: ConversionError.self) {
            try await converter.convert(
                ConverterFixtures.request([input], bogus, output: dir.appendingPathComponent("o.txt")), progress: { _ in })
        }
    }
}
