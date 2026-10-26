import Foundation
import Testing
@testable import Xmac

/// fontTable / numbering / extra parts / Strict OOXML coverage for the legacy-font DOCX converter.
@Suite struct DocxLegacyFontPartsTests {
    private let converter = DocxLegacyFontConverter()
    private let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    private let transitional = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private let strict = "http://purl.oclc.org/ooxml/wordprocessingml/main"

    private func part(_ root: String, _ namespace: String, _ inner: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:\(root) xmlns:w=\"\(namespace)\">\(inner)</w:\(root)>"
    }

    private func run(_ font: String, _ text: String) -> String {
        "<w:r><w:rPr><w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\"/></w:rPr><w:t>\(text)</w:t></w:r>"
    }

    /// Builds a DOCX whose `word/document.xml` is `document` plus any extra parts keyed by path under the package root.
    private func convert(document: String, extra: [String: String], in dir: URL) async throws -> URL {
        let package = dir.appendingPathComponent("pkg", isDirectory: true)
        var parts = extra
        parts["word/document.xml"] = document
        parts["_rels/.rels"] = """
            <?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
            Target="word/document.xml"/></Relationships>
            """
        parts["[Content_Types].xml"] = """
            <?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/></Types>
            """
        for (path, content) in parts {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        let docx = dir.appendingPathComponent("in.docx")
        try await ConverterWorkspace.run(ditto, ["-c", "-k", package.path, docx.path])
        let output = dir.appendingPathComponent("out.docx")
        let offered = try #require(converter.targets(for: docx).first)
        try await converter.convert(ConverterFixtures.request([docx], offered, output: output), progress: { _ in })
        return output
    }

    private func read(_ name: String, of docx: URL, in dir: URL) async throws -> String {
        let folder = dir.appendingPathComponent("unzipped")
        if !FileManager.default.fileExists(atPath: folder.path) {
            try await ConverterWorkspace.run(ditto, ["-x", "-k", docx.path, folder.path])
        }
        return try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    private func occurrences(of needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    private func legacyBody(_ ns: String) -> String {
        part("document", ns, "<w:body><w:p>" + run(".VnTime", "ViÖt") + "</w:p></w:body>")
    }

    @Test func fontTableRenamesLegacyEntriesAndDropsDuplicates() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let table = part("fonts", transitional, """
            <w:font w:name=".VnTime"><w:charset w:val="00"/></w:font>\
            <w:font w:name=".VnArial"><w:charset w:val="00"/></w:font>\
            <w:font w:name="VNI-Helve"><w:charset w:val="00"/></w:font>\
            <w:font w:name="Arial"><w:charset w:val="00"/></w:font>\
            <w:font w:name="Calibri"/>
            """)
        let output = try await convert(document: legacyBody(transitional), extra: ["word/fontTable.xml": table], in: dir)
        let xml = try await read("word/fontTable.xml", of: output, in: dir)
        #expect(!xml.contains(".Vn") && !xml.contains("VNI-"))
        #expect(occurrences(of: "w:name=\"Times New Roman\"", in: xml) == 1)
        #expect(occurrences(of: "w:name=\"Arial\"", in: xml) == 1)
        #expect(xml.contains("w:name=\"Calibri\""))
    }

    @Test func renamedFontEntryLosesItsEmbeddedLegacyFontFiles() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let table = part("fonts", transitional, """
            <w:font w:name=".VnTime"><w:charset w:val="00"/>\
            <w:embedRegular r:id="rId1" w:fontKey="{A}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>\
            <w:embedBold w:fontKey="{B}"/><w:embedItalic w:fontKey="{C}"/><w:embedBoldItalic w:fontKey="{D}"/></w:font>\
            <w:font w:name="Calibri"><w:embedRegular w:fontKey="{E}"/></w:font>
            """)
        let output = try await convert(document: legacyBody(transitional), extra: ["word/fontTable.xml": table], in: dir)
        let xml = try await read("word/fontTable.xml", of: output, in: dir)
        #expect(xml.contains("w:name=\"Times New Roman\""))
        #expect(occurrences(of: "embed", in: xml) == 1)
        #expect(xml.contains("{E}") && !xml.contains("{A}") && !xml.contains("{D}"))
    }

    @Test func fontTableAloneDoesNotCountAsFoundLegacyFont() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let table = part("fonts", transitional, "<w:font w:name=\".VnTime\"/>")
        let plain = part("document", transitional, "<w:body><w:p>" + run("Calibri", "Hi") + "</w:p></w:body>")
        await #expect(throws: ConversionError.self) {
            _ = try await convert(document: plain, extra: ["word/fontTable.xml": table], in: dir)
        }
    }

    @Test func numberingLevelWithoutFontInheritsFromItsStyleThenDefaults() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let styles = part("styles", transitional, """
            <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=".VnTime"/></w:rPr></w:rPrDefault></w:docDefaults>\
            <w:style w:type="paragraph" w:styleId="ListA"><w:rPr><w:rFonts w:ascii=".VnTime"/></w:rPr></w:style>\
            <w:style w:type="paragraph" w:styleId="ListB"><w:rPr><w:rFonts w:ascii="Calibri"/></w:rPr></w:style>
            """)
        let numbering = part("numbering", transitional, """
            <w:abstractNum w:abstractNumId="0">\
            <w:lvl w:ilvl="0"><w:pStyle w:val="ListA"/><w:lvlText w:val="Môc %1"/></w:lvl>\
            <w:lvl w:ilvl="1"><w:pStyle w:val="ListB"/><w:lvlText w:val="Môc %1"/></w:lvl>\
            <w:lvl w:ilvl="2"><w:lvlText w:val="Môc %1"/></w:lvl>\
            </w:abstractNum>
            """)
        let plain = part("document", transitional, "<w:body><w:p>" + run("Calibri", "Hi") + "</w:p></w:body>")
        let output = try await convert(
            document: plain, extra: ["word/styles.xml": styles, "word/numbering.xml": numbering], in: dir)
        let xml = try await read("word/numbering.xml", of: output, in: dir)
        // ListA is TCVN3 and the style-less level falls to the TCVN3 default (both converted); ListB is Calibri (kept).
        #expect(occurrences(of: "w:val=\"Mục %1\"", in: xml) == 2)
        #expect(occurrences(of: "w:val=\"Môc %1\"", in: xml) == 1)
        #expect(xml.contains("w:val=\"ListB\""))
    }

    @Test func numberingConvertsLevelTextAndFontKeepingPlaceholders() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let numbering = part("numbering", transitional, """
            <w:abstractNum w:abstractNumId="0">\
            <w:lvl w:ilvl="0"><w:lvlText w:val="Môc %1."/><w:rPr><w:rFonts w:ascii=".VnTime" w:hAnsi=".VnTime"/></w:rPr></w:lvl>\
            <w:lvl w:ilvl="1"><w:lvlText w:val="Môc %1"/><w:rPr><w:rFonts w:ascii="Calibri"/></w:rPr></w:lvl>\
            </w:abstractNum>
            """)
        let output = try await convert(document: legacyBody(transitional), extra: ["word/numbering.xml": numbering], in: dir)
        let xml = try await read("word/numbering.xml", of: output, in: dir)
        #expect(xml.contains("w:val=\"Mục %1.\""))
        #expect(xml.contains("w:val=\"Môc %1\""))
        #expect(xml.contains("w:ascii=\"Times New Roman\"") && !xml.contains(".VnTime"))
    }

    @Test func numberingOnlyDocumentCountsAsConverted() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let numbering = part("numbering", transitional, """
            <w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:lvlText w:val="%1"/>\
            <w:rPr><w:rFonts w:ascii="VNI-Times"/></w:rPr></w:lvl></w:abstractNum>
            """)
        let plain = part("document", transitional, "<w:body><w:p>" + run("Calibri", "Hi") + "</w:p></w:body>")
        let output = try await convert(document: plain, extra: ["word/numbering.xml": numbering], in: dir)
        #expect(try await read("word/numbering.xml", of: output, in: dir).contains("Times New Roman"))
    }

    @Test func commentsAndGlossaryPartsAreConverted() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let comments = part("comments", transitional, "<w:comment w:id=\"0\"><w:p>" + run(".VnTime", "ViÖt") + "</w:p></w:comment>")
        let glossary = part("glossaryDocument", transitional, "<w:docParts><w:docPart><w:docPartBody><w:p>"
            + run("VNI-Times", "Vieät") + "</w:p></w:docPartBody></w:docPart></w:docParts>")
        let output = try await convert(
            document: legacyBody(transitional),
            extra: ["word/comments.xml": comments, "word/glossary/document.xml": glossary], in: dir)
        #expect(try await read("word/comments.xml", of: output, in: dir).contains("<w:t>Việt</w:t>"))
        #expect(try await read("word/glossary/document.xml", of: output, in: dir).contains("<w:t>Việt</w:t>"))
    }

    @Test func strictNamespaceIsConvertedWithStylesAndSoftHyphen() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let styles = part("styles", strict, """
            <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=".VnTime" w:hAnsi=".VnTime"/></w:rPr></w:rPrDefault></w:docDefaults>
            """)
        let hyphen = "<w:r><w:rPr><w:rFonts w:ascii=\".VnTime\"/></w:rPr><w:t>Tr</w:t><w:softHyphen/><w:t>ng</w:t></w:r>"
        let body = part("document", strict, "<w:body><w:p>" + run(".VnTime", "ViÖt") + "</w:p><w:p><w:r><w:t>Hµ Néi</w:t></w:r></w:p>"
            + "<w:p>" + hyphen + "</w:p></w:body>")
        let numbering = part("numbering", strict, """
            <w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:lvlText w:val="Môc %1"/>\
            <w:rPr><w:rFonts w:ascii=".VnTime"/></w:rPr></w:lvl></w:abstractNum>
            """)
        let table = part("fonts", strict, "<w:font w:name=\".VnTime\"/>")
        let output = try await convert(
            document: body, extra: ["word/styles.xml": styles, "word/numbering.xml": numbering, "word/fontTable.xml": table], in: dir)
        let xml = try await read("word/document.xml", of: output, in: dir)
        #expect(xml.contains("<w:t>Việt</w:t>") && xml.contains("<w:t>Hà Nội</w:t>"))
        #expect(xml.contains("<w:t>ư</w:t>") && !xml.contains("softHyphen"))
        #expect(xml.contains(strict) && !xml.contains(".VnTime"))
        #expect(try await read("word/numbering.xml", of: output, in: dir).contains("w:val=\"Mục %1\""))
        #expect(try await read("word/fontTable.xml", of: output, in: dir).contains("w:name=\"Times New Roman\""))
        #expect(!(try await read("word/styles.xml", of: output, in: dir)).contains(".VnTime"))
    }
}
