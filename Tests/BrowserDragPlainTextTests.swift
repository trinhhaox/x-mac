import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Xmac

@Suite struct BrowserDragPlainTextTests {
    private func provider(_ text: String, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(Data(text.utf8), nil)
            return nil
        }
        return provider
    }

    @Test(arguments: [UTType.plainText, UTType.utf8PlainText])
    func singleHttpsLinkBecomesRemotePayload(type: UTType) async throws {
        let payload = await BrowserDragProviderReader.payload(from: provider("https://example.com/a/report.pdf\n", type: type))
        guard case .remote(let url, _)? = payload else { Issue.record("expected remote, got \(String(describing: payload))"); return }
        #expect(url.absoluteString == "https://example.com/a/report.pdf")
    }

    @Test(arguments: ["just some words", "https://a.com/x https://b.com/y", "javascript:alert(1)", "file:///etc/passwd", ""])
    func nonLinkTextIsRejected(text: String) async {
        #expect(await BrowserDragProviderReader.payload(from: provider(text, type: .plainText)) == nil)
    }
}
