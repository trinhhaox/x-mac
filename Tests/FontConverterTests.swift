import CoreGraphics
import Foundation
import Testing
@testable import Xmac

@Suite struct FontConverterTests {
    private let converter = FontConverter()
    private static let ttf = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")
    private static let otf = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/NotoSansJavanese-Regular.otf")

    /// tag → table bytes, ignoring offsets and padding.
    private func tables(_ sfnt: Data) -> [String: Data] {
        let b = [UInt8](sfnt)
        let count = Int(b[4]) << 8 | Int(b[5])
        var result: [String: Data] = [:]
        for i in 0..<count {
            let e = 12 + i * 16
            let tag = String(decoding: b[e..<e + 4], as: UTF8.self)
            let offset = b[(e + 8)..<(e + 12)].reduce(0) { $0 << 8 | Int($1) }
            let length = b[(e + 12)..<(e + 16)].reduce(0) { $0 << 8 | Int($1) }
            result[tag] = Data(b[offset..<offset + length])
        }
        return result
    }

    private func run(_ input: URL, to ext: String, in dir: URL) async throws -> URL {
        let target = try #require(converter.targets(for: input).first { $0.fileExtension == ext })
        let out = dir.appendingPathComponent("out-\(UUID().uuidString).\(ext)")
        try await converter.convert(ConverterFixtures.request([input], target, output: out), progress: { _ in })
        return out
    }

    private func roundTrip(_ source: URL, ext: String) async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let woff = try await run(source, to: "woff", in: dir)
        let original = try Data(contentsOf: source)
        let packed = try Data(contentsOf: woff)
        #expect(packed.count < original.count)
        let restored = try await run(woff, to: ext, in: dir)
        let data = try Data(contentsOf: restored)
        #expect(tables(data) == tables(original))
        let provider = try #require(CGDataProvider(data: data as CFData))
        #expect(CGFont(provider) != nil)
    }

    @Test func targetsFollowExtension() {
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.ttf")).map(\.fileExtension) == ["woff"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.OTF")).map(\.fileExtension) == ["woff"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.woff")).map(\.fileExtension) == ["ttf", "otf"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.woff2")).isEmpty)
    }

    @Test func ttfRoundTripsThroughWoff() async throws {
        try #require(FileManager.default.fileExists(atPath: Self.ttf.path))
        try await roundTrip(Self.ttf, ext: "ttf")
    }

    @Test func otfRoundTripsThroughWoff() async throws {
        try #require(FileManager.default.fileExists(atPath: Self.otf.path))
        try await roundTrip(Self.otf, ext: "otf")
    }

    @Test func wrongFlavorTargetIsRejected() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let woff = try await run(Self.ttf, to: "woff", in: dir)
        await #expect(throws: ConversionError.self) { _ = try await run(woff, to: "otf", in: dir) }
    }

    @Test func garbageIsRejected() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad.ttf")
        try Data(repeating: 7, count: 100).write(to: bad)
        await #expect(throws: ConversionError.self) { _ = try await run(bad, to: "woff", in: dir) }
        let badWoff = dir.appendingPathComponent("bad.woff")
        try Data("wOFF".utf8).write(to: badWoff)
        await #expect(throws: ConversionError.self) { _ = try await run(badWoff, to: "ttf", in: dir) }
    }
}
