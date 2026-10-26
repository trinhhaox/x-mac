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
    static let legacyPresetKey = "Converter.Preset.v1"
    static let presetsKey = "Converter.Presets.v2"
    static let notifyKey = "Converter.NotifyOnFinish"
    static let recentLimit = 20

    @Published public private(set) var jobs: [ConversionJob] = []
    @Published public private(set) var recent: [RecentConversion]
    /// Per-group settings, keyed by `ConversionGroup.rawValue` (a String key keeps the JSON a plain object).
    @Published private var presets: [String: ConversionPreset] {
        didSet { persist(presets, key: Self.presetsKey) }
    }
    /// Pending crops (normalized rects) for the current selection, keyed by standardized input URL. Not persisted.
    @Published public private(set) var cropRects: [URL: CGRect] = [:]

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
        presets = Self.loadPresets(from: defaults)
    }

    public func preset(for group: ConversionGroup) -> ConversionPreset {
        presets[group.rawValue] ?? ConversionPreset()
    }

    public func updatePreset(for group: ConversionGroup, _ change: (inout ConversionPreset) -> Void) {
        var value = preset(for: group)
        change(&value)
        presets[group.rawValue] = value
    }

    /// The PDF-group preset; only the page-range field edits it (`pdfPageRange` is per-selection UI state).
    public var preset: ConversionPreset {
        get { preset(for: .pdf) }
        set { presets[ConversionGroup.pdf.rawValue] = newValue }
    }

    public func setCrop(_ rect: CGRect?, for input: URL) {
        cropRects[input.standardizedFileURL] = rect
    }

    public func clearCrops() {
        if !cropRects.isEmpty { cropRects = [:] }
    }

    public var notifyOnFinish: Bool {
        get { defaults.object(forKey: Self.notifyKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.notifyKey) }
    }

    /// One job per input, or a single job when the target combines inputs. Returns the new job ids.
    /// `disposeInputs` deletes the inputs (only if they are browser-drop scratch copies) once each job ends.
    /// `crops` is explicit (standardized input URL to rect): only the converter UI passes it.
    @discardableResult
    public func enqueue(
        inputs: [URL], target: ConversionTarget, outputDirectory: URL? = nil, disposeInputs: Bool = false,
        crops: [URL: CGRect] = [:]
    ) -> [UUID] {
        guard !inputs.isEmpty else { return [] }
        let groups = target.combinesInputs ? [inputs] : inputs.map { [$0] }
        let batch = UUID()
        let newJobs = groups.map { ConversionJob(id: UUID(), inputs: $0, target: target, state: .queued) }
        jobsOfBatch[batch] = newJobs.map(\.id)
        newJobs.forEach { batchOfJob[$0.id] = batch }
        if disposeInputs { disposableJobs.formUnion(newJobs.map(\.id)) }
        jobs.append(contentsOf: newJobs)
        let presets = newJobs.map { jobPreset(for: $0, crops: crops) }
        // Forwarded in order so a cancel can never overtake the enqueue it refers to.
        forward { queue in
            for (job, preset) in zip(newJobs, presets) {
                await queue.enqueue(
                    id: job.id, inputs: job.inputs, target: job.target, preset: preset, outputDirectory: outputDirectory
                )
            }
        }
        return newJobs.map(\.id)
    }

    /// The settings section a group reads: OCR (document) renders PDF pages, so it shares the PDF tab;
    /// groups without a tab of their own (office, archive, subtitle, ...) use the image defaults.
    static func settingsGroup(for group: ConversionGroup) -> ConversionGroup {
        switch group {
        case .pdf, .document: return .pdf
        case .media: return .media
        default: return .image
        }
    }

    /// The group's settings, plus the pending crop when the job converts one image to an image format.
    func jobPreset(for job: ConversionJob, crops: [URL: CGRect]) -> ConversionPreset {
        var value = preset(for: Self.settingsGroup(for: job.target.group))
        if job.target.group == .image, !job.target.combinesInputs, let input = job.inputs.first {
            value.cropRect = crops[input.standardizedFileURL]
        }
        return value
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

    /// v2 if present; otherwise the old single preset becomes every group's starting point.
    private static func loadPresets(from defaults: UserDefaults) -> [String: ConversionPreset] {
        if let saved = load([String: ConversionPreset].self, key: presetsKey, from: defaults) { return saved }
        let legacy = load(ConversionPreset.self, key: legacyPresetKey, from: defaults) ?? ConversionPreset()
        return Dictionary(uniqueKeysWithValues: ConversionGroup.allCases.map { ($0.rawValue, legacy) })
    }

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
