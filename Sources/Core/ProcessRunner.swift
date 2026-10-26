import Foundation

public struct ProcessResult {
    public let status: Int32
    public let stdout: Data
    public let stderrTail: String

    /// Converts a non-zero exit status into `ProcessRunnerError.nonZeroExit`.
    public func throwIfFailed() throws -> ProcessResult {
        guard status == 0 else { throw ProcessRunnerError.nonZeroExit(status, stderrTail) }
        return self
    }
}

public enum ProcessRunnerError: Error, Equatable {
    case launchFailed(String)
    case timedOut
    case cancelled
    case nonZeroExit(Int32, String)
}

public enum ProcessRunner {
    static let stderrTailLimit = 4096
    static let killGracePeriod: TimeInterval = 3
    static let readerDrainTimeout: TimeInterval = 5
    private static let live = LiveProcesses()

    /// For app shutdown: SIGTERM every running child, wait up to 1 s in total, then SIGKILL the rest.
    public static func terminateAll() {
        let processes = live.snapshot()
        processes.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(1)
        while processes.contains(where: \.isRunning), Date() < deadline { usleep(20_000) }
        for process in processes where process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    fileprivate static func track(_ process: Process) { live.insert(process) }
    fileprivate static func untrack(_ process: Process) { live.remove(process) }

    /// A non-zero exit is returned in `ProcessResult.status`, not thrown; call `throwIfFailed()` to opt in.
    public static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval? = nil,
        onStderrLine: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let job = ProcessJob(executable: executable, arguments: arguments, timeout: timeout, onStderrLine: onStderrLine)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try job.execute() })
                }
            }
        } onCancel: {
            job.cancel()
        }
    }
}

private final class LiveProcesses: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func insert(_ process: Process) { lock.withLock { processes[ObjectIdentifier(process)] = process } }
    func remove(_ process: Process) { lock.withLock { processes[ObjectIdentifier(process)] = nil } }
    func snapshot() -> [Process] { lock.withLock { Array(processes.values) } }
}

private final class ProcessJob: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let timeout: TimeInterval?
    private let onStderrLine: ((String) -> Void)?
    private let lock = NSLock()
    private var isRunning = false
    private var wasCancelled = false
    private var didTimeOut = false
    private var stdoutData = Data()
    private var stderrTail = Data()

    init(executable: URL, arguments: [String], timeout: TimeInterval?, onStderrLine: ((String) -> Void)?) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.timeout = timeout
        self.onStderrLine = onStderrLine
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let running = isRunning
        lock.unlock()
        if running { terminate() }
    }

    func execute() throws -> ProcessResult {
        lock.lock()
        if wasCancelled {
            lock.unlock()
            throw ProcessRunnerError.cancelled
        }
        do {
            try process.run()
        } catch {
            lock.unlock()
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }
        isRunning = true
        ProcessRunner.track(process)
        lock.unlock()

        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                lock.lock()
                let running = isRunning
                if running { didTimeOut = true }
                lock.unlock()
                if running { terminate() }
            }
        }

        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async { [self] in
            readStdout()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async { [self] in
            readStderr()
            readers.leave()
        }
        process.waitUntilExit()
        ProcessRunner.untrack(process)
        // A grandchild that inherited the pipes can keep them open after the child exits;
        // give up on the readers (they end with that grandchild) and use what arrived.
        _ = readers.wait(timeout: .now() + ProcessRunner.readerDrainTimeout)

        lock.lock()
        isRunning = false
        let cancelled = wasCancelled
        let timedOut = didTimeOut
        lock.unlock()
        if cancelled { throw ProcessRunnerError.cancelled }
        if timedOut { throw ProcessRunnerError.timedOut }
        lock.lock()
        defer { lock.unlock() }
        return ProcessResult(
            status: process.terminationStatus,
            stdout: stdoutData,
            stderrTail: String(decoding: stderrTail, as: UTF8.self)
        )
    }

    /// SIGTERM first; SIGKILL if the child ignores it.
    private func terminate() {
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + ProcessRunner.killGracePeriod) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func readStdout() {
        let handle = stdoutPipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            lock.withLock { stdoutData.append(chunk) }
        }
    }

    /// Streams stderr line by line (`\n` or `\r`, as ffmpeg uses both), keeping the last 4 KB.
    private func readStderr() {
        let handle = stderrPipe.fileHandleForReading
        var pending = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            lock.withLock {
                stderrTail.append(chunk)
                if stderrTail.count > ProcessRunner.stderrTailLimit {
                    stderrTail = stderrTail.suffix(ProcessRunner.stderrTailLimit)
                }
            }
            pending.append(chunk)
            while let index = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                emit(pending[pending.startIndex..<index])
                pending = Data(pending[pending.index(after: index)...])
            }
        }
        emit(pending[...])
    }

    private func emit(_ bytes: Data.SubSequence) {
        guard let onStderrLine, !bytes.isEmpty else { return }
        onStderrLine(String(decoding: bytes, as: UTF8.self))
    }
}
