import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Xmac

@Suite struct ImageConverterTests {
    private let converter = ImageConverter()

    private func target(_ id: String, for url: URL) throws -> ConversionTarget {
        try #require(converter.targets(for: url).first { $0.id == id })
    }

    @Test func offersFormatsExceptTheInputType() throws {
        let png = URL(fileURLWithPath: "/tmp/a.png")
        let ids = converter.targets(for: png).map(\.id)
        #expect(ids.contains("image.jpg") && ids.contains("image.heic"))
        #expect(!ids.contains("image.png"))
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.jpeg")).map(\.id).contains("image.jpg") == false)
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.pdf")).isEmpty)
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.unknownext")).isEmpty)
    }

    @Test func convertsPNGToJPGAndHEIC() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try ConverterFixtures.writeImage(to: dir.appendingPathComponent("a.png"))
        for key in ["jpg", "heic", "tiff", "bmp", "gif"] {
            let out = dir.appendingPathComponent("out.\(key)")
            try await converter.convert(
                ConverterFixtures.request([input], try target("image.\(key)", for: input), output: out), progress: { _ in }
            )
            let size = try #require(ConverterFixtures.imageSize(at: out), "\(key) unreadable")
            #expect(size.width == 40 && size.height == 20)
        }
    }

    @Test func honoursMaxDimension() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try ConverterFixtures.writeImage(to: dir.appendingPathComponent("a.png"))
        var preset = ConversionPreset()
        preset.maxImageDimension = 10
        let out = dir.appendingPathComponent("out.jpg")
        try await converter.convert(
            ConverterFixtures.request([input], try target("image.jpg", for: input), output: out, preset: preset), progress: { _ in }
        )
        let size = try #require(ConverterFixtures.imageSize(at: out))
        #expect(size.width == 10 && size.height == 5)
    }

    @Test func appliesExifOrientation() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try ConverterFixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), type: .jpeg, orientation: 6)
        let out = dir.appendingPathComponent("out.png")
        try await converter.convert(
            ConverterFixtures.request([input], try target("image.png", for: input), output: out), progress: { _ in }
        )
        let size = try #require(ConverterFixtures.imageSize(at: out))
        #expect(size.width == 20 && size.height == 40)
    }

    @Test func corruptInputThrowsAndLeavesNoOutput() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: input)
        let out = dir.appendingPathComponent("out.jpg")
        let jpg = ConversionTarget(id: "image.jpg", title: "JPG", fileExtension: "jpg", group: .image)
        await #expect(throws: ConversionError.self) {
            try await converter.convert(ConverterFixtures.request([input], jpg, output: out), progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}
