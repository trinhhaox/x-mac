import Combine
import CoreServices
import Foundation

/// Converts files that appear in watched folders. Only files created or renamed into a folder after
/// monitoring starts are considered; existing files are never back-filled.
///
/// FSEvents (not a directory fd + DispatchSource) because it names the changed paths, so no
/// directory diffing is needed, and one stream covers every folder.
@MainActor
final class WatchFolderMonitor {
    static let shared = WatchFolderMonitor()

    private let store: WatchFolderStore
    private let manager: ConverterManager
    private let stat: (URL) -> FileSnapshot?
    private let sleep: (TimeInterval) async throws -> Void
    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    private var subscription: AnyCancellable?
    private var inFlight = Set<String>()

    init(
        store: WatchFolderStore? = nil,
        manager: ConverterManager? = nil,
        stat: @escaping (URL) -> FileSnapshot? = FileSnapshot.read,
        sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        let manager = manager ?? .shared
        self.store = store ?? .shared
        self.manager = manager
        self.stat = stat
        self.sleep = sleep
        manager.onOutputProduced = { [weak self] url in self?.recordOutput(url) }
    }

    /// Follows the store from now on: the stream runs while the switch is on and a rule is enabled.
    func start() {
        guard subscription == nil else { return }
        subscription = Publishers.CombineLatest(store.$isEnabled, store.$rules)
            .sink { [weak self] enabled, rules in
                self?.watch(enabled ? Set(rules.filter(\.enabled).map(\.folderPath)).sorted() : [])
            }
    }

    func stop() {
        subscription = nil
        watch([])
    }

    // MARK: Decision pipeline

    /// Waits for the file to settle, then queues one conversion per matching rule that has not seen it.
    func process(_ file: URL) async {
        guard !WatchCandidateFilter.isIgnored(file), activeRules(for: file).isEmpty == false,
              inFlight.insert(file.path).inserted else { return }
        defer { inFlight.remove(file.path) }
        guard let snapshot = await WatchStability.waitUntilStable(file, stat: stat, sleep: sleep),
              !store.processed.isOutput(file.path, snapshot) else { return }
        for rule in activeRules(for: file) where !store.processed.wasHandled(by: rule.id, file.path) {
            guard let target = manager.registry.targets(for: [file]).first(where: { $0.id == rule.targetID }) else { continue }
            store.updateProcessed { $0.markHandled(by: rule.id, file.path) }
            manager.enqueue(inputs: [file], target: target, outputDirectory: rule.outputDirectory)
        }
    }

    private func activeRules(for file: URL) -> [WatchFolderRule] {
        guard store.isEnabled else { return [] }
        return store.rules.filter { $0.enabled && $0.accepts(file) }
    }

    private func recordOutput(_ url: URL) {
        guard let snapshot = stat(url) else { return }
        store.updateProcessed { $0.markOutput(url.path, snapshot) }
    }

    // MARK: FSEvents

    private func watch(_ paths: [String]) {
        guard paths != watchedPaths else { return }
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        watchedPaths = paths
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let created = FSEventStreamCreate(
            nil, Self.callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags
        ) else {
            NSLog("WatchFolders: could not create FSEvent stream")
            watchedPaths = []
            return
        }
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
        stream = created
    }

    /// Delivered on the main queue (see `FSEventStreamSetDispatchQueue`).
    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
        guard let info, let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
        let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
        let monitor = Unmanaged<WatchFolderMonitor>.fromOpaque(info).takeUnretainedValue()
        MainActor.assumeIsolated { monitor.receive(paths: paths, flags: flags) }
    }

    private static let arrivalFlags = UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed)

    private func receive(paths: [String], flags: [FSEventStreamEventFlags]) {
        for (path, flag) in zip(paths, flags)
        where flag & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 && flag & Self.arrivalFlags != 0 {
            let file = URL(fileURLWithPath: path)
            Task { await process(file) }
        }
    }
}
