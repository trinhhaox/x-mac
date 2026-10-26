import Foundation

/// Runs `xmac convert` through ConversionQueue directly (no MainActor UI state).
struct ConverterCLIJobRunner {
    private struct Job {
        let id = UUID()
        let inputs: [URL]
        let target: ConversionTarget
    }

    let registry: ConverterRegistry
    var defaults: UserDefaults = .standard

    func convert(_ options: ConverterCLIConvertOptions) async -> Int32 {
        ConverterCLIJournalSweeper.sweep(in: FileManager.default.temporaryDirectory)
        let files = options.files.map { URL(fileURLWithPath: $0) }
        var failures = 0
        var runnable: [URL] = []
        for file in files {
            if FileManager.default.fileExists(atPath: file.path) { runnable.append(file) } else {
                ConverterCLI.fail("no such file: \(file.path)")
                failures += 1
            }
        }
        let saved = await savedPresets()
        let jobs: [Job]
        let presets: [ConversionGroup: ConversionPreset]
        do {
            (jobs, failures) = try plan(runnable, spec: options.target, failures: failures)
            presets = try Dictionary(uniqueKeysWithValues: Set(jobs.map(\.target.group)).map {
                ($0, try options.applying(to: saved[$0.rawValue] ?? ConversionPreset()))
            })
        } catch let error as ConverterCLIUsageError {
            ConverterCLI.fail(error.message)
            return ConverterCLIExit.usage
        } catch {
            ConverterCLI.fail("\(error)")
            return ConverterCLIExit.usage
        }
        if jobs.isEmpty { return failures == 0 ? ConverterCLIExit.usage : ConverterCLIExit.someFailed }
        let failed = await run(jobs, presets: presets, outputDirectory: options.outputDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }, quiet: options.quiet)
        return failures + failed == 0 ? ConverterCLIExit.success : ConverterCLIExit.someFailed
    }

    /// A merge-style target takes every file in one job; anything else resolves per file.
    private func plan(_ files: [URL], spec: String, failures: Int) throws -> ([Job], Int) {
        guard !files.isEmpty else { return ([], failures) }
        if files.count > 1, let shared = try? ConverterCLITargetResolver.resolve(spec, among: registry.targets(for: files)),
           shared.combinesInputs {
            return ([Job(inputs: files, target: shared)], failures)
        }
        var jobs: [Job] = []
        var failures = failures
        var errors: [ConverterCLIUsageError] = []
        for file in files {
            do {
                jobs.append(Job(inputs: [file], target: try ConverterCLITargetResolver.resolve(spec, among: registry.targets(for: [file]))))
            } catch let error as ConverterCLIUsageError {
                errors.append(error)
                failures += 1
            }
        }
        if jobs.isEmpty, let first = errors.first { throw first }
        errors.forEach { ConverterCLI.fail($0.message) }
        return (jobs, failures)
    }

    /// Per-group presets saved by the app; empty when none or unreadable.
    private func savedPresets() async -> [String: ConversionPreset] {
        let key = await MainActor.run { ConverterManager.presetsKey }
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: ConversionPreset].self, from: data)) ?? [:]
    }

    /// Returns the number of failed or cancelled jobs.
    private func run(
        _ jobs: [Job], presets: [ConversionGroup: ConversionPreset], outputDirectory: URL?, quiet: Bool
    ) async -> Int {
        var continuation: AsyncStream<(UUID, ConversionJobEvent)>.Continuation?
        let events = AsyncStream<(UUID, ConversionJobEvent)> { continuation = $0 }
        guard let continuation else { return jobs.count }
        // A per-process journal: the app's launch sweep must never treat a running CLI job's
        // partial file as stale (the shared journal file is not locked across processes).
        let journalURL = ConverterCLIJournalSweeper.journalURL(
            pid: ProcessInfo.processInfo.processIdentifier, in: FileManager.default.temporaryDirectory)
        let queue = ConversionQueue(registry: registry, journal: PartialFileJournal(storeURL: journalURL)) { id, event in
            continuation.yield((id, event))
        }
        let signalSources = Self.installInterruptHandlers(queue: queue)
        defer {
            signalSources.forEach { $0.cancel() }
            try? FileManager.default.removeItem(at: journalURL)
        }
        let names = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0.inputs[0].lastPathComponent) })
        for job in jobs {
            await queue.enqueue(
                id: job.id, inputs: job.inputs, target: job.target,
                preset: presets[job.target.group] ?? ConversionPreset(), outputDirectory: outputDirectory
            )
        }
        var remaining = jobs.count
        var failed = 0
        var lastQuarter: [UUID: Int] = [:]
        for await (id, event) in events {
            let name = names[id] ?? ""
            switch event {
            case .started:
                if !quiet { log("\(name): converting") }
            case .progress(let value):
                let quarter = Int(value * 4)
                if !quiet, quarter > (lastQuarter[id] ?? 0), quarter < 4 {
                    lastQuarter[id] = quarter
                    log("\(name): \(quarter * 25)%")
                }
            case .succeeded(let url):
                print(url.path)
                remaining -= 1
            case .failed(let error):
                ConverterCLI.fail("\(name): \(Self.describe(error))")
                failed += 1
                remaining -= 1
            case .cancelled:
                ConverterCLI.fail("\(name): cancelled")
                failed += 1
                remaining -= 1
            }
            if remaining == 0 { break }
        }
        return failed
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case ConversionError.toolMissing(let tool): return "requires \(tool.rawValue), which is not installed"
        case ConversionError.unsupportedInput(let detail): return "unsupported input (\(detail))"
        case ConversionError.failed(let detail): return detail
        default: return error.localizedDescription
        }
    }

    /// SIGINT/SIGTERM/SIGHUP: stop queued jobs, kill child processes, give partial files a moment
    /// to be removed, then exit 128 + signal number (130, 143, 129).
    private static func installInterruptHandlers(queue: ConversionQueue) -> [DispatchSourceSignal] {
        [SIGINT, SIGTERM, SIGHUP].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                Task {
                    await queue.cancelAll()
                    ProcessRunner.terminateAll()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    exit(128 + number)
                }
            }
            source.resume()
            return source
        }
    }
}
