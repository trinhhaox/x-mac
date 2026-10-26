import Foundation
import Testing
@testable import Xmac

@Suite struct EPUBHTMLSanitizerTests {
    private let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("san-\(UUID().uuidString)", isDirectory: true)

    private func clean(_ html: String) -> String {
        EPUBHTMLSanitizer(root: root).sanitize(html, chapterFile: root.appendingPathComponent("ch.xhtml"))
    }

    @Test func dropsMultiLineAndSelfClosingScripts() {
        let out = clean("<html><body><p>keep</p><script>\nalert(1)\n</script><script src=\"x.js\"/><p>after</p></body></html>")
        #expect(out.contains("keep") && out.contains("after"))
        #expect(!out.contains("script") && !out.contains("alert") && !out.contains("x.js"))
    }

    @Test func dropsEventHandlersAndStyles() {
        let out = clean("<body><p onclick=\"evil()\" style=\"background:url(http://x/y)\">hi</p><style>p{background:url(http://x)}</style></body>")
        #expect(out.contains("hi") && !out.contains("onclick") && !out.contains("url(") && !out.contains("style"))
    }

    @Test func dropsActiveElements() {
        let out = clean("<body><iframe src=\"http://x\"></iframe><object data=\"a\"></object><embed src=\"a\"><form action=\"/\"><input name=\"q\"></form><svg><circle/></svg><video src=\"v\"></video><p>ok</p></body>")
        #expect(out.contains("ok"))
        for word in ["iframe", "object", "embed", "form", "input", "svg", "video", "http://x"] { #expect(!out.contains(word)) }
    }

    @Test func linksKeepOnlySafeSchemes() {
        let out = clean("<body><a href=\"javascript:alert(1)\">bad</a><a href=\" JaVa\nscript:x\">bad2</a><a href=\"https://example.com/a\">good</a><a href=\"mailto:a@b.c\">mail</a></body>")
        #expect(!out.lowercased().contains("javascript") && !out.contains("script:"))
        #expect(out.contains("href=\"https://example.com/a\"") && out.contains("href=\"mailto:a@b.c\""))
        #expect(out.contains("bad") && out.contains("bad2"))
    }

    @Test func remoteImageBecomesAltText() {
        let out = clean("<body><img src=\"http://evil/x.png\" alt=\"remote pic\" onerror=\"x()\"/><img src=\"//evil/y.png\" alt=\"proto\"></body>")
        #expect(out.contains("remote pic") && out.contains("proto"))
        #expect(!out.contains("<img") && !out.contains("evil") && !out.contains("onerror"))
    }

    @Test func dataImageKeptAndMalformedDataDropped() {
        let png = "data:image/png;base64,iVBORw0KGgo="
        let out = clean("<body><img src=\"\(png)\" alt=\"ok\" width=\"10\" height=\"5x\"><img src=\"data:text/html;base64,PHNjcmlwdD4=\" alt=\"html\"><img src=\"data:image/png;base64,AA\" onload=\"x\" alt=\"q\\\"\"></body>")
        #expect(out.contains("src=\"\(png)\"") && out.contains("width=\"10\"") && !out.contains("height"))
        #expect(!out.contains("text/html"))
    }

    @Test func oversizedDataImageIsDropped() {
        let big = "data:image/png;base64," + String(repeating: "A", count: EPUBHTMLSanitizer.maxInlineImageBytes * 2)
        let out = clean("<body><img src=\"\(big)\" alt=\"huge\"></body>")
        #expect(out == "huge")
    }

    @Test func keepsTextInOrderWithStructure() {
        let out = clean("<body><h1>One</h1><p>two <em>three</em></p><table><tr><td colspan=\"2\">four</td></tr></table><ul><li>five</li></ul></body>")
        let positions = ["One", "two", "three", "four", "five"].compactMap { out.range(of: $0)?.lowerBound }
        #expect(positions.count == 5 && positions == positions.sorted())
        #expect(out.contains("<h1>") && out.contains("<em>") && out.contains("colspan=\"2\"") && out.contains("<li>"))
    }

    @Test func builderAddsCSPAndCharset() throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let chapter = dir.appendingPathComponent("c.xhtml")
        try Data("<html><body><p>text</p></body></html>".utf8).write(to: chapter)
        let html = try EPUBHTMLBuilder.html(for: EPUBPackage(title: "T", chapterFiles: [chapter], root: dir))
        #expect(html.contains("Content-Security-Policy") && html.contains("img-src data:") && html.contains("charset=\"utf-8\""))
    }
}

@Suite struct ZipArchiveGuardTests {
    private let summary = "3 files, 1234 bytes uncompressed, 500 bytes compressed:  59.5%"

    @Test func parsesUncompressedTotal() {
        #expect(ZipArchiveGuard.uncompressedBytes(in: summary) == 1234)
        #expect(ZipArchiveGuard.uncompressedBytes(in: "garbage") == nil)
    }

    @Test func acceptsSmallArchive() throws {
        try ZipArchiveGuard.check(listing: "a.txt\nb/c.txt\n", summary: summary)
    }

    @Test func rejectsOversizeEntryCountAndMissingSummary() {
        let big = "2 files, \(ZipArchiveGuard.maxUncompressedBytes + 1) bytes uncompressed, 5 bytes compressed:  99%"
        #expect(throws: ConversionError.self) { try ZipArchiveGuard.check(listing: "a\nb\n", summary: big) }
        let many = (0...ZipArchiveGuard.maxEntries).map { "f\($0)" }.joined(separator: "\n")
        #expect(throws: ConversionError.self) { try ZipArchiveGuard.check(listing: many, summary: summary) }
        #expect(throws: ConversionError.self) { try ZipArchiveGuard.check(listing: "a\n", summary: "") }
    }

    @Test func rejectsTraversalEntries() {
        #expect(throws: ConversionError.self) { try ZipArchiveGuard.check(listing: "../evil\n", summary: summary) }
    }
}
