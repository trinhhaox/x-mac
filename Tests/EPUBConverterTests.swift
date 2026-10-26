import AppKit
import Testing
import Foundation
@testable import Xmac

@Suite struct EPUBConverterTests {
    private let converter = EPUBConverter()

    /// Builds a small EPUB: chapter 2 is listed first in the manifest but second in the spine.
    private func makeEPUB(in dir: URL, chapterHref: String = "ch2.xhtml") throws -> URL {
        let src = dir.appendingPathComponent("src", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: src.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: src.appendingPathComponent("OEBPS/images"), withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: src.appendingPathComponent("mimetype"))
        try Data("""
        <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """.utf8).write(to: src.appendingPathComponent("META-INF/container.xml"))
        try Data("""
        <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Truyen Thu</dc:title></metadata>
        <manifest>
        <item id="b" href="\(chapterHref)" media-type="application/xhtml+xml"/>
        <item id="a" href="ch%31.xhtml" media-type="application/xhtml+xml"/>
        </manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>
        """.utf8).write(to: src.appendingPathComponent("OEBPS/content.opf"))
        try Data("""
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title><style>p{}</style></head>
        <body><p>Alpha chapter</p><img src="images/pic.png" alt="a pic"/><img src="images/missing.png" alt="gone"/></body></html>
        """.utf8).write(to: src.appendingPathComponent("OEBPS/ch1.xhtml"))
        try Data("<html><body><p>Beta chapter</p></body></html>".utf8).write(to: src.appendingPathComponent("OEBPS/ch2.xhtml"))
        try ConverterFixtures.writeImage(to: src.appendingPathComponent("OEBPS/images/pic.png"))

        let epub = dir.appendingPathComponent("book.epub")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", src.path, epub.path]
        try ditto.run()
        ditto.waitUntilExit()
        try #require(ditto.terminationStatus == 0)
        return epub
    }

    private func convert(_ epub: URL, to targetID: String, in dir: URL) async throws -> ConversionRequest {
        let request = try ConverterToolTestSupport.request(converter, input: epub, targetID: targetID, outputIn: dir)
        try await converter.convert(request) { _ in }
        return request
    }

    @Test func offersFourTargetsForEPUBOnly() {
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.EPUB")).map(\.fileExtension) == ["txt", "html", "docx", "rtf"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/x/a.mobi")).isEmpty)
    }

    @Test func textKeepsSpineOrderAndTitle() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let request = try await convert(try makeEPUB(in: dir), to: "epub.txt", in: dir)
        let text = try String(contentsOf: request.outputURL, encoding: .utf8)
        let title = try #require(text.range(of: "Truyen Thu"))
        let alpha = try #require(text.range(of: "Alpha chapter"))
        let beta = try #require(text.range(of: "Beta chapter"))
        #expect(title.lowerBound < alpha.lowerBound && alpha.lowerBound < beta.lowerBound)
    }

    @Test func htmlEmbedsImageAndDropsMissingOne() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let request = try await convert(try makeEPUB(in: dir), to: "epub.html", in: dir)
        let html = try String(contentsOf: request.outputURL, encoding: .utf8)
        #expect(html.contains("Alpha chapter") && html.contains("Beta chapter"))
        #expect(html.contains("src=\"data:image/png;base64,"))
        #expect(html.contains("gone") && !html.contains("missing.png"))
        #expect(!html.contains("p{}"))
    }

    @Test func docxOpensAsAttributedString() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let request = try await convert(try makeEPUB(in: dir), to: "epub.docx", in: dir)
        let attributed = try NSAttributedString(
            data: Data(contentsOf: request.outputURL), options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil)
        #expect(attributed.string.contains("Alpha chapter") && attributed.string.contains("Beta chapter"))
    }

    @Test func rejectsSpineHrefEscapingTheArchive() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let epub = try makeEPUB(in: dir, chapterHref: "../../evil.xhtml")
        let request = try ConverterToolTestSupport.request(converter, input: epub, targetID: "epub.txt", outputIn: dir)
        await #expect(throws: ConversionError.self) { try await converter.convert(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: request.outputURL.path))
    }

    @Test func resolveRejectsAbsoluteAndTraversal() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("epub-root")
        let opf = root.appendingPathComponent("OEBPS/content.opf")
        #expect(EPUBPackage.resolve("../ch%31.xhtml", relativeTo: opf, root: root) != nil)
        #expect(EPUBPackage.resolve("../../evil", relativeTo: opf, root: root) == nil)
        #expect(EPUBPackage.resolve("/etc/passwd", relativeTo: opf, root: root) == nil)
        #expect(EPUBPackage.resolve("..%2F..%2Fevil", relativeTo: opf, root: root) == nil)
    }
}
