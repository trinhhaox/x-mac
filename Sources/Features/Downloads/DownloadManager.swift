import AppKit
import Foundation
import UserNotifications

public enum ManagedDownloadStatus: String, Codable {
    case downloading
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

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24

        let queue = OperationQueue()
        queue.name = "com.xmac.downloads.delegate"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    private override init() {
        super.init()
        restoreHistory()
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
            rejected.append("Chỉ có thể thêm tối đa 20 liên kết mỗi lần.")
        }
        return rejected
    }

    public func pause(_ id: UUID) {
        guard let task = tasks[id] else { return }
        update(id) { item in
            item.status = .paused
            item.errorMessage = nil
        }
        persistHistory()
        task.cancel { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data { self.resumeData[id] = data }
                self.tasks.removeValue(forKey: id)
            }
        }
    }

    public func resume(_ id: UUID) {
        guard let item = item(id),
              item.status == .paused || item.status == .failed || item.status == .cancelled else { return }

        let task: URLSessionDownloadTask
        let savedResumeData = resumeData.removeValue(forKey: id)
        if let data = savedResumeData {
            task = session.downloadTask(withResumeData: data)
        } else if let url = Self.validHTTPURL(from: item.sourceURL) {
            task = session.downloadTask(with: url)
        } else {
            update(id) { download in
                download.status = .failed
                download.errorMessage = "Liên kết tải xuống không còn hợp lệ."
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
        tasks.removeValue(forKey: id)?.cancel()
        resumeData.removeValue(forKey: id)
        update(id) { item in
            item.status = .cancelled
            item.errorMessage = nil
        }
        persistHistory()
    }

    public func remove(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        resumeData.removeValue(forKey: id)
        items.removeAll { $0.id == id }
        taskItems = taskItems.filter { $0.value != id }
        persistHistory()
    }

    public func clearFinished() {
        let removable = Set(items.filter { $0.status != .downloading && $0.status != .paused }.map(\.id))
        items.removeAll { removable.contains($0.id) }
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
        task.resume()
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
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              var restored = try? JSONDecoder().decode([ManagedDownload].self, from: data) else {
            return
        }
        for index in restored.indices where restored[index].status == .downloading {
            restored[index].status = .paused
            restored[index].errorMessage = "Phiên tải trước đã dừng. Tiếp tục để tải lại."
        }
        items = restored
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.historyKey)
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
            self.update(id) { item in
                item.receivedBytes = totalBytesWritten
                item.expectedBytes = max(totalBytesExpectedToWrite, 0)
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        var context: (id: UUID, item: ManagedDownload)?
        DispatchQueue.main.sync {
            if let id = self.taskItems[downloadTask.taskIdentifier], let item = self.item(id) {
                context = (id, item)
            }
        }
        guard let context else { return }

        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            DispatchQueue.main.async {
                self.update(context.id) { item in
                    item.status = .failed
                    item.errorMessage = "Máy chủ phản hồi HTTP \(response.statusCode)."
                }
                self.tasks.removeValue(forKey: context.id)
                self.persistHistory()
                self.notify(title: "Tải xuống thất bại", body: context.item.fileName)
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
                self.notify(title: "Tải xuống hoàn tất", body: destination.lastPathComponent)
            }
        } catch {
            DispatchQueue.main.async {
                self.update(context.id) { item in
                    item.status = .failed
                    item.errorMessage = error.localizedDescription
                }
                self.tasks.removeValue(forKey: context.id)
                self.persistHistory()
                self.notify(title: "Tải xuống thất bại", body: context.item.fileName)
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
            self.tasks.removeValue(forKey: id)
            guard let error, let current = self.item(id), current.status == .downloading else { return }

            self.update(id) { item in
                item.status = .failed
                item.errorMessage = error.localizedDescription
            }
            self.persistHistory()
            self.notify(title: "Tải xuống thất bại", body: current.fileName)
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
