import Foundation
import Testing
@testable import Xmac

struct FakeConverter: FileConverter {
    enum Behavior { case write, fail, hang }

    var id = "fake"
    var requiredTool: ExternalTool?
    var group: ConversionGroup = .image
    var behavior: Behavior = .write
    var combines = false

    func targets(for input: URL) -> [ConversionTarget] {
        guard ["txt", "md"].contains(input.pathExtension) else { return [] }
        return [ConversionTarget(id: "\(id).out", title: "Out", fileExtension: "out", group: group, combinesInputs: combines)]
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        try Data("partial".utf8).write(to: request.outputURL)
        switch behavior {
        case .write: progress(1)
        case .fail: throw ConversionError.failed("boom")
        case .hang: while true { try await Task.sleep(nanoseconds: 10_000_000) }
        }
    }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [(UUID, ConversionJobEvent)] = []

    func record(_ id: UUID, _ event: ConversionJobEvent) {
        lock.lock(); events.append((id, event)); lock.unlock()
    }

    func events(for id: UUID) -> [ConversionJobEvent] {
        lock.lock(); defer { lock.unlock() }
        return events.filter { $0.0 == id }.map(\.1)
    }

    func hasStarted(_ id: UUID) -> Bool {
        events(for: id).contains { if case .started = $0 { return true } else { return false } }
    }

    func outcome(_ id: UUID) -> ConversionJobEvent? {
        events(for: id).first {
            switch $0 {
            case .succeeded, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    /// Polls up to 5 s; true when the condition became true.
    func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}

@Suite struct ConversionQueueTests {
    private let locator = BinaryLocator(defaults: UserDefaults(suiteName: "queue-tests-\(UUID().uuidString)")!)

    private func makeQueue(
        _ converters: [FileConverter], maxConcurrent: Int = 4, log: EventLog
    ) -> ConversionQueue {
        ConversionQueue(
            registry: ConverterRegistry(converters: converters, locator: locator),
            reserver: OutputPathReserver(), maxConcurrent: maxConcurrent
        ) { log.record($0, $1) }
    }

    private func target(_ converter: FakeConverter) -> ConversionTarget {
        converter.targets(for: URL(fileURLWithPath: "/x.txt"))[0]
    }

    private func makeInput(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("in".utf8).write(to: url)
        return url
    }

    private func outputURL(_ event: ConversionJobEvent?) -> URL? {
        if case .succeeded(let url) = event { return url }
        return nil
    }

    @Test func neverOverwritesExistingOrConcurrentNames() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("keep".utf8).write(to: dir.appendingPathComponent("photo.out"))
        let inputs = try ["photo.txt", "photo.md"].map { try makeInput($0, in: dir) }
        let converter = FakeConverter()
        let log = EventLog()
        let queue = makeQueue([converter], log: log)
        let ids = inputs.map { _ in UUID() }
        for (id, input) in zip(ids, inputs) {
            await queue.enqueue(id: id, inputs: [input], target: target(converter), preset: ConversionPreset())
        }
        #expect(await log.wait { ids.allSatisfy { log.outcome($0) != nil } })
        let outputs = try ids.map { try #require(outputURL(log.outcome($0))) }
        #expect(Set(outputs.map(\.path)).count == 2)
        #expect(!outputs.contains { $0.lastPathComponent == "photo.out" })
        #expect(try String(contentsOf: dir.appendingPathComponent("photo.out")) == "keep")
        #expect(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func combiningTargetIsNamedAfterFirstInput() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inputs = try ["first.txt", "second.txt"].map { try makeInput($0, in: dir) }
        let converter = FakeConverter(combines: true)
        let log = EventLog()
        let queue = makeQueue([converter], log: log)
        let id = UUID()
        await queue.enqueue(id: id, inputs: inputs, target: target(converter), preset: ConversionPreset())
        #expect(await log.wait { log.outcome(id) != nil })
        #expect(outputURL(log.outcome(id))?.lastPathComponent == "first.out")
    }

    @Test func failureLeavesNoPartialOrOutput() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeInput("a.txt", in: dir)
        let converter = FakeConverter(behavior: .fail)
        let log = EventLog()
        let queue = makeQueue([converter], log: log)
        let id = UUID()
        await queue.enqueue(id: id, inputs: [input], target: target(converter), preset: ConversionPreset())
        #expect(await log.wait { log.outcome(id) != nil })
        guard case .failed(let error) = log.outcome(id) else { Issue.record("expected failure"); return }
        #expect(error as? ConversionError == .failed("boom"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.txt"])
    }

    @Test func cancellingRunningJobCleansUp() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try makeInput("a.txt", in: dir)
        let converter = FakeConverter(behavior: .hang)
        let log = EventLog()
        let queue = makeQueue([converter], log: log)
        let id = UUID()
        await queue.enqueue(id: id, inputs: [input], target: target(converter), preset: ConversionPreset())
        #expect(await log.wait { log.hasStarted(id) })
        await queue.cancel(id)
        #expect(await log.wait { log.outcome(id) != nil })
        guard case .cancelled = log.outcome(id) else { Issue.record("expected cancelled"); return }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.txt"])
    }

    @Test func toolBackedConvertersRunOneAtATimeAndPendingCanBeCancelled() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let override = dir.appendingPathComponent("fake-tool")
        try Data("#!/bin/sh\n".utf8).write(to: override)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: override.path)
        let defaults = UserDefaults(suiteName: "queue-tool-\(UUID().uuidString)")!
        defaults.set(override.path, forKey: ExternalTool.ffmpeg.overrideDefaultsKey)
        let converter = FakeConverter(requiredTool: .ffmpeg, behavior: .hang)
        let log = EventLog()
        let queue = ConversionQueue(
            registry: ConverterRegistry(converters: [converter], locator: BinaryLocator(defaults: defaults)),
            reserver: OutputPathReserver()
        ) { log.record($0, $1) }
        let inputs = try ["a.txt", "b.txt"].map { try makeInput($0, in: dir) }
        let ids = [UUID(), UUID()]
        for (id, input) in zip(ids, inputs) {
            await queue.enqueue(id: id, inputs: [input], target: target(converter), preset: ConversionPreset())
        }
        #expect(await log.wait { log.hasStarted(ids[0]) })
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(!log.hasStarted(ids[1]))
        await queue.cancel(ids[1])
        #expect(await log.wait { log.outcome(ids[1]) != nil })
        #expect(!log.hasStarted(ids[1]))
        await queue.cancelAll()
        #expect(await log.wait { log.outcome(ids[0]) != nil })
    }

    @Test func respectsMaxConcurrency() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let converter = FakeConverter(behavior: .hang)
        let log = EventLog()
        let queue = makeQueue([converter], maxConcurrent: 1, log: log)
        let ids = [UUID(), UUID()]
        for (id, name) in zip(ids, ["a.txt", "b.txt"]) {
            await queue.enqueue(id: id, inputs: [try makeInput(name, in: dir)], target: target(converter), preset: ConversionPreset())
        }
        #expect(await log.wait { log.hasStarted(ids[0]) })
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(!log.hasStarted(ids[1]))
        await queue.cancelAll()
        #expect(await log.wait { ids.allSatisfy { log.outcome($0) != nil } })
    }

    @Test func missingToolFailsImmediately() async throws {
        let converter = FakeConverter(requiredTool: .soffice)
        let log = EventLog()
        let queue = makeQueue([converter], log: log)
        let id = UUID()
        await queue.enqueue(id: id, inputs: [URL(fileURLWithPath: "/x/a.txt")], target: target(converter), preset: ConversionPreset())
        guard case .failed(let error) = log.outcome(id) else { Issue.record("expected failure"); return }
        #expect(error as? ConversionError == .toolMissing(.soffice))
    }

    @Test func pdfPagesGoIntoAFolderNamedAfterThePDF() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try ConverterFixtures.writePDF(to: dir.appendingPathComponent("doc.pdf"), pages: 2)
        let registry = ConverterRegistry(converters: [PDFConverter()], locator: locator)
        let log = EventLog()
        let queue = ConversionQueue(registry: registry, reserver: OutputPathReserver()) { log.record($0, $1) }
        let id = UUID()
        await queue.enqueue(id: id, inputs: [pdf], target: try #require(registry.targets(for: [pdf]).first { $0.id == "pdf.png" }), preset: ConversionPreset())
        #expect(await log.wait { log.outcome(id) != nil })
        let output = try #require(outputURL(log.outcome(id)))
        #expect(output.lastPathComponent == "doc")
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["doc", "doc.pdf"])
    }
}

