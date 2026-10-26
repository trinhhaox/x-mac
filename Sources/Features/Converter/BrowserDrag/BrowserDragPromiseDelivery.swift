import AppKit

/// File promises from a browser drop. The system only honours `receivePromisedFiles` while the drag is live, so
/// `start(into:)` must run inside `performDragOperation`; `files()` can be awaited afterwards.
final class BrowserDragPromiseDelivery: @unchecked Sendable {
    static let idleTimeout: TimeInterval = 60

    let receivers: [NSFilePromiseReceiver]
    private let idleTimeout: TimeInterval
    private let lock = NSLock()
    private var target: URL?
    private var expected = 0
    private var finished = 0
    private var received: [URL] = []
    private var firstError: Error?
    private var settled: Result<[URL], Error>?
    private var continuation: CheckedContinuation<[URL], Error>?
    private var lastProgress = Date()
    private var lastBytes: Int64 = 0

    private enum Ending { case complete, idle, cancelled }

    init(receivers: [NSFilePromiseReceiver], idleTimeout: TimeInterval = BrowserDragPromiseDelivery.idleTimeout) {
        self.receivers = receivers
        self.idleTimeout = idleTimeout
    }

    /// Folder the promised files are delivered into; nil until `start`.
    var destination: URL? { lock.withLock { target } }

    func start(into destination: URL) {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            prepare(destination: destination, expected: 1)
            record(destination, error: error)
            return
        }
        prepare(destination: destination, expected: receivers.reduce(0) { $0 + $1.fileNames.count })
        for receiver in receivers where !receiver.fileNames.isEmpty {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: .main) { [self] url, error in
                record(url, error: error)
            }
        }
    }

    func prepare(destination: URL, expected: Int) {
        lock.withLock {
            target = destination
            self.expected = expected
            lastProgress = Date()
        }
        if expected == 0 { settle(.complete) }
    }

    func record(_ url: URL, error: Error?) {
        let complete: Bool = lock.withLock {
            guard settled == nil else { return false }
            if let error { firstError = firstError ?? error } else { received.append(url) }
            finished += 1
            lastProgress = Date()
            return finished >= expected
        }
        if complete { settle(.complete) }
    }

    /// Whatever arrived once every promise reported, or once nothing new landed for `idleTimeout` seconds.
    func files() async throws -> [URL] {
        let watchdog = Task { await watch() }
        defer { watchdog.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<[URL], Error>) in
                lock.lock()
                if let settled {
                    lock.unlock()
                    waiting.resume(with: settled)
                } else {
                    continuation = waiting
                    lock.unlock()
                }
            }
        } onCancel: {
            settle(.cancelled)
        }
    }

    private func settle(_ ending: Ending) {
        lock.lock()
        guard settled == nil else { lock.unlock(); return }
        let result: Result<[URL], Error>
        if ending == .cancelled {
            result = .failure(CancellationError())
        } else if !received.isEmpty {
            result = .success(received)
        } else {
            result = .failure(firstError.map { BrowserDragError.unreachable($0.localizedDescription) } ?? BrowserDragError.nothingReceived)
        }
        settled = result
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(with: result)
    }

    /// A promised file that is still growing counts as progress, so one slow large file is not cut off.
    private func watch() async {
        while !Task.isCancelled {
            let (done, folder) = lock.withLock { (settled != nil, target) }
            if done { return }
            let bytes = folder.map(Self.bytes(in:)) ?? 0
            let idle: TimeInterval = lock.withLock {
                if bytes != lastBytes {
                    lastBytes = bytes
                    lastProgress = Date()
                }
                return Date().timeIntervalSince(lastProgress)
            }
            if idle >= idleTimeout { return settle(.idle) }
            try? await Task.sleep(nanoseconds: UInt64(max(min(idleTimeout - idle, 1), 0.02) * 1_000_000_000))
        }
    }

    private static func bytes(in folder: URL) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
