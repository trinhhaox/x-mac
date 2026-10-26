import Foundation

public enum ConversionJobEvent {
    case started
    case progress(Double)
    case succeeded(URL)
    case failed(Error)
    case cancelled
}

/// Runs conversions with bounded concurrency. Converters write to a hidden sibling file that is
/// moved onto the reserved name only on success, so a failure or cancel never leaves a partial result.
public actor ConversionQueue {
    public typealias EventHandler = @Sendable (UUID, ConversionJobEvent) -> Void

    private struct Job {
        let id: UUID
        let inputs: [URL]
        let target: ConversionTarget
        let preset: ConversionPreset
        let outputDirectory: URL?
        let converter: FileConverter

        /// External tools and heavy media/office work run one at a time to avoid thrashing the machine.
        var isSerial: Bool {
            converter.requiredTool != nil || target.group == .media || target.group == .office
        }
    }

    private let registry: ConverterRegistry
    private let reserver: OutputPathReserver
    private let maxConcurrent: Int
    private let onEvent: EventHandler
    private var pending: [Job] = []
    private var running: [UUID: (task: Task<Void, Never>, isSerial: Bool)] = [:]

    public init(
        registry: ConverterRegistry,
        reserver: OutputPathReserver = .shared,
        maxConcurrent: Int = min(4, ProcessInfo.processInfo.activeProcessorCount),
        onEvent: @escaping EventHandler
    ) {
        self.registry = registry
        self.reserver = reserver
        self.maxConcurrent = max(1, maxConcurrent)
        self.onEvent = onEvent
    }

    /// `outputDirectory` overrides the default (next to the first input); it is created when missing.
    public func enqueue(
        id: UUID, inputs: [URL], target: ConversionTarget, preset: ConversionPreset, outputDirectory: URL? = nil
    ) {
        guard !inputs.isEmpty, let converter = registry.converter(for: target) else {
            onEvent(id, .failed(ConversionError.unsupportedInput(target.id)))
            return
        }
        if let tool = converter.requiredTool, !registry.isAvailable(tool) {
            onEvent(id, .failed(ConversionError.toolMissing(tool)))
            return
        }
        pending.append(Job(
            id: id, inputs: inputs, target: target, preset: preset, outputDirectory: outputDirectory, converter: converter
        ))
        pump()
    }

    public func cancel(_ id: UUID) {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            pending.remove(at: index)
            onEvent(id, .cancelled)
        } else {
            running[id]?.task.cancel()
        }
    }

    public func cancelAll() {
        let waiting = pending
        pending.removeAll()
        waiting.forEach { onEvent($0.id, .cancelled) }
        running.values.forEach { $0.task.cancel() }
    }

    private func pump() {
        var index = 0
        while index < pending.count, running.count < maxConcurrent {
            if pending[index].isSerial, running.values.contains(where: \.isSerial) {
                index += 1
                continue
            }
            start(pending.remove(at: index))
        }
    }

    private func start(_ job: Job) {
        let reserver = reserver
        let onEvent = onEvent
        // Detached: converters may do blocking work and must not occupy this actor.
        let task = Task.detached { [weak self] in
            onEvent(job.id, .started)
            let result = await Self.execute(job, reserver: reserver) { onEvent(job.id, .progress($0)) }
            await self?.didFinish(job.id, result)
        }
        running[job.id] = (task, job.isSerial)
    }

    private func didFinish(_ id: UUID, _ result: Result<URL, Error>) {
        running[id] = nil
        switch result {
        case .success(let url): onEvent(id, .succeeded(url))
        case .failure(is CancellationError): onEvent(id, .cancelled)
        case .failure(let error): onEvent(id, .failed(error))
        }
        pump()
    }

    private static func execute(
        _ job: Job, reserver: OutputPathReserver, progress: @escaping (Double) -> Void
    ) async -> Result<URL, Error> {
        let first = job.inputs[0]
        let fileExtension = job.target.fileExtension
        let base = baseName(of: first)
        let directory = job.outputDirectory ?? first.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(error)
        }
        let finalURL = await reserver.reserve(
            fileName: fileExtension.isEmpty ? base : "\(base).\(fileExtension)",
            in: directory
        )
        let partialURL = partialURL(for: finalURL, fileExtension: fileExtension)
        do {
            try? FileManager.default.removeItem(at: partialURL)
            let request = ConversionRequest(inputs: job.inputs, target: job.target, preset: job.preset, outputURL: partialURL)
            try await job.converter.convert(request, progress: progress)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: partialURL, to: finalURL)
            await reserver.release(finalURL)
            return .success(finalURL)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            await reserver.release(finalURL)
            return .failure(Task.isCancelled ? CancellationError() : error)
        }
    }

    private static let compoundArchiveSuffixes = [".tar.gz", ".tar.bz2", ".tar.xz"]

    /// File name without extension; `x.tar.gz` gives `x`, not `x.tar`.
    static func baseName(of url: URL) -> String {
        let name = url.lastPathComponent
        if let suffix = compoundArchiveSuffixes.first(where: { name.lowercased().hasSuffix($0) }) {
            return String(name.dropLast(suffix.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Hidden, so an interrupted run never shows up in Finder. The real extension stays last
    /// because tools such as ffmpeg infer the format from it.
    static func partialURL(for finalURL: URL, fileExtension: String) -> URL {
        let leaf = finalURL.lastPathComponent
        let stem = fileExtension.isEmpty ? leaf : String(leaf.dropLast(fileExtension.count + 1))
        let name = fileExtension.isEmpty ? ".\(stem).xmac-partial" : ".\(stem).xmac-partial.\(fileExtension)"
        return finalURL.deletingLastPathComponent().appendingPathComponent(name)
    }
}
