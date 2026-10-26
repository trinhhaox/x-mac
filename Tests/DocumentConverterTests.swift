import Testing
import Foundation
@testable import Xmac

@Suite struct DocumentConverterTests {
    private let converter = DocumentConverter()

    @Test func offersAllFormatsExceptTheInputs() {
        let docx = converter.targets(for: URL(fileURLWithPath: "/x/a.DOCX")).map(\.fileExtension)
        #expect(docx == ["rtf", "odt", "html", "txt"])
        let htm = converter.targets(for: URL(fileURLWithPath: "/x/a.htm")).map(\.fileExtension)
        #expect(htm == ["docx", "rtf", "odt", "txt"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.pdf")).isEmpty)
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.rtf")).first?.id == "document.docx")
    }

    @Test func convertsRTFToTextAndDocx() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("note.rtf")
        try Data(#"{\rtf1\ansi Xin chao Xmac\par}"#.utf8).write(to: source)

        let txt = try ConverterToolTestSupport.request(converter, input: source, targetID: "document.txt", outputIn: dir)
        try await converter.convert(txt) { _ in }
        #expect(try String(contentsOf: txt.outputURL).contains("Xin chao Xmac"))

        let docx = try ConverterToolTestSupport.request(converter, input: source, targetID: "document.docx", outputIn: dir)
        try await converter.convert(docx) { _ in }
        let header = try Data(contentsOf: docx.outputURL).prefix(2)
        #expect(Array(header) == [0x50, 0x4B])
    }

    @Test func convertsHTMLToRTF() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("page.html")
        try Data("<html><body><h1>Tieu de</h1></body></html>".utf8).write(to: source)
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "document.rtf", outputIn: dir)
        try await converter.convert(request) { _ in }
        #expect(try String(contentsOf: request.outputURL).hasPrefix("{\\rtf"))
    }

    @Test func missingInputThrowsAndLeavesNoOutput() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("missing.docx")
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "document.rtf", outputIn: dir)
        await #expect(throws: ConversionError.self) { try await converter.convert(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: request.outputURL.path))
    }
}
