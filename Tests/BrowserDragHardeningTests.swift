import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Xmac

private func isQuarantined(_ url: URL) -> Bool {
    getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
}

@Suite struct BrowserDragFetchHardeningTests {
    private func fetcher() -> BrowserDragFetcher { BrowserDragFetcher(configuration: StubURLProtocol.configuration) }

    @Test func everyFetchedFileIsQuarantined() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = StubURLProtocol.register(.body(status: 200, headers: ["Content-Type": "image/png"], chunks: [Data("x".utf8)]))
        let downloaded = try await fetcher().fetch(.remote(url, suggestedName: "a.png"), into: dir)[0]
        let written = try await fetcher().fetch(.imageData(Data([1]), .png, suggestedName: "b"), into: dir)[0]
        #expect(isQuarantined(downloaded))
        #expect(isQuarantined(written))
    }

    @Test func promisedFilesAreRenamedSafelyMovedAndQuarantined() async throws {
        let root = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("staging"), final = root.appendingPathComponent("final")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let delivered = staging.appendingPathComponent("photo\u{202E}gnp.command")
        try Data("x".utf8).write(to: delivered)
        let delivery = BrowserDragPromiseDelivery(receivers: [])
        delivery.prepare(destination: staging, expected: 1)
        delivery.record(delivered, error: nil)
        let files = try await fetcher().fetch(.promise(delivery), into: final, staging: staging)
        #expect(files.map(\.lastPathComponent) == ["photognp.command"])
        #expect(isQuarantined(files[0]))
        #expect(!FileManager.default.fileExists(atPath: delivered.path))
    }

    @Test func promiseThatWasNeverStartedFailsInsteadOfWaiting() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: BrowserDragError.nothingReceived) {
            try await fetcher().fetch(.promise(BrowserDragPromiseDelivery(receivers: [])), into: dir)
        }
    }

    @Test func plainHTTPIsRefusedInitiallyAndOnRedirect() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: BrowserDragError.insecureLink) {
            try await fetcher().fetch(.remote(URL(string: "http://example.test/a.pdf")!, suggestedName: nil), into: dir)
        }
        let downgrade = StubURLProtocol.register(.redirect("http://example.test/a.pdf"))
        await #expect(throws: BrowserDragError.unsupportedRedirect) {
            try await fetcher().fetch(.remote(downgrade, suggestedName: nil), into: dir)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func nameTakenByAnotherWriterIsRetriedWithANewName() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let taken = dir.appendingPathComponent("pic.png")
        try Data("other".utf8).write(to: taken)
        var calls = 0
        var racing = fetcher()
        racing.pickDestination = { name, directory in
            calls += 1
            return calls == 1 ? taken : DownloadManager.uniqueDestination(for: name, in: directory)
        }
        let written = try await racing.fetch(.imageData(Data([1]), .png, suggestedName: "pic"), into: dir)[0]
        #expect(written.lastPathComponent == "pic 1.png")
        #expect(try Data(contentsOf: taken) == Data("other".utf8))
    }

    @Test func oversizedImageDataIsRefused() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var small = fetcher()
        small.maxBytes = 2
        await #expect(throws: BrowserDragError.tooLarge) {
            try await small.fetch(.imageData(Data(count: 3), .png, suggestedName: nil), into: dir)
        }
    }

    @Test func onlyServerTrustChallengesProceed() {
        #expect(BrowserDragDownloader.disposition(forChallengeMethod: NSURLAuthenticationMethodServerTrust) == .performDefaultHandling)
        for method in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodNTLM, NSURLAuthenticationMethodClientCertificate] {
            #expect(BrowserDragDownloader.disposition(forChallengeMethod: method) == .cancelAuthenticationChallenge)
        }
    }
}

@Suite struct BrowserDragPromiseDeliveryTests {
    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    @Test func completesWhenEveryPromiseReported() async throws {
        let delivery = BrowserDragPromiseDelivery(receivers: [], idleTimeout: 5)
        delivery.prepare(destination: file("d"), expected: 2)
        delivery.record(file("a"), error: nil)
        delivery.record(file("b"), error: nil)
        delivery.record(file("late"), error: nil)
        #expect(try await delivery.files() == [file("a"), file("b")])
    }

    @Test func idleTimeoutReturnsWhatArrived() async throws {
        let delivery = BrowserDragPromiseDelivery(receivers: [], idleTimeout: 0.2)
        delivery.prepare(destination: file("d"), expected: 3)
        delivery.record(file("a"), error: nil)
        #expect(try await delivery.files() == [file("a")])
    }

