import Foundation
import Testing
@testable import Xmac

@Suite struct SubtitleConverterTests {
    private let converter = SubtitleConverter()
    private let srt = "1\n00:00:01,500 --> 00:00:03,000\nXin chào\nthế giới\n\n2\n00:01:00,000 --> 00:01:02,250\nTạm biệt\n"

    private func convert(_ text: String, from: String, to: String, encoding: String.Encoding = .utf8) async throws -> String {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("sub.\(from)")
        try #require(text.data(using: encoding)).write(to: input)
        let target = try #require(converter.targets(for: input).first { $0.fileExtension == to })
        let out = dir.appendingPathComponent("out.\(to)")
        try await converter.convert(ConverterFixtures.request([input], target, output: out), progress: { _ in })
        return try String(contentsOf: out, encoding: .utf8)
    }

    @Test func targetsExcludeInputFormat() {
        let exts = converter.targets(for: URL(fileURLWithPath: "/tmp/a.srt")).map(\.fileExtension)
        #expect(exts == ["vtt", "ass"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.txt")).isEmpty)
    }

    @Test func srtToVTT() async throws {
        let vtt = try await convert(srt, from: "srt", to: "vtt")
        #expect(vtt.hasPrefix("WEBVTT\n\n00:00:01.500 --> 00:00:03.000\nXin chào\nthế giới"))
        #expect(vtt.contains("00:01:00.000 --> 00:01:02.250"))
    }

    @Test func roundTripThroughASSKeepsTextAndTimes() async throws {
        let ass = try await convert(srt, from: "srt", to: "ass")
        #expect(ass.contains("Dialogue: 0,0:00:01.50,0:00:03.00,Default,,0,0,0,,Xin chào\\Nthế giới"))
        let back = try await convert(ass, from: "ass", to: "srt")
        #expect(back.contains("1\n00:00:01,500 --> 00:00:03,000\nXin chào\nthế giới"))
        #expect(back.contains("2\n00:01:00,000 --> 00:01:02,250\nTạm biệt"))
    }

    @Test func vttWithoutHoursAndSettingsParses() {
        let cues = SubtitleFormats.parse("WEBVTT\n\nNOTE x\n\n01:02.500 --> 01:04.000 align:start\nHi\n", format: "vtt")
        #expect(cues == [SubtitleCue(start: 62.5, end: 64, text: "Hi")])
    }

    @Test func assStripsOverrideTags() {
        let cues = SubtitleFormats.parse("[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\i1}Hello, world{\\i0}\n", format: "ass")
        #expect(cues.first?.text == "Hello, world")
    }

    @Test func decodesUTF16AndLegacyEncodings() async throws {
        let utf16 = try await convert(srt, from: "srt", to: "vtt", encoding: .utf16)
        #expect(utf16.contains("Xin chào"))
        let legacy = Data("1\n00:00:01,000 --> 00:00:02,000\nCafé\n".utf8.map { $0 })
        var bytes = Array("1\n00:00:01,000 --> 00:00:02,000\nCaf".utf8)
        bytes.append(0xE9)
        #expect(SubtitleConverter.decode(Data(bytes)) == "1\n00:00:01,000 --> 00:00:02,000\nCafé")
        #expect(SubtitleConverter.decode(Data([0xEF, 0xBB, 0xBF]) + legacy)?.hasSuffix("Café\n") == true)
    }

    @Test func garbageInputFailsWithoutOutput() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("sub.srt")
        try Data("just some text".utf8).write(to: input)
        let target = try #require(converter.targets(for: input).first)
        let out = dir.appendingPathComponent("out.vtt")
        await #expect(throws: ConversionError.self) {
            try await converter.convert(ConverterFixtures.request([input], target, output: out), progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}
