import AppKit
import Foundation
import Testing
@testable import Xmac

@Suite struct DocxLegacyFontConverterTests {
    private let converter = DocxLegacyFontConverter()
    private let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    private let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""

    private func run(_ fonts: String, text: String) -> String {
        "<w:r><w:rPr>\(fonts)</w:rPr><w:t>\(text)</w:t></w:r>"
    }

    private func documentXML(body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document \(ns)><w:body>\(body)</w:body></w:document>"
    }

    private func stylesXML(defaultFont: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:styles \(ns)>"
            + "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"\(defaultFont)\" w:hAnsi=\"\(defaultFont)\"/></w:rPr></w:rPrDefault></w:docDefaults>"
            + "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>"
    }

    private func makeDocx(in dir: URL, document: String, styles: String? = nil) async throws -> URL {
        let package = dir.appendingPathComponent("pkg", isDirectory: true)
        let word = package.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: word, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        let relationship = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        </Types>
        """.utf8).write(to: package.appendingPathComponent("[Content_Types].xml"))
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="\(relationship)" Target="word/document.xml"/></Relationships>
        """.utf8).write(to: package.appendingPathComponent("_rels/.rels"))
        try Data(document.utf8).write(to: word.appendingPathComponent("document.xml"))
        if let styles { try Data(styles.utf8).write(to: word.appendingPathComponent("styles.xml")) }
        let docx = dir.appendingPathComponent("in.docx")
        try await ConverterWorkspace.run(ditto, ["-c", "-k", package.path, docx.path])
        return docx
    }

    private func convert(_ docx: URL, in dir: URL) async throws -> URL {
        let output = dir.appendingPathComponent("out.docx")
        let offered = try #require(converter.targets(for: docx).first)
        try await converter.convert(ConverterFixtures.request([docx], offered, output: output), progress: { _ in })
        return output
    }

    private func part(_ name: String, of docx: URL, in dir: URL) async throws -> String {
        let folder = dir.appendingPathComponent("unzipped-\(UUID().uuidString)")
        try await ConverterWorkspace.run(ditto, ["-x", "-k", docx.path, folder.path])
        return try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    @Test func offersOneTargetForDocxOnly() {
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.DOCX")).map(\.id) == ["vn-legacy-docx.docx"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.doc")).isEmpty)
    }

    @Test func convertsTCVN3AndVNIRunsAndReplacesFonts() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = "<w:p>"
            + run("<w:rFonts w:ascii=\".VnTime\" w:hAnsi=\".VnTime\"/>", text: "ViÖt Nam")
            + run("<w:rFonts w:ascii=\"VNI-Times\" w:hAnsi=\"VNI-Times\"/>", text: "Vieät Nam &amp; Ñaø Naüng")
            + run("<w:rFonts w:ascii=\".VnArial\" w:hAnsi=\".VnArial\"/>", text: "Hµ Néi")
            + run("<w:rFonts w:ascii=\"Calibri\" w:hAnsi=\"Calibri\"/>", text: "Vieät giữ nguyên")
            + "</w:p>"
        let docx = try await makeDocx(in: dir, document: documentXML(body: body))
        let output = try await convert(docx, in: dir)

        let xml = try await part("word/document.xml", of: output, in: dir)
        #expect(xml.components(separatedBy: "Việt Nam").count == 3)
        #expect(xml.contains("Việt Nam &amp; Đà Nẵng"))
        #expect(xml.contains("Hà Nội"))
        #expect(xml.contains("Vieät giữ nguyên"))
        #expect(!xml.contains(".VnTime") && !xml.contains("VNI-Times") && !xml.contains(".VnArial"))
        #expect(xml.contains("w:ascii=\"Times New Roman\"") && xml.contains("w:ascii=\"Arial\""))

        let attributed = try NSAttributedString(
            url: output, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        #expect(attributed.string.components(separatedBy: "Việt Nam").count == 3)
    }

    @Test func runsWithoutFontsInheritLegacyDocumentDefault() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = "<w:p><w:r><w:t>ViÖt Nam</w:t></w:r></w:p>"
            + "<w:p>" + run("<w:rFonts w:ascii=\"Calibri\"/>", text: "ViÖt") + "</w:p>"
        let docx = try await makeDocx(in: dir, document: documentXML(body: body), styles: stylesXML(defaultFont: ".VnTime"))
        let output = try await convert(docx, in: dir)

        let xml = try await part("word/document.xml", of: output, in: dir)
        #expect(xml.contains("<w:t>Việt Nam</w:t>"))
        #expect(xml.contains("ViÖt"))
        let styles = try await part("word/styles.xml", of: output, in: dir)
        #expect(styles.contains("Times New Roman") && !styles.contains(".VnTime"))
    }

    @Test func allCapsFontUppercasesDecodedText() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = "<w:p>" + run("<w:rFonts w:ascii=\".VnTimeH\"/>", text: "ViÖt Nam") + "</w:p>"
        let docx = try await makeDocx(in: dir, document: documentXML(body: body))
        let output = try await convert(docx, in: dir)
        #expect(try await part("word/document.xml", of: output, in: dir).contains("VIỆT NAM"))
    }

    @Test func documentWithoutLegacyFontsFailsAndLeavesNoOutput() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = "<w:p>" + run("<w:rFonts w:ascii=\"Calibri\"/>", text: "Hello") + "</w:p>"
        let docx = try await makeDocx(in: dir, document: documentXML(body: body))
        let offered = try #require(converter.targets(for: docx).first)
        let output = dir.appendingPathComponent("out.docx")
        await #expect(throws: ConversionError.self) {
            try await converter.convert(ConverterFixtures.request([docx], offered, output: output), progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    private func convertedDocument(_ body: String, styles: String? = nil) async throws -> String {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let docx = try await makeDocx(in: dir, document: documentXML(body: body), styles: styles)
        return try await part("word/document.xml", of: convert(docx, in: dir), in: dir)
    }

    @Test func letterSplitAcrossRunsIsRejoined() async throws {
        let vni = "<w:rFonts w:ascii=\"VNI-Times\"/>"
        let xml = try await convertedDocument("<w:p>" + run(vni, text: "Vie") + run(vni, text: "ät a") + run(vni, text: "ù") + "</w:p>")
        #expect(xml.contains("<w:t>Việ</w:t>") && xml.contains("<w:t>t á</w:t>"))
        let tcvn = "<w:rFonts w:ascii=\".VnTime\"/>"
        let capital = try await convertedDocument("<w:p>" + run(tcvn, text: "A") + run(tcvn, text: "¹") + "</w:p>")
        #expect(capital.contains("<w:t>Ạ</w:t>"))
    }

    @Test func fontIsResolvedFromAsciiSlotOnly() async throws {
        let styles = "<?xml version=\"1.0\"?><w:styles \(ns)><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\">"
            + "<w:rPr><w:rFonts w:ascii=\".VnTime\" w:hAnsi=\".VnTime\"/></w:rPr></w:style></w:styles>"
        let xml = try await convertedDocument(
            "<w:p>" + run("<w:rFonts w:eastAsia=\"SimSun\"/>", text: "ViÖt")
                + run("<w:rFonts w:asciiTheme=\"minorHAnsi\"/>", text: "ViÖt") + "</w:p>", styles: styles)
        #expect(xml.contains("<w:t>Việt</w:t>") && xml.contains("<w:t>ViÖt</w:t>"))
    }

    @Test func trackedDeletionsAreConverted() async throws {
        let fonts = "<w:rFonts w:ascii=\".VnTime\"/>"
        let xml = try await convertedDocument("<w:p><w:del><w:r><w:rPr>\(fonts)</w:rPr><w:delText>ViÖt</w:delText></w:r></w:del></w:p>")
        #expect(xml.contains("<w:delText>Việt</w:delText>"))
    }

    @Test func tcvn3SoftHyphenIsLetterU() async throws {
        let fonts = "<w:rFonts w:ascii=\".VnTime\"/>"
        let xml = try await convertedDocument(
            "<w:p>" + run(fonts, text: "Tr\u{AD}ng")
                + "<w:r><w:rPr>\(fonts)</w:rPr><w:t>Tr</w:t><w:softHyphen/><w:t>ng</w:t></w:r></w:p>")
        #expect(xml.contains("<w:t>Trưng</w:t>"))
        #expect(xml.contains("<w:t>ư</w:t>") && !xml.contains("softHyphen"))
    }
}