    @Test func idleTimeoutWithNothingThrows() async {
        let delivery = BrowserDragPromiseDelivery(receivers: [], idleTimeout: 0.2)
        delivery.prepare(destination: file("d"), expected: 1)
        await #expect(throws: BrowserDragError.nothingReceived) { try await delivery.files() }
    }

    @Test func onlyFailuresSurfaceTheFirstError() async {
        let delivery = BrowserDragPromiseDelivery(receivers: [], idleTimeout: 5)
        delivery.prepare(destination: file("d"), expected: 1)
        delivery.record(file("a"), error: URLError(.cannotWriteToFile))
        await #expect(throws: BrowserDragError.self) { try await delivery.files() }
    }

    @Test func cancellationEndsTheWaitOnce() async throws {
        let delivery = BrowserDragPromiseDelivery(receivers: [], idleTimeout: 60)
        delivery.prepare(destination: file("d"), expected: 1)
        let waiting = Task { try await delivery.files() }
        try await Task.sleep(nanoseconds: 50_000_000)
        waiting.cancel()
        delivery.record(file("a"), error: nil)
        await #expect(throws: CancellationError.self) { try await waiting.value }
    }

    @Test func aGrowingFileCountsAsProgress() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delivery = BrowserDragPromiseDelivery(receivers: [], idleTimeout: 0.4)
        delivery.prepare(destination: dir, expected: 1)
        let growing = dir.appendingPathComponent("big")
        FileManager.default.createFile(atPath: growing.path, contents: nil)
        let writer = Task {
            let handle = try FileHandle(forWritingTo: growing)
            defer { try? handle.close() }
            for _ in 0..<8 {
                try handle.write(contentsOf: Data(count: 10))
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            delivery.record(growing, error: nil)
        }
        #expect(try await delivery.files() == [growing])
        _ = try await writer.value
    }
}

@MainActor
@Suite struct BrowserDropFollowUpTests {
    final class FailureLog { var messages: [String] = [] }

    private func coordinator(mode: BrowserDropMode, downloads: URL, failures: FailureLog) -> BrowserDropCoordinator {
        let defaults = UserDefaults(suiteName: "browser-drop-\(UUID().uuidString)")!
        defaults.set(mode.rawValue, forKey: BrowserDropCoordinator.modeKey)
        return BrowserDropCoordinator(
            defaults: defaults, fetcher: BrowserDragFetcher(configuration: StubURLProtocol.configuration),
            downloads: downloads, reportFailure: { failures.messages.append($0) }
        )
    }

    private var emptyRegistry: ConverterRegistry {
        ConverterRegistry(converters: [FakeConverter()], locator: BinaryLocator(defaults: UserDefaults(suiteName: "browser-drop-\(UUID().uuidString)")!))
    }

    @Test(arguments: [BrowserDropMode.downloads, .convertedOnly])
    func fetchedFilesWithoutTargetsAreDeletedAndReported(mode: BrowserDropMode) async throws {
        let downloads = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let failures = FailureLog()
        let drops = coordinator(mode: mode, downloads: downloads, failures: failures)
        let inputs = try #require(await drops.fetch(.imageData(Data([1]), .png, suggestedName: "a")))
        var shown = false
        drops.deliver(inputs, registry: emptyRegistry) { _ in shown = true }
        #expect(!shown)
        #expect(inputs.urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloads.path).isEmpty)
        #expect(failures.messages == [L10n.text("Không có định dạng đích phù hợp cho các tệp này.")])
    }

    @Test func userFilesAndConvertibleFetchesAreAlwaysShown() throws {
        let drops = coordinator(mode: .downloads, downloads: FileManager.default.temporaryDirectory, failures: FailureLog())
        var shown = 0
        drops.deliver(BrowserDropInputs(urls: [URL(fileURLWithPath: "/tmp/mine.png")]), registry: emptyRegistry) { _ in shown += 1 }
        drops.deliver(BrowserDropInputs(urls: [URL(fileURLWithPath: "/tmp/a.txt")], created: true), registry: emptyRegistry) { _ in shown += 1 }
        #expect(shown == 2)
    }

