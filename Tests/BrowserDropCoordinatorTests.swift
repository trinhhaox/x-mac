import Foundation
import Testing
@testable import Xmac

@MainActor
@Suite struct BrowserDropCoordinatorTests {
    final class FailureLog { var messages: [String] = [] }

    private func makeCoordinator(mode: BrowserDropMode, downloads: URL, failures: FailureLog = FailureLog()) -> BrowserDropCoordinator {
        let defaults = UserDefaults(suiteName: "browser-drop-\(UUID().uuidString)")!
        defaults.set(mode.rawValue, forKey: BrowserDropCoordinator.modeKey)
        return BrowserDropCoordinator(
            defaults: defaults, fetcher: BrowserDragFetcher(configuration: StubURLProtocol.configuration),
            downloads: downloads, reportFailure: { failures.messages.append($0) }
        )
    }

    @Test func modeDefaultsToDownloads() {
        let coordinator = BrowserDropCoordinator(defaults: UserDefaults(suiteName: "browser-drop-\(UUID().uuidString)")!)
        #expect(coordinator.mode == .downloads)
        coordinator.mode = .convertedOnly
        #expect(coordinator.mode == .convertedOnly)
    }

    @Test func downloadsModeKeepsTheFileInDownloads() async throws {
        let downloads = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let coordinator = makeCoordinator(mode: .downloads, downloads: downloads)
        let inputs = await coordinator.fetch(.imageData(Data([1]), .png, suggestedName: "a"))
        #expect(inputs?.urls.first?.deletingLastPathComponent().standardizedFileURL == downloads.standardizedFileURL)
        #expect(inputs?.outputDirectory == nil)
        #expect(inputs?.disposable == false)
    }

    @Test func convertedOnlyUsesScratchAndSendsResultsToDownloads() async throws {
        let downloads = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let coordinator = makeCoordinator(mode: .convertedOnly, downloads: downloads)
        let inputs = try #require(await coordinator.fetch(.imageData(Data([1]), .png, suggestedName: "a")))
        #expect(inputs.disposable)
        #expect(inputs.outputDirectory == downloads)
        let file = try #require(inputs.urls.first)
        #expect(file.standardizedFileURL.path.hasPrefix(BrowserDropCoordinator.scratchRoot.standardizedFileURL.path))
        BrowserDropCoordinator.dispose(inputs.urls)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloads.path).isEmpty)
    }

    @Test func disposeNeverTouchesFilesOutsideScratch() throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("keep.txt")
        try Data("x".utf8).write(to: file)
        BrowserDropCoordinator.dispose([file])
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func failuresAreReportedAndNothingIsLeftRunning() async throws {
        let downloads = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let failures = FailureLog()
        let coordinator = makeCoordinator(mode: .convertedOnly, downloads: downloads, failures: failures)
        let url = StubURLProtocol.register(.body(status: 500, headers: [:], chunks: []))
        #expect(await coordinator.fetch(.remote(url, suggestedName: nil)) == nil)
        #expect(failures.messages.count == 1)
        #expect(coordinator.activeCount == 0)
    }

    @Test func managerDeletesScratchInputsWhenTheJobEnds() async throws {
        let defaults = UserDefaults(suiteName: "browser-drop-\(UUID().uuidString)")!
        let converter = FakeConverter()
        let manager = ConverterManager(
            registry: ConverterRegistry(converters: [converter], locator: BinaryLocator(defaults: defaults)),
            defaults: defaults, notify: { _, _ in }, playSound: { _ in }
        )
        let scratch = BrowserDropCoordinator.scratchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let input = scratch.appendingPathComponent("in.txt")
        try Data("x".utf8).write(to: input)
        let output = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        manager.enqueue(inputs: [input], target: converter.targets(for: input)[0], outputDirectory: output, disposeInputs: true)
        for _ in 0..<500 where !(manager.jobs.first?.state.isFinished ?? false) { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(manager.jobs.first?.state.isFinished == true)
        #expect(!FileManager.default.fileExists(atPath: input.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).contains("in.out"))
    }
}
