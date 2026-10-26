import AppKit
import Foundation
import ModelIO
import Testing
@testable import Xmac

@Suite struct Model3DConverterTests {
    private let converter = Model3DConverter()

    private func makeCube(in dir: URL, ext: String) throws -> URL {
        let mesh = MDLMesh(boxWithExtent: [1, 1, 1], segments: [1, 1, 1], inwardNormals: false,
                           geometryType: .triangles, allocator: nil)
        let asset = MDLAsset()
        asset.add(mesh)
        let url = dir.appendingPathComponent("cube.\(ext)")
        try asset.export(to: url)
        return url
    }

    private func vertexCount(_ url: URL) throws -> Int {
        let asset = MDLAsset(url: url)
        let meshes = asset.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
        return meshes.reduce(0) { $0 + $1.vertexCount }
    }

    private func convert(_ input: URL, to ext: String, in dir: URL) async throws -> URL {
        let target = try #require(converter.targets(for: input).first { $0.fileExtension == ext })
        let out = dir.appendingPathComponent("out.\(ext)")
        try await converter.convert(ConverterFixtures.request([input], target, output: out), progress: { _ in })
        return out
    }

    @Test func targetsExcludeInputAndAddPreview() {
        let ids = converter.targets(for: URL(fileURLWithPath: "/tmp/a.obj")).map(\.fileExtension)
        #expect(!ids.contains("obj"))
        #expect(ids.contains("stl") && ids.contains("png"))
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.txt")).isEmpty)
    }

    @Test func cubeSurvivesFormatConversion() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeCube(in: dir, ext: "obj")
        let expected = try vertexCount(source)
        #expect(expected >= 8)
        for ext in ["stl", "ply"] {
            let out = try await convert(source, to: ext, in: dir)
            #expect(try vertexCount(out) >= 8)
        }
        let obj = try String(contentsOf: source, encoding: .utf8)
        #expect(obj.contains("v "))
    }

    @Test func objOutputHasNoDanglingMaterialReference() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stl = try makeCube(in: dir, ext: "stl")
        let obj = try await convert(stl, to: "obj", in: dir)
        let text = try String(contentsOf: obj, encoding: .utf8)
        #expect(!text.contains("mtllib"))
    }

    @Test func previewIsNonUniformPNG() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try makeCube(in: dir, ext: "obj")
        let png = try await convert(source, to: "png", in: dir)
        let rep = try #require(NSBitmapImageRep(data: Data(contentsOf: png)))
        #expect(rep.pixelsWide == 1024 && rep.pixelsHigh == 1024)
        var colors = Set<UInt32>()
        for (x, y) in [(10, 10), (512, 512), (400, 600), (600, 400), (512, 300), (300, 512)] {
            let c = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            colors.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
        }
        #expect(colors.count > 1)
    }

    @Test func emptyOrGarbageInputFails() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad.obj")
        try Data("not a model".utf8).write(to: bad)
        await #expect(throws: ConversionError.self) { _ = try await convert(bad, to: "stl", in: dir) }
    }
}