    @Test func severalPayloadsMergeInOrder() async throws {
        let downloads = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let drops = coordinator(mode: .downloads, downloads: downloads, failures: FailureLog())
        let merged = try #require(await drops.fetch([
            .imageData(Data([1]), .png, suggestedName: "first"), .imageData(Data([2]), .png, suggestedName: "second"),
        ]))
        #expect(merged.urls.map(\.lastPathComponent) == ["first.png", "second.png"])
        #expect(merged.created)
    }

    @Test func downloadsAreStagedOutsideDownloadsAndTheStagingIsRemoved() async throws {
        let downloads = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let drops = coordinator(mode: .downloads, downloads: downloads, failures: FailureLog())
        let url = StubURLProtocol.register(.body(status: 200, headers: ["Content-Type": "image/png"], chunks: [Data("x".utf8)]))
        let inputs = try #require(await drops.fetch(.remote(url, suggestedName: "pic.png")))
        #expect(inputs.urls.map(\.lastPathComponent) == ["pic.png"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloads.path) == ["pic.png"])
    }

    @Test func rescueMovesScratchFilesToTheFolderWithoutOverwriting() throws {
        let root = try ConverterFixtures.makeTempDirectory(), folder = try ConverterFixtures.makeTempDirectory()
        defer { [root, folder].forEach { try? FileManager.default.removeItem(at: $0) } }
        let scratch = root.appendingPathComponent("s1")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let input = scratch.appendingPathComponent("a.txt")
        try Data("new".utf8).write(to: input)
        try Data("old".utf8).write(to: folder.appendingPathComponent("a.txt"))
        let outside = folder.appendingPathComponent("outside.txt")
        try Data("keep".utf8).write(to: outside)
        BrowserDropCoordinator.rescue([input, outside], into: folder, root: root)
        #expect(try String(contentsOf: folder.appendingPathComponent("a 1.txt")) == "new")
        #expect(try String(contentsOf: folder.appendingPathComponent("a.txt")) == "old")
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    @Test func staleScratchFoldersAreSweptButFreshOnesStay() throws {
        let root = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fresh = root.appendingPathComponent("fresh")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        BrowserDropCoordinator.sweepStaleScratch(root: root)
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        BrowserDropCoordinator.sweepStaleScratch(root: root, now: Date().addingTimeInterval(25 * 3600))
        #expect(!FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test func aFailedConversionKeepsTheFetchedFileInTheRescueFolder() async throws {
        let defaults = UserDefaults(suiteName: "browser-drop-\(UUID().uuidString)")!
        let converter = FakeConverter(behavior: .fail)
        let rescue = try ConverterFixtures.makeTempDirectory(), output = try ConverterFixtures.makeTempDirectory()
        defer { [rescue, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        let manager = ConverterManager(
            registry: ConverterRegistry(converters: [converter], locator: BinaryLocator(defaults: defaults)),
            defaults: defaults, notify: { _, _ in }, playSound: { _ in }, rescueFolder: rescue
        )
        let scratch = BrowserDropCoordinator.newScratchFolder()
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let input = scratch.appendingPathComponent("in.txt")
        try Data("x".utf8).write(to: input)
        manager.enqueue(inputs: [input], target: converter.targets(for: input)[0], outputDirectory: output, disposeInputs: true)
        for _ in 0..<500 where !(manager.jobs.first?.state.isFinished ?? false) { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: rescue.path) == ["in.txt"])
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }
}

@Suite struct BrowserDragPeekTests {
    @Test func peekNeverReadsImageBytes() {
        var snapshot = BrowserDragSnapshot(values: ["public.png": Data([1]), "public.url": Data("https://example.com/a.pdf".utf8)])
        snapshot.read = { type in
            #expect(!type.hasPrefix("public.png"), "image bytes must not be read")
            return type == "public.url" ? Data("https://example.com/a.pdf".utf8) : nil
        }
        #expect(BrowserDragPayload.peekInputs(snapshot)?.first?.pathExtension == "png")
        let tiffWithLink = BrowserDragSnapshot(values: ["public.tiff": Data([1]), "public.url": Data("https://example.com/a.pdf".utf8)])
        #expect(BrowserDragPayload.peekInputs(tiffWithLink)?.first?.lastPathComponent == "a.pdf")
        #expect(BrowserDragPayload.peekInputs(BrowserDragSnapshot(values: ["public.url": Data("https://example.com/".utf8)])) == nil)
    }

    @Test func hugeDataURLsAreRejected() {
        let bytes = String(repeating: "A", count: BrowserDragPayload.maxDataURLBytes + 4)
        #expect(BrowserDragPayload.link(from: "data:image/png;base64,\(bytes)", name: nil) == nil)
    }

    @Test func snapshotKnowsWhetherAnImageComesAlong() {
        #expect(BrowserDragSnapshot(values: ["public.tiff": Data([1])]).hasImage)
        #expect(!BrowserDragSnapshot(values: ["public.url": Data([1])]).hasImage)
    }
}