@Suite struct ConversionNamingTests {
    @Test func compoundArchiveExtensionsAreStripped() {
        func base(_ name: String) -> String { ConversionQueue.baseName(of: URL(fileURLWithPath: "/tmp/\(name)")) }
        #expect(base("x.tar.gz") == "x")
        #expect(base("Data.TAR.BZ2") == "Data")
        #expect(base("a.b.tar.xz") == "a.b")
        #expect(base("x.tgz") == "x")
        #expect(base("photo.jpeg") == "photo")
    }

    @Test func partialFilesAreHiddenAndKeepTheRealExtension() {
        let partial = ConversionQueue.partialURL(for: URL(fileURLWithPath: "/tmp/a/clip.mp4"), fileExtension: "mp4")
        #expect(partial.lastPathComponent == ".clip.xmac-partial.mp4")
        let folder = ConversionQueue.partialURL(for: URL(fileURLWithPath: "/tmp/a/x"), fileExtension: "")
        #expect(folder.lastPathComponent == ".x.xmac-partial")
    }

    @Test func sweepRemovesOnlyOldConverterDirectories() throws {
        let root = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("xmac-convert-old")
        let fresh = root.appendingPathComponent("xmac-convert-fresh")
        let other = root.appendingPathComponent("other-old")
        for url in [old, fresh, other] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let past = Date().addingTimeInterval(-7200)
        for url in [old, other] { try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path) }
        ConverterWorkspace.sweepStaleTempDirectories(olderThan: 3600, in: root)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
