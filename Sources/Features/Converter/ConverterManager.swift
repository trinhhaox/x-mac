import Foundation
import UserNotifications

public enum ConversionJobState: Equatable {
    case queued
    case running(Double)
    case done(URL)
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .queued, .running: return false
        default: return true
        }
    }
}

public struct ConversionJob: Identifiable, Equatable {
    public let id: UUID
    public let inputs: [URL]
    public let target: ConversionTarget
    public var state: ConversionJobState

    public static func == (lhs: ConversionJob, rhs: ConversionJob) -> Bool {
        lhs.id == rhs.id && lhs.state == rhs.state
    }
}

public struct RecentConversion: Codable, Identifiable, Equatable {
    public let id: UUID
    public let inputName: String
    public let outputPath: String
    public let targetTitle: String
    public let date: Date
}

/// UI-free state for the converter: job list, recent results, preset, and the end-of-batch alert.
@MainActor
public final class ConverterManager: ObservableObject {
    public static let shared = ConverterManager()

    static let recentKey = "Converter.Recent.v1"
    static let presetKey = "Converter.Preset.v1"
    static let notifyKey = "Converter.NotifyOnFinish"
    static let recentLimit = 20

    @Published public private(set) var jobs: [ConversionJob] = []
    @Published public private(set) var recent: [RecentConversion]
    @Published public var preset: ConversionPreset {
        didSet { persist(preset, key: Self.presetKey) }
    }

    public let registry: ConverterRegistry
    private let defaults: UserDefaults
    private let notify: (_ title: String, _ paths: [String]) -> Void
    private let playSound: (SoundEffectManager.SoundType) -> Void
    private let rescueFolder: URL
    private var batchOfJob: [UUID: UUID] = [:]
    private var jobsOfBatch: [UUID: [UUID]] = [:]
    /// Jobs whose inputs are scratch copies of browser drops: deleted when the job ends, or moved to `rescueFolder` if it failed.
    private var disposableJobs: Set<UUID> = []
    /// Called on the main actor with every successfully produced output (file or folder).
    public var onOutputProduced: ((URL) -> Void)?
    private var queueCalls: Task<Void, Never>?
    private lazy var queue = ConversionQueue(registry: registry) { [weak self] id, event in
        Task { @MainActor in self?.handle(event, for: id) }
    }

    public init(
        registry: ConverterRegistry = .standard(),
        defaults: UserDefaults = .standard,
        notify: @escaping (_ title: String, _ paths: [String]) -> Void = ConverterManager.postNotification,
        playSound: @escaping (SoundEffectManager.SoundType) -> Void = { SoundEffectManager.shared.play($0) },
        rescueFolder: URL? = nil
    ) {
        self.rescueFolder = rescueFolder ?? BrowserDropCoordinator.userDownloads
        self.registry = registry
        self.defaults = defaults
        self.notify = notify
        self.playSound = playSound
        recent = Self.load([RecentConversion].self, key: Self.recentKey, from: defaults) ?? []
        preset = Self.load(ConversionPreset.self, key: Self.presetKey, from: defaults) ?? ConversionPreset()
    }

    public var notifyOnFinish: Bool {
        get { defaults.object(forKey: Self.notifyKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.notifyKey) }
    }

    /// One job per input, or a single job when the target combines inputs. Returns the new job ids.
    /// `disposeInputs` deletes the inputs (only if they are browser-drop scratch copies) once each job ends.
    @discardableResult
    public func enqueue(
        inputs: [URL], target: ConversionTarget, outputDirectory: URL? = nil, disposeInputs: Bool = false
    ) -> [UUID] {
        guard !inputs.isEmpty else { return [] }
        let groups = target.combinesInputs ? [inputs] : inputs.map { [$0] }
        let batch = UUID()
        let newJobs = groups.map { ConversionJob(id: UUID(), inputs: $0, target: target, state: .queued) }
        jobsOfBatch[batch] = newJobs.map(\.id)
        newJobs.forEach { batchOfJob[$0.id] = batch }
        if disposeInputs { disposableJobs.formUnion(newJobs.map(\.id)) }
        jobs.append(contentsOf: newJobs)
        let snapshot = preset
        // Forwarded in order so a cancel can never overtake the enqueue it refers to.
        forward { queue in
            for job in newJobs {
                await queue.enqueue(
                    id: job.id, inputs: job.inputs, target: job.target, preset: snapshot, outputDirectory: outputDirectory
                )
            }
        }
        return newJobs.map(\.id)
    }

