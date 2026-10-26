import Foundation
import Testing
@testable import Xmac

@Suite struct BrowserDragNamingTests {
    @Test func contentDispositionForms() {
        #expect(BrowserDragNaming.contentDispositionFileName("attachment; filename=\"a b.pdf\"") == "a b.pdf")
        #expect(BrowserDragNaming.contentDispositionFileName("attachment; filename=plain.zip") == "plain.zip")
        let both = "attachment; filename=\"x.txt\"; filename*=UTF-8''caf%C3%A9%20menu.txt"
        #expect(BrowserDragNaming.contentDispositionFileName(both) == "café menu.txt")
        #expect(BrowserDragNaming.contentDispositionFileName("inline") == nil)
        #expect(BrowserDragNaming.contentDispositionFileName(nil) == nil)
    }

    @Test func nameFallbackChainAndMimeExtension() {
        let url = URL(string: "https://example.com/files/photo")!
        let root = URL(string: "https://example.com/")!
        func name(_ disposition: String?, _ suggested: String?, _ at: URL, _ mime: String?) -> String {
            BrowserDragNaming.finalName(contentDisposition: disposition, suggested: suggested, url: at, mime: mime)
        }
        #expect(name("attachment; filename=cd.png", "s.jpg", url, "image/png") == "cd.png")
        #expect(name(nil, "s.jpg", url, nil) == "s.jpg")
        #expect(name(nil, nil, url, "image/png") == "photo.png")
        #expect(name(nil, nil, root, "application/pdf") == "download.pdf")
        #expect(name(nil, "Tên trang v1.2", url, "image/jpeg") == "Tên trang v1.2.jpeg")
        #expect(name(nil, nil, url, "application/octet-stream") == "photo")
    }

    @Test func namesAreSanitizedAndBounded() {
        let url = URL(string: "https://example.com/x")!
        let evil = BrowserDragNaming.finalName(contentDisposition: "attachment; filename=\"../../evil.sh\"", suggested: nil, url: url, mime: nil)
        #expect(evil == "evil.sh")
        let long = String(repeating: "a", count: 400) + ".png"
        let bounded = BrowserDragNaming.finalName(contentDisposition: nil, suggested: long, url: url, mime: nil)
        #expect(bounded.utf8.count == BrowserDragNaming.maxStemBytes + 4)
    }

    @Test func quotedSemicolonStaysInsideTheFileName() {
        #expect(BrowserDragNaming.contentDispositionFileName("attachment; filename=\"a;b.pdf\"; size=3") == "a;b.pdf")
    }

    @Test func bidiAndControlCharactersAreStripped() {
        let url = URL(string: "https://example.com/x")!
        let name = BrowserDragNaming.finalName(contentDisposition: nil, suggested: "photo\u{202E}gnp.command\u{7}\u{200F}", url: url, mime: nil)
        #expect(name == "photognp.command")
        #expect(BrowserDragNaming.safeName("a\u{2066}b\u{2069}\u{0}c.txt") == "abc.txt")
        #expect(BrowserDragNaming.safeName("e\u{200D}f.txt") == "e\u{200D}f.txt")
    }

    @Test func longNamesAreCutByBytesOnACharacterBoundary() {
        for unit in ["ệ", "漢", "👨‍👩‍👧"] {
            let name = String(repeating: unit, count: 300) + ".pdf"
            let result = BrowserDragNaming.withExtension(name, mime: nil)
            let stem = (result as NSString).deletingPathExtension
            #expect(stem.utf8.count <= BrowserDragNaming.maxStemBytes)
            #expect(stem.allSatisfy { String($0) == unit })
            #expect(result.hasSuffix(".pdf"))
        }
    }

    @Test func overLongExtensionIsDropped() {
        let name = "report." + String(repeating: "x", count: 20)
        #expect(BrowserDragNaming.withExtension(name, mime: nil) == "report")
    }
}
