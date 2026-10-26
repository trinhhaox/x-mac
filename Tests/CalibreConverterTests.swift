import Testing
import Foundation
@testable import Xmac

@Suite struct CalibreConverterTests {
    private let converter = CalibreConverter()

    @Test func listsTargetsWithoutTheInputFormat() {
        let mobi = converter.targets(for: URL(fileURLWithPath: "/x/a.MOBI")).map(\.fileExtension)
        #expect(mobi == ["epub", "azw3", "pdf", "docx", "txt", "fb2"])
        let epub = converter.targets(for: URL(fileURLWithPath: "/x/a.epub")).map(\.id)
        #expect(epub.contains("calibre.mobi") && !epub.contains("calibre.epub"))
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.pdf")).isEmpty)
        #expect(converter.requiredTool == .ebookConvert)
    }

    @Test func buildsArgumentsAndParsesProgress() {
        let args = CalibreConverter.arguments(input: URL(fileURLWithPath: "/a/in.mobi"), output: URL(fileURLWithPath: "/t/output.epub"))
        #expect(args == ["/a/in.mobi", "/t/output.epub"])
        #expect(CalibreConverter.progressFraction(from: "34% Running transforms") == 0.34)
        #expect(CalibreConverter.progressFraction(from: "Output saved to x") == nil)
        #expect(CalibreConverter.progressFraction(from: "150% bogus") == nil)
    }

    @Test func missingToolIsReported() async throws {
        let defaults = try #require(UserDefaults(suiteName: "calibre-test-\(UUID().uuidString)"))
        defaults.set("/nonexistent/ebook-convert", forKey: ExternalTool.ebookConvert.overrideDefaultsKey)
        let converter = CalibreConverter(locator: BinaryLocator(defaults: defaults))
        let input = URL(fileURLWithPath: "/x/a.mobi")
        let request = ConversionRequest(
            inputs: [input], target: try #require(converter.targets(for: input).first),
            preset: ConversionPreset(), outputURL: URL(fileURLWithPath: "/x/out.epub"))
        await #expect(throws: ConversionError.toolMissing(.ebookConvert)) { try await converter.convert(request) { _ in } }
    }

    @Test(.enabled(if: BinaryLocator().locate(.ebookConvert) != nil))
    func convertsEPUBToMOBIWithCalibre() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("in.txtz")
        try Data("not a real txtz".utf8).write(to: source)
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "calibre.epub", outputIn: dir)
        await #expect(throws: ConversionError.self) { try await converter.convert(request) { _ in } }
    }
}
