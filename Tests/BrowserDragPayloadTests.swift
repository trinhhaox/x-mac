import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Xmac

@Suite struct BrowserDragPayloadTests {
    private func values(_ pairs: [String: String]) -> [String: Data] { pairs.mapValues { Data($0.utf8) } }

    private func remote(_ payload: BrowserDragPayload?) -> (URL, String?)? {
        if case .remote(let url, let name)? = payload { return (url, name) }
        return nil
    }

    @Test func safariLinkBeatsItsDecodedTiff() {
        var board = values(["public.url": "https://example.com/cat.jpg", "public.url-name": "cat.jpg"])
        board["public.tiff"] = Data([1, 2, 3])
        let payload = BrowserDragPayload.parse(BrowserDragSnapshot(values: board))
        #expect(remote(payload)?.0.absoluteString == "https://example.com/cat.jpg")
        #expect(remote(payload)?.1 == "cat.jpg")
        #expect(payload?.expectedExtension == "jpg")
    }

    @Test func tiffAloneIsUsedAndRealImageBeatsLink() {
        let tiff = BrowserDragPayload.parse(BrowserDragSnapshot(values: ["public.tiff": Data([1])]))
        guard case .imageData(_, let type, _)? = tiff else { Issue.record("expected image data"); return }
        #expect(type == .tiff)
        let board: [String: Data] = ["public.png": Data([1]), "public.url": Data("https://example.com/a".utf8)]
        guard case .imageData(_, let png, _)? = BrowserDragPayload.parse(BrowserDragSnapshot(values: board)) else {
            Issue.record("expected image data"); return
        }
        #expect(png == .png)
    }

    @Test func fileBeatsPromiseBeatsEverythingElse() {
        let file = URL(fileURLWithPath: "/tmp/a.pdf")
        let board = values(["public.url": "https://example.com/b.png"])
        let withFile = BrowserDragSnapshot(fileURLs: [file], promiseReceivers: [NSFilePromiseReceiver()], values: board)
        guard case .files(let urls)? = BrowserDragPayload.parse(withFile) else { Issue.record("file should win"); return }
        #expect(urls == [file])
        let promise = BrowserDragPayload.parse(BrowserDragSnapshot(promiseReceivers: [NSFilePromiseReceiver()], values: board))
        guard case .promise? = promise else { Issue.record("promise should beat link"); return }
        #expect(promise?.expectedExtension == nil)
    }

    @Test func plainTextMustBeASingleHTTPURL() {
        let single = BrowserDragPayload.parse(BrowserDragSnapshot(values: values(["public.utf8-plain-text": " https://example.com/a.pdf\n"])))
        #expect(remote(single)?.0.pathExtension == "pdf")
        for text in ["see https://example.com/a.pdf", "hello", ""] {
            #expect(BrowserDragPayload.parse(BrowserDragSnapshot(values: values(["public.utf8-plain-text": text]))) == nil)
        }
    }

    @Test func unsafeSchemesAreRejected() {
        let links = ["javascript:alert(1)", "file:///etc/passwd", "ftp://example.com/a.zip", "data:text/html;base64,PGI+", "https:///nohost"]
        for link in links {
            #expect(BrowserDragPayload.parse(BrowserDragSnapshot(values: values(["public.url": link]))) == nil, "\(link)")
        }
    }

    @Test func dataURLImagesAreDecoded() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let board = values(["public.url": "data:image/png;base64,\(bytes.base64EncodedString())"])
        guard case .imageData(let data, let type, _)? = BrowserDragPayload.parse(BrowserDragSnapshot(values: board)) else {
            Issue.record("expected image data"); return
        }
        #expect(type == .png)
        #expect(data == bytes)
        #expect(BrowserDragPayload.parse(BrowserDragSnapshot(values: values(["public.url": "data:image/png;base64,!!"]))) == nil)
    }

    @Test func expectedExtensionAndPlaceholderInputs() {
        let named = BrowserDragPayload.remote(URL(string: "https://example.com/view?id=3")!, suggestedName: "Report.PDF")
        #expect(named.expectedExtension == "pdf")
        #expect(named.placeholderInputs?.first?.lastPathComponent == "Report.pdf")
        let page = BrowserDragPayload.remote(URL(string: "https://example.com/")!, suggestedName: "Example Domain")
        #expect(page.expectedExtension == nil)
        #expect(page.placeholderInputs == nil)
        let direct = BrowserDragPayload.remote(URL(string: "https://example.com/files/clip.mp4")!, suggestedName: nil)
        #expect(direct.placeholderInputs?.first?.lastPathComponent == "clip.mp4")
        let image = BrowserDragPayload.imageData(Data([1]), .jpeg, suggestedName: nil)
        #expect(image.placeholderInputs?.first?.pathExtension == "jpeg")
    }
}