    public func cancel(_ id: UUID) {
        forward { await $0.cancel(id) }
    }

    public func cancelAll() {
        forward { await $0.cancelAll() }
    }

    /// App quit: stop queued work and kill converter child processes (ffmpeg, soffice) so none are orphaned.
    public func shutdown() {
        cancelAll()
        ProcessRunner.terminateAll()
    }

    public func clearFinished() {
        jobs.removeAll { $0.state.isFinished }
    }

    private func forward(_ operation: @escaping (ConversionQueue) async -> Void) {
        let previous = queueCalls
        let queue = queue
        queueCalls = Task {
            await previous?.value
            await operation(queue)
        }
    }

    // MARK: Events

    private func handle(_ event: ConversionJobEvent, for id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        // Events hop threads and can arrive out of order; a finished job never changes again.
        guard !jobs[index].state.isFinished else { return }
        switch event {
        case .started: jobs[index].state = .running(0)
        case .progress(let value): jobs[index].state = .running(min(max(value, 0), 1))
        case .succeeded(let url):
            jobs[index].state = .done(url)
            record(jobs[index], output: url)
            onOutputProduced?(url)
        case .failed(let error): jobs[index].state = .failed(Self.message(for: error))
        case .cancelled: jobs[index].state = .cancelled
        }
        if jobs[index].state.isFinished {
            if disposableJobs.remove(id) != nil {
                if case .failed = jobs[index].state {
                    BrowserDropCoordinator.rescue(jobs[index].inputs, into: rescueFolder)
                } else {
                    BrowserDropCoordinator.dispose(jobs[index].inputs)
                }
            }
            batchProgressed(afterFinishing: id)
        }
    }

    private func record(_ job: ConversionJob, output: URL) {
        let entry = RecentConversion(
            id: job.id, inputName: job.inputs[0].lastPathComponent, outputPath: output.path,
            targetTitle: job.target.title, date: Date()
        )
        recent = Array(([entry] + recent).prefix(Self.recentLimit))
        persist(recent, key: Self.recentKey)
    }

    private func batchProgressed(afterFinishing id: UUID) {
        guard let batch = batchOfJob[id], let ids = jobsOfBatch[batch] else { return }
        let members = jobs.filter { ids.contains($0.id) }
        guard members.allSatisfy({ $0.state.isFinished }) else { return }
        jobsOfBatch[batch] = nil
        ids.forEach { batchOfJob[$0] = nil }
        let paths = members.compactMap { job -> String? in
            if case .done(let url) = job.state { return url.path }
            return nil
        }
        let failures = members.filter { if case .failed = $0.state { return true } else { return false } }.count
        guard !paths.isEmpty || failures > 0 else { return }
        playSound(paths.isEmpty ? .error : .done)
        guard notifyOnFinish else { return }
        let title = failures == 0
            ? L10n.format("Đã chuyển đổi %d tệp", paths.count)
            : L10n.format("Đã chuyển đổi %d tệp, lỗi %d tệp", paths.count, failures)
        notify(title, paths)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case ConversionError.unsupportedInput(let text), ConversionError.failed(let text): return text
        case ConversionError.toolMissing(let tool): return L10n.format("Thiếu công cụ %@", tool.rawValue)
        default: return error.localizedDescription
        }
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            NSLog("Converter: dropping unreadable \(key): \(error)")
            return nil
        }
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            NSLog("Converter: could not save \(key): \(error)")
        }
    }

    public nonisolated static func postNotification(title: String, paths: [String]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.categoryIdentifier = NotificationRouter.categoryIdentifier
        content.userInfo = ["paths": paths]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Converter: notification failed: \(error)") }
        }
    }
}
