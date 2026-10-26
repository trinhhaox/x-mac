import Foundation
import Testing
@testable import Xmac

@Suite struct ConverterRegistryTests {
    private func locator(ffmpegAt path: String? = nil) -> BinaryLocator {
        let defaults = UserDefaults(suiteName: "registry-tests-\(UUID().uuidString)")!
        if let path { defaults.set(path, forKey: ExternalTool.ffmpeg.overrideDefaultsKey) }
        return BinaryLocator(defaults: defaults)
    }

    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    @Test func standardRegistryIntersectsTargetsAcrossInputs() {
        let registry = ConverterRegistry.standard(locator: locator())
        let single = registry.targets(for: [url("a.png")]).map(\.id)
        #expect(single.contains("image.jpg") && single.contains("images-pdf.pdf") && !single.contains("image.png"))
        let both = registry.targets(for: [url("a.png"), url("b.jpg")]).map(\.id)
        #expect(both.contains("image.heic") && both.contains("images-pdf.pdf"))
        #expect(!both.contains("image.png") && !both.contains("image.jpg"))
        // Unrelated types share only the format-agnostic ZIP target.
        #expect(registry.targets(for: [url("a.png"), url("b.srt")]).map(\.id) == ["archive.zip"])
        #expect(registry.targets(for: []).isEmpty)
    }

    @Test func mergeIsOfferedOnlyForTwoOrMorePDFs() {
        let registry = ConverterRegistry.standard(locator: locator())
        #expect(!registry.targets(for: [url("a.pdf")]).map(\.id).contains(PDFConverter.mergeTargetID))
        #expect(registry.targets(for: [url("a.pdf"), url("b.pdf")]).map(\.id).contains(PDFConverter.mergeTargetID))
    }

    @Test func converterLookupUsesTargetIDPrefix() throws {
        let registry = ConverterRegistry.standard(locator: locator())
        let png = try #require(registry.targets(for: [url("a.jpg")]).first { $0.id == "image.png" })
        #expect(registry.converter(for: png)?.id == "image")
        let pdf = try #require(registry.targets(for: [url("a.png")]).first { $0.id == "images-pdf.pdf" })
        #expect(registry.converter(for: pdf)?.id == "images-pdf")
        #expect(registry.converter(for: ConversionTarget(id: "nope.x", title: "", fileExtension: "x", group: .image)) == nil)
    }

    @Test func toolBackedTargetsAppearOnlyWhenToolIsInstalled() throws {
        let fake = FakeConverter(requiredTool: .ffmpeg)
        let missing = ConverterRegistry(converters: [fake], locator: locator(ffmpegAt: "/nonexistent/ffmpeg"))
        #expect(missing.targets(for: [url("a.txt")]).isEmpty)
        #expect(missing.missingTools(for: [url("a.txt")]) == [.ffmpeg])
        #expect(missing.missingTools(for: [url("a.png")]).isEmpty)

        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = dir.appendingPathComponent("ffmpeg")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let present = ConverterRegistry(converters: [fake], locator: locator(ffmpegAt: tool.path))
        #expect(present.targets(for: [url("a.txt")]).map(\.id) == ["fake.out"])
        #expect(present.missingTools(for: [url("a.txt")]).isEmpty)
    }
}

@Suite struct ConverterRegistryStandardTests {
    @Test func nativeTargetWinsOverExternalDuplicate() throws {
        let registry = ConverterRegistry.standard()
        let targets = registry.targets(for: [URL(fileURLWithPath: "/tmp/clip.mov")])
        let titles = targets.map(\.title)
        #expect(titles.count == Set(titles).count)
        if let m4a = targets.first(where: { $0.fileExtension == "m4a" }) {
            #expect(m4a.id.hasPrefix("media."))
        }
    }
}
