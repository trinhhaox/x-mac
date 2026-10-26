import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Xmac

/// Serves canned responses by URL so no test touches the network.
final class StubURLProtocol: URLProtocol {
    enum Route {
        case body(status: Int, headers: [String: String], chunks: [Data])
        case redirect(String)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: Route] = [:]

    static func register(_ route: Route) -> URL {
        let url = URL(string: "https://\(UUID().uuidString.lowercased()).test/file")!
        lock.lock(); routes[url.absoluteString] = route; lock.unlock()
        return url
    }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock(); let route = Self.routes[url.absoluteString]; Self.lock.unlock()
        switch route {
        case .redirect(let location)?:
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": location])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: location)!), redirectResponse: response)
        case .body(let status, let headers, let chunks)?:
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
            client?.urlProtocolDidFinishLoading(self)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }
}

@Suite struct BrowserDragFetcherTests {
    private func fetcher(maxBytes: Int64 = BrowserDragDownloader.defaultMaxBytes) -> BrowserDragFetcher {
        BrowserDragFetcher(configuration: StubURLProtocol.configuration, maxBytes: maxBytes)
    }

    private func fetch(
        _ url: URL, name: String? = nil, maxBytes: Int64 = BrowserDragDownloader.defaultMaxBytes, into dir: URL
    ) async throws -> URL {
        try await fetcher(maxBytes: maxBytes).fetch(.remote(url, suggestedName: name), into: dir)[0]
    }

    @Test func downloadsWithContentDispositionAndNeverOverwrites() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let headers = ["Content-Disposition": "attachment; filename*=UTF-8''caf%C3%A9.png", "Content-Type": "image/png"]
        let url = StubURLProtocol.register(.body(status: 200, headers: headers, chunks: [Data("png".utf8)]))
        let first = try await fetch(url, into: dir)
        let second = try await fetch(url, into: dir)
        #expect(first.lastPathComponent == "café.png")
        #expect(second.lastPathComponent == "café 1.png")
        #expect(try Data(contentsOf: first) == Data("png".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 2)
    }

    @Test func extensionComesFromMimeWhenNameHasNone() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = StubURLProtocol.register(.body(status: 200, headers: ["Content-Type": "application/pdf"], chunks: [Data("x".utf8)]))
        #expect(try await fetch(url, into: dir).lastPathComponent == "file.pdf")
    }

    @Test func httpErrorIsReportedAndLeavesNothingBehind() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = StubURLProtocol.register(.body(status: 404, headers: [:], chunks: [Data("no".utf8)]))
        await #expect(throws: BrowserDragError.badStatus(404)) { try await fetch(url, into: dir) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func declaredOversizeIsRefused() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = StubURLProtocol.register(.body(status: 200, headers: ["Content-Length": "5000"], chunks: [Data(count: 5000)]))
        await #expect(throws: BrowserDragError.tooLarge) { try await fetch(url, maxBytes: 1000, into: dir) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func undeclaredOversizeAbortsWhileStreaming() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let chunks = Array(repeating: Data(count: 64 * 1024), count: 32)
        let url = StubURLProtocol.register(.body(status: 200, headers: [:], chunks: chunks))
        await #expect(throws: BrowserDragError.tooLarge) { try await fetch(url, maxBytes: 100_000, into: dir) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func redirectsStayOnHTTP() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = StubURLProtocol.register(.redirect("ftp://example.test/a.zip"))
        await #expect(throws: BrowserDragError.unsupportedRedirect) { try await fetch(bad, into: dir) }
        let final = StubURLProtocol.register(.body(status: 200, headers: ["Content-Type": "image/png"], chunks: [Data("ok".utf8)]))
        let good = StubURLProtocol.register(.redirect(final.absoluteString))
        #expect(try await fetch(good, name: "pic.png", into: dir).lastPathComponent == "pic.png")
    }

    @Test func cancelledDownloadLeavesNoFile() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = StubURLProtocol.register(.body(status: 200, headers: [:], chunks: [Data("x".utf8)]))
        let task = Task { try await fetch(url, into: dir) }
        task.cancel()
        _ = await task.result
        let visible = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix(".") }
        #expect(visible.count <= 1)
        let hidden = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".xmac-fetch") }
        #expect(hidden.isEmpty)
    }

    @Test func imageDataIsWrittenWithATypeExtension() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = BrowserDragPayload.imageData(Data([1, 2, 3]), .png, suggestedName: "My cat")
        let file = try await fetcher().fetch(payload, into: dir)[0]
        #expect(file.lastPathComponent == "My cat.png")
        #expect(try Data(contentsOf: file) == Data([1, 2, 3]))
    }
}
