import Foundation
import Testing
@testable import Xmac

private final class SuccessfulDownloadProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var attempted = Set<String>()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url!.path.hasPrefix("/retry-") {
            Self.lock.lock()
            let first = Self.attempted.insert(request.url!.absoluteString).inserted
            Self.lock.unlock()
            if first {
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost))
                return
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: request.url!.path == "/http-error" ? 404 : 200, httpVersion: nil,
                                       headerFields: ["Content-Length": "7"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("payload".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor @Suite(.serialized) struct DownloadRecoveryTests {
    private func fixture() -> (DownloadManager, DownloadEnvironment, UserDefaults, String, URL) {
        let name = "XmacDownloadRecovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(false, forKey: "Downloads.KeepAwake")
        let environment = DownloadEnvironment(defaults: defaults, startMonitoring: false)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SuccessfulDownloadProtocol.self]
        let manager = DownloadManager(defaults: defaults, environment: environment, configuration: config, notificationsEnabled: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (manager, environment, defaults, name, directory)
    }

    @Test func offlineDownloadCompletesWhenConnectivityReturns() async throws {
        let (manager, environment, defaults, name, directory) = fixture()
        defer { manager.shutdown(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        environment.updateConnection(online: false, metered: false)
        manager.enqueue(rawLinks: "https://xmac.test/file.txt", directory: directory)
        #expect(manager.items.first?.status == .waitingForNetwork)
        manager.clearFinished()
        #expect(manager.items.count == 1)
        environment.updateConnection(online: true, metered: false)
        for _ in 0..<100 {
            if manager.items.first?.status == .completed { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(manager.items.first?.status == .completed)
        #expect(try String(contentsOf: directory.appendingPathComponent("file.txt")) == "payload")
    }

    @Test func reconnectDoesNotResumeUserPausedOrCancelledDownloads() {
        let (manager, environment, defaults, name, _) = fixture()
        defer { manager.shutdown(); defaults.removePersistentDomain(forName: name) }
        environment.updateConnection(online: false, metered: false)
        manager.enqueue(rawLinks: "https://xmac.test/a\nhttps://xmac.test/b")
        let paused = manager.items[0].id
        let cancelled = manager.items[1].id
        manager.pause(paused)
        manager.cancel(cancelled)
        environment.updateConnection(online: true, metered: false)
        #expect(manager.items.first { $0.id == paused }?.status == .paused)
        #expect(manager.items.first { $0.id == cancelled }?.status == .cancelled)
    }

    @Test func meteredConnectionWaitsUntilUserAllowsIt() async throws {
        let (manager, environment, defaults, name, directory) = fixture()
        defer { manager.shutdown(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        environment.avoidMetered = true
        environment.updateConnection(online: true, metered: true)
        manager.enqueue(rawLinks: "https://xmac.test/file.txt", directory: directory)
        #expect(manager.items.first?.status == .waitingForNetwork)
        environment.avoidMetered = false
        for _ in 0..<100 {
            if manager.items.first?.status == .completed { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(manager.items.first?.status == .completed)
    }

    @Test func redirectPolicyRejectsHTTPSToHTTPDowngrade() throws {
        let secure = try #require(URL(string: "https://a.example/file.zip"))
        let plain = try #require(URL(string: "http://b.example/file.zip"))
        #expect(!DownloadManager.allowsRedirect(from: secure, to: plain))
        #expect(DownloadManager.allowsRedirect(from: secure, to: try #require(URL(string: "https://c.example/f"))))
        #expect(DownloadManager.allowsRedirect(from: plain, to: secure))
        #expect(DownloadManager.allowsRedirect(from: plain, to: plain))
    }

    @Test func recoveryRejectsNonNetworkFailuresAndSleepAssertionIsScoped() {
        #expect(DownloadManager.isRecoverableNetworkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)))
        #expect(!DownloadManager.isRecoverableNetworkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(!DownloadManager.isRecoverableNetworkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)))
        #expect(!DownloadManager.isRecoverableNetworkError(NSError(domain: NSCocoaErrorDomain, code: 4)))
        #expect(DownloadEnvironment.shouldKeepAwake(enabled: true, running: true, online: true))
        #expect(!DownloadEnvironment.shouldKeepAwake(enabled: true, running: false, online: true))
        #expect(!DownloadEnvironment.shouldKeepAwake(enabled: false, running: true, online: true))
        #expect(!DownloadEnvironment.shouldKeepAwake(enabled: true, running: true, online: false))
    }

    @Test func transientFailureRetriesWithoutUserAction() async throws {
        let (manager, environment, defaults, name, directory) = fixture()
        defer { manager.shutdown(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        environment.updateConnection(online: true, metered: false)
        manager.enqueue(rawLinks: "https://xmac.test/retry-\(UUID().uuidString)", directory: directory)
        for _ in 0..<150 {
            if manager.items.first?.status == .completed { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(manager.items.first?.status == .completed)
    }

    @Test func downloadedFileIsQuarantinedForGatekeeper() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("XmacQuarantine-\(UUID().uuidString).command")
        try Data("echo hi".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        DownloadManager.markAsDownloadedFromInternet(file, sourceURL: "https://example.com/run.command")

        let properties = try file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        #expect(properties?[kLSQuarantineAgentNameKey as String] as? String == "Xmac")
        #expect(properties?[kLSQuarantineTypeKey as String] as? String == kLSQuarantineTypeWebDownload as String)
    }

    @Test func httpErrorDoesNotWriteAnErrorPageAsAFile() async throws {
        let (manager, environment, defaults, name, directory) = fixture()
        defer { manager.shutdown(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        environment.updateConnection(online: true, metered: false)
        manager.enqueue(rawLinks: "https://xmac.test/http-error", directory: directory)
        for _ in 0..<100 {
            if manager.items.first?.status == .failed { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(manager.items.first?.status == .failed)
        #expect(manager.items.first?.errorMessage?.contains("404") == true)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("http-error").path))
    }
}
