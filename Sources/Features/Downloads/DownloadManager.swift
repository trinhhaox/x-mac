import AppKit
import Foundation
import UserNotifications

public enum ManagedDownloadStatus: String, Codable {
    case downloading
    case waitingForNetwork
    case paused
    case completed
    case failed
    case cancelled
}

public struct ManagedDownload: Identifiable, Codable, Equatable {
    public let id: UUID
    public let sourceURL: String
    public var fileName: String
    public var destinationDirectory: String
    public var destinationPath: String?
    public var receivedBytes: Int64
    public var expectedBytes: Int64
    public var status: ManagedDownloadStatus
    public var errorMessage: String?
    public let createdAt: Date

    public var progress: Double {
        guard expectedBytes > 0 else { return 0 }
        return min(max(Double(receivedBytes) / Double(expectedBytes), 0), 1)
    }
}

public final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = DownloadManager()

    @Published public private(set) var items: [ManagedDownload] = []

    private static let historyKey = "Xmac.ManagedDownloads.v1"
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var taskItems: [Int: UUID] = [:]
    private var resumeData: [UUID: Data] = [:]
    private let environment: DownloadEnvironment
    private let defaults: UserDefaults
    private let configuration: URLSessionConfiguration
    private let notificationsEnabled: Bool
    private var networkRetries: [UUID: Int] = [:]
    private var pendingPauses = Set<UUID>()

    private lazy var session: URLSession = {
        let configuration = self.configuration
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24

        let queue = OperationQueue()
        queue.name = "com.xmac.downloads.delegate"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    init(defaults: UserDefaults = .standard, environment: DownloadEnvironment = .shared,
         configuration: URLSessionConfiguration = .default, notificationsEnabled: Bool = true) {
        self.defaults = defaults
        self.environment = environment
        self.configuration = configuration
        self.notificationsEnabled = notificationsEnabled
        super.init()
        restoreHistory()
        environment.onChange = { [weak self] in self?.networkChanged() }
    }

    public var activeCount: Int {
        items.filter { $0.status == .downloading }.count
    }

    public var defaultDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    @discardableResult
    public func enqueue(rawLinks: String, directory: URL? = nil) -> [String] {
        let lines = rawLinks
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var rejected: [String] = []
        var accepted = Set<String>()
        let saveDirectory = directory ?? defaultDirectory

        for line in lines.prefix(20) {
            guard accepted.insert(line).inserted else { continue }
            guard let url = Self.validHTTPURL(from: line) else {
                rejected.append(line)
                continue
            }
            startNewDownload(url: url, directory: saveDirectory)
        }

        if lines.count > 20 {
            rejected.append(L10n.text("Chỉ có thể thêm tối đa 20 liên kết mỗi lần."))
        }
        return rejected
    }

    public func pause(_ id: UUID) {
        guard let current = item(id), current.status == .downloading || current.status == .waitingForNetwork else { return }
        guard let task = tasks[id] else {
            update(id) { $0.status = .paused; $0.errorMessage = nil }
            persistHistory()
            return
        }
        pendingPauses.insert(id)
        update(id) { item in
            item.status = .paused
            item.errorMessage = nil
        }
        persistHistory()
        task.cancel { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, self.item(id)?.status == .paused { self.resumeData[id] = data }
                if self.tasks[id] === task { self.tasks.removeValue(forKey: id) }
                self.pendingPauses.remove(id)
            }
        }
    }

    public func resume(_ id: UUID, automatically: Bool = false) {
        guard let item = item(id),
              !pendingPauses.contains(id),
              item.status == .paused || item.status == .failed || item.status == .cancelled || item.status == .waitingForNetwork else { return }
        if !automatically { networkRetries[id] = 0 }
        guard environment.online, !(environment.avoidMetered && environment.metered) else {
            update(id) { $0.status = .waitingForNetwork; $0.errorMessage = L10n.text("Chờ kết nối phù hợp để tải xuống.") }
            persistHistory()
            return
        }
        if let task = tasks[id] {
            update(id) { $0.status = .downloading; $0.errorMessage = nil }
            task.resume()
            persistHistory()
            return
        }

        let task: URLSessionDownloadTask
        let savedResumeData = resumeData.removeValue(forKey: id)
        if let data = savedResumeData {
            task = session.downloadTask(withResumeData: data)
        } else if let url = Self.validHTTPURL(from: item.sourceURL) {
            task = session.downloadTask(with: url)
        } else {
            update(id) { download in
                download.status = .failed
                download.errorMessage = L10n.text("Liên kết tải xuống không còn hợp lệ.")
            }
            return
        }

        register(task, for: id)
        update(id) { download in
            download.status = .downloading
            download.errorMessage = nil
            if savedResumeData == nil {
                download.receivedBytes = 0
                download.expectedBytes = 0
            }
        }
        persistHistory()
        task.resume()
    }

    public func cancel(_ id: UUID) {
        networkRetries.removeValue(forKey: id)
        tasks.removeValue(forKey: id)?.cancel()
        resumeData.removeValue(forKey: id)
        update(id) { item in
            item.status = .cancelled
            item.errorMessage = nil
        }
        persistHistory()
    }

    public func remove(_ id: UUID) {
        networkRetries.removeValue(forKey: id)
        tasks.removeValue(forKey: id)?.cancel()
        resumeData.removeValue(forKey: id)
        items.removeAll { $0.id == id }
        taskItems = taskItems.filter { $0.value != id }
        persistHistory()
    }

    public func clearFinished() {
        let removable = Set(items.filter { $0.status != .downloading && $0.status != .paused && $0.status != .waitingForNetwork }.map(\.id))
        items.removeAll { removable.contains($0.id) }
        for id in removable { resumeData.removeValue(forKey: id); networkRetries.removeValue(forKey: id) }
        persistHistory()
    }

    public func reveal(_ id: UUID) {
        guard let path = item(id)?.destinationPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    public static func validHTTPURL(from text: String) -> URL? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            return nil
        }
        return url
    }

    public static func sanitizedFileName(_ proposed: String, fallback: String = "download") -> String {
        let lastComponent = URL(fileURLWithPath: proposed).lastPathComponent
        let forbidden = CharacterSet(charactersIn: "/:\0")
        let cleaned = lastComponent
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? fallback : cleaned
    }

    public static func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let manager = FileManager.default
        let safeName = sanitizedFileName(fileName)
        let initial = directory.appendingPathComponent(safeName, isDirectory: false)
        guard manager.fileExists(atPath: initial.path) else { return initial }

        let extensionName = initial.pathExtension
        let stem = initial.deletingPathExtension().lastPathComponent
        var suffix = 1
        while true {
            let candidateName = extensionName.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(extensionName)"
            let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }

    private func startNewDownload(url: URL, directory: URL) {
        let id = UUID()
        let fallbackName = "download-\(id.uuidString.prefix(8))"
        let name = Self.sanitizedFileName(url.lastPathComponent, fallback: fallbackName)
        let item = ManagedDownload(
            id: id,
            sourceURL: url.absoluteString,
            fileName: name,
            destinationDirectory: directory.path,
            destinationPath: nil,
            receivedBytes: 0,
            expectedBytes: 0,
            status: .downloading,
            errorMessage: nil,
            createdAt: Date()
        )
        items.insert(item, at: 0)

        let task = session.downloadTask(with: url)
        register(task, for: id)
        persistHistory()
        if environment.online && !(environment.avoidMetered && environment.metered) {
            task.resume()
        } else {
            update(id) { $0.status = .waitingForNetwork; $0.errorMessage = L10n.text("Chờ kết nối phù hợp để tải xuống.") }
            persistHistory()
        }
    }

    private func register(_ task: URLSessionDownloadTask, for id: UUID) {
        tasks[id] = task
        taskItems[task.taskIdentifier] = id
    }

    private func item(_ id: UUID) -> ManagedDownload? {
        items.first { $0.id == id }
    }

    private func update(_ id: UUID, mutate: (inout ManagedDownload) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    private func restoreHistory() {
        guard let data = defaults.data(forKey: Self.historyKey),
              var restored = try? JSONDecoder().decode([ManagedDownload].self, from: data) else {
            return
        }
        for index in restored.indices where restored[index].status == .downloading || restored[index].status == .waitingForNetwork {
            restored[index].status = .paused
            restored[index].errorMessage = L10n.text("Phiên tải trước đã dừng. Tiếp tục để tải lại.")
        }
        items = restored
    }

    private func persistHistory() {
        environment.setRunning(items.contains { $0.status == .downloading })
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }

    private func networkChanged() {
        let allowed = environment.online && !(environment.avoidMetered && environment.metered)
        for item in items {
            if !allowed && item.status == .downloading {
                tasks[item.id]?.suspend()
                update(item.id) { $0.status = .waitingForNetwork; $0.errorMessage = L10n.text("Chờ kết nối phù hợp để tải xuống.") }
            } else if allowed && item.status == .waitingForNetwork {
                resume(item.id, automatically: true)
            }
        }
        persistHistory()
    }

    static func isRecoverableNetworkError(_ error: NSError) -> Bool {
        error.domain == NSURLErrorDomain && [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
            NSURLErrorCannotFindHost
        ].contains(error.code)
    }

    private func notify(title: String, body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func shutdown() {
        for item in items where item.status == .downloading || item.status == .waitingForNetwork {
            update(item.id) { $0.status = .paused; $0.errorMessage = L10n.text("Phiên tải đã dừng. Tiếp tục để tải lại.") }
        }
        taskItems.removeAll()
        tasks.removeAll()
        session.invalidateAndCancel()
        environment.onChange = nil
        persistHistory()
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        DispatchQueue.main.async {
            guard let id = self.taskItems[downloadTask.taskIdentifier] else { return }
            guard self.tasks[id] === downloadTask else { return }
            guard let status = self.item(id)?.status, status == .downloading || status == .waitingForNetwork else { return }
            self.update(id) { item in
                if item.status == .waitingForNetwork { item.status = .downloading; item.errorMessage = nil }
                item.receivedBytes = totalBytesWritten
                item.expectedBytes = max(totalBytesExpectedToWrite, 0)
            }
            self.environment.setRunning(self.items.contains { $0.status == .downloading })
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        var context: (id: UUID, item: ManagedDownload)?
        DispatchQueue.main.sync {
            if let id = self.taskItems[downloadTask.taskIdentifier], self.tasks[id] === downloadTask,
               let item = self.item(id), item.status == .downloading || item.status == .waitingForNetwork {
                context = (id, item)
            }
        }
        guard let context else { return }

        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            DispatchQueue.main.async {
                self.update(context.id) { item in
                    item.status = .failed
                    item.errorMessage = L10n.format("Máy chủ phản hồi HTTP %lld.", Int64(response.statusCode))
                }
                self.tasks.removeValue(forKey: context.id)
                self.persistHistory()
                self.notify(title: L10n.text("Tải xuống thất bại"), body: context.item.fileName)
            }
            return
        }

        let suggested = downloadTask.response?.suggestedFilename ?? context.item.fileName
        let safeName = Self.sanitizedFileName(suggested, fallback: context.item.fileName)
        let directory = URL(fileURLWithPath: context.item.destinationDirectory, isDirectory: true)
        let destination = Self.uniqueDestination(for: safeName, in: directory)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destination)
            DispatchQueue.main.async {
                self.update(context.id) { item in
                    item.fileName = destination.lastPathComponent
                    item.destinationPath = destination.path
                    item.receivedBytes = max(item.receivedBytes, item.expectedBytes)
                    item.status = .completed
                    item.errorMessage = nil
                }
                self.tasks.removeValue(forKey: context.id)
                self.persistHistory()
                self.notify(title: L10n.text("Tải xuống hoàn tất"), body: destination.lastPathComponent)
            }
        } catch {
            DispatchQueue.main.async {
                self.update(context.id) { item in
                    item.status = .failed
                    item.errorMessage = error.localizedDescription
                }
                self.tasks.removeValue(forKey: context.id)
                self.persistHistory()
                self.notify(title: L10n.text("Tải xuống thất bại"), body: context.item.fileName)
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        DispatchQueue.main.async {
            guard let id = self.taskItems.removeValue(forKey: task.taskIdentifier) else { return }
            guard self.tasks[id] === task else { return }
            self.tasks.removeValue(forKey: id)
            guard let error, let current = self.item(id), current.status == .downloading || current.status == .waitingForNetwork else {
                self.persistHistory()
                return
            }

            let failure = error as NSError
            let attempts = self.networkRetries[id, default: 0]
            if Self.isRecoverableNetworkError(failure), attempts < 3 {
                self.networkRetries[id] = attempts + 1
                if let data = failure.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    self.resumeData[id] = data
                }
                self.update(id) { $0.status = .waitingForNetwork; $0.errorMessage = L10n.text("Chờ kết nối; sẽ tự thử lại khi có mạng.") }
                self.persistHistory()
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(1 << attempts)) {
                    if self.item(id)?.status == .waitingForNetwork { self.resume(id, automatically: true) }
                }
                return
            }

            self.update(id) { item in
                item.status = .failed
                item.errorMessage = error.localizedDescription
            }
            self.persistHistory()
            self.notify(title: L10n.text("Tải xuống thất bại"), body: current.fileName)
        }
    }

    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        DispatchQueue.main.async {
            guard let id = self.taskItems[task.taskIdentifier], self.tasks[id] === task,
                  self.item(id)?.status == .downloading else { return }
            self.update(id) { $0.status = .waitingForNetwork; $0.errorMessage = L10n.text("Chờ kết nối mạng.") }
            self.persistHistory()
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
              Self.validHTTPURL(from: redirectedURL.absoluteString) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
