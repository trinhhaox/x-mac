import Foundation

/// Where a file dragged out of a browser lands. Stored under `BrowserDropCoordinator.modeKey`.
enum BrowserDropMode: String, CaseIterable {
    /// Keep the fetched file in ~/Downloads and write the result next to it.
    case downloads
    /// Fetch into a scratch folder, write the result to ~/Downloads and delete the fetched file afterwards
    /// (a failed conversion moves it to ~/Downloads instead).
    case convertedOnly
}

/// Local inputs ready for the converter, plus where results go and whether the inputs are scratch copies.
struct BrowserDropInputs {
    let urls: [URL]
    var outputDirectory: URL?
    var disposable = false
    /// True when this feature created the files (as opposed to files the user already had).
    var created = false

    func merging(_ other: BrowserDropInputs) -> BrowserDropInputs {
        BrowserDropInputs(
            urls: urls + other.urls, outputDirectory: outputDirectory ?? other.outputDirectory,
            disposable: disposable && other.disposable, created: created && other.created
        )
    }
}

/// Fetches browser drops to disk for every drop target and reports failures.
@MainActor
final class BrowserDropCoordinator: ObservableObject {
    static let shared = BrowserDropCoordinator()
    static let modeKey = "Converter.BrowserDropMode"

    @Published private(set) var activeCount = 0

    private let defaults: UserDefaults
    private let fetcher: BrowserDragFetcher
    private let downloads: URL
    private let reportFailure: (String) -> Void
    private var tasks: [UUID: Task<BrowserDropInputs?, Never>] = [:]
    private var cancelGeneration = 0
    private var swept = false

    init(
        defaults: UserDefaults = .standard,
        fetcher: BrowserDragFetcher = BrowserDragFetcher(),
        downloads: URL = BrowserDropCoordinator.userDownloads,
        reportFailure: @escaping (String) -> Void = { ConverterManager.postNotification(title: $0, paths: []) }
    ) {
        self.defaults = defaults
        self.fetcher = fetcher
        self.downloads = downloads
        self.reportFailure = reportFailure
    }

    var mode: BrowserDropMode {
        get { defaults.string(forKey: Self.modeKey).flatMap(BrowserDropMode.init) ?? .downloads }
        set { defaults.set(newValue.rawValue, forKey: Self.modeKey) }
    }

    /// Requests file promises. Call synchronously from `performDragOperation`: the system only fulfils
    /// `receivePromisedFiles` while the drag is live. Other payloads need nothing here.
    func begin(_ payload: BrowserDragPayload) {
        guard case .promise(let delivery) = payload, delivery.destination == nil else { return }
        delivery.start(into: Self.newScratchFolder().appendingPathComponent(Self.incomingFolder, isDirectory: true))
    }

    /// Materializes the payloads (in order). Returns nil after reporting failures, or silently when cancelled.
    func fetch(_ payload: BrowserDragPayload) async -> BrowserDropInputs? { await fetch([payload]) }

    func fetch(_ payloads: [BrowserDragPayload]) async -> BrowserDropInputs? {
        sweepStaleOnce()
        let generation = cancelGeneration
        activeCount += 1
        defer { activeCount -= 1 }
        var merged: BrowserDropInputs?
        for payload in payloads where generation == cancelGeneration {
            guard let next = await fetchOne(payload) else { continue }
            merged = merged.map { $0.merging(next) } ?? next
        }
        return merged
    }

    /// Hands fetched inputs to `show` once something can convert them; otherwise deletes what this feature fetched and says so.
    func deliver(
        _ inputs: BrowserDropInputs, registry: ConverterRegistry? = nil,
        show: (BrowserDropInputs) -> Void
    ) {
        guard inputs.created, (registry ?? ConverterManager.shared.registry).targets(for: inputs.urls).isEmpty else { return show(inputs) }
        if inputs.disposable {
            Self.dispose(inputs.urls)
        } else {
            inputs.urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        reportFailure(L10n.text("Không có định dạng đích phù hợp cho các tệp này."))
    }

    func reportUnreadable() { reportFailure(L10n.text("Không đọc được nội dung đã thả")) }

    func cancelAll() {
        cancelGeneration += 1
        tasks.values.forEach { $0.cancel() }
    }

    private func fetchOne(_ payload: BrowserDragPayload) async -> BrowserDropInputs? {
        if case .files(let urls) = payload { return BrowserDropInputs(urls: urls) }
        let id = UUID()
        let task = Task { await run(payload) }
        tasks[id] = task
        defer { tasks[id] = nil }
        return await task.value
    }

    private func run(_ payload: BrowserDragPayload) async -> BrowserDropInputs? {
        var staging = Self.newScratchFolder().appendingPathComponent(Self.incomingFolder, isDirectory: true)
        if case .promise(let delivery) = payload, let started = delivery.destination { staging = started }
        let scratch = staging.deletingLastPathComponent()
        let convertedOnly = mode == .convertedOnly
        do {
            let urls = try await fetcher.fetch(payload, into: convertedOnly ? scratch : downloads, staging: staging)
            try? FileManager.default.removeItem(at: convertedOnly ? staging : scratch)
            return BrowserDropInputs(urls: urls, outputDirectory: convertedOnly ? downloads : nil, disposable: convertedOnly, created: true)
        } catch {
            try? FileManager.default.removeItem(at: scratch)
            if !(error is CancellationError) {
                NSLog("Converter: browser drop failed: \(error)")
                reportFailure(L10n.format("Không tải được tệp từ trình duyệt: %@", error.localizedDescription))
            }
            return nil
        }
    }

    private func sweepStaleOnce() {
        guard !swept else { return }
        swept = true
        Self.sweepStaleScratch()
    }
}
