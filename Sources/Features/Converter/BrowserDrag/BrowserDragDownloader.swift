import Foundation

enum BrowserDragError: Error, Equatable, LocalizedError {
    case unreachable(String)
    case badStatus(Int)
    case tooLarge
    case unsupportedRedirect
    case nothingReceived
    case insecureLink

    var errorDescription: String? {
        switch self {
        case .unreachable(let reason): return reason
        case .badStatus(let code): return L10n.format("Máy chủ trả về lỗi %d", code)
        case .tooLarge: return L10n.text("Tệp lớn hơn 2 GB")
        case .unsupportedRedirect: return L10n.text("Liên kết chuyển hướng sang địa chỉ không hợp lệ")
        case .nothingReceived: return L10n.text("Trình duyệt không cung cấp tệp nào")
        case .insecureLink: return L10n.text("Chỉ hỗ trợ liên kết https")
        }
    }
}

/// Downloads one https URL anonymously: no cookies, no credentials, no cache, capped size.
final class BrowserDragDownloader: NSObject, URLSessionDownloadDelegate {
    static let defaultMaxBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let timeout: TimeInterval = 60

    struct Result {
        let response: HTTPURLResponse
        let file: URL
    }

    private let maxBytes: Int64
    private let configuration: URLSessionConfiguration
    private let staging: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result, Error>?
    private var failure: BrowserDragError?
    private var staged: URL?
    private var task: URLSessionDownloadTask?

    /// `configuration` lets tests install a stub protocol; the anonymous settings are always applied.
    init(staging: URL, maxBytes: Int64 = defaultMaxBytes, configuration: URLSessionConfiguration = .ephemeral) {
        self.staging = staging
        self.maxBytes = maxBytes
        self.configuration = configuration
        super.init()
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = 3600
    }

    func download(_ url: URL) async throws -> Result {
        guard url.scheme?.lowercased() == "https" else { throw BrowserDragError.insecureLink }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let task = session.downloadTask(with: url)
                self.task = task
                lock.unlock()
                task.resume()
                if Task.isCancelled { task.cancel() }
            }
        } onCancel: {
            lock.lock()
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }

    private func fail(_ error: BrowserDragError, cancelling task: URLSessionTask) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
        task.cancel()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if request.url?.scheme?.lowercased() == "https" {
            completionHandler(request)
        } else {
            fail(.unsupportedRedirect, cancelling: task)
            completionHandler(nil)
        }
    }

    /// Fully anonymous: only the server's certificate check proceeds; Basic/Digest/NTLM/client-cert challenges are refused.
    static func disposition(forChallengeMethod method: String) -> URLSession.AuthChallengeDisposition {
        method == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(Self.disposition(forChallengeMethod: challenge.protectionSpace.authenticationMethod), nil)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            fail(.badStatus(http.statusCode), cancelling: downloadTask)
        } else if totalBytesWritten > maxBytes || totalBytesExpectedToWrite > maxBytes {
            fail(.tooLarge, cancelling: downloadTask)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let destination = staging.appendingPathComponent(".xmac-fetch-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            lock.lock()
            staged = destination
            lock.unlock()
        } catch {
            lock.lock()
            if failure == nil { failure = .unreachable(error.localizedDescription) }
            lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let failure = self.failure
        let file = staged
        lock.unlock()
        guard let continuation else { return }
        if let failure {
            file.map { try? FileManager.default.removeItem(at: $0) }
            continuation.resume(throwing: failure)
        } else if let error {
            continuation.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : BrowserDragError.unreachable(error.localizedDescription))
        } else if let file, let http = task.response as? HTTPURLResponse {
            if (200..<300).contains(http.statusCode) {
                continuation.resume(returning: Result(response: http, file: file))
            } else {
                try? FileManager.default.removeItem(at: file)
                continuation.resume(throwing: BrowserDragError.badStatus(http.statusCode))
            }
        } else {
            continuation.resume(throwing: BrowserDragError.nothingReceived)
        }
    }
}
