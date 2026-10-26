import AppKit
import UniformTypeIdentifiers

/// Turns a dropped browser payload into local files inside `directory`. Never opens or runs what it fetches.
/// Everything fetched is quarantined like a browser download.
struct BrowserDragFetcher {
    private static let nameAttempts = 5

    var configuration: URLSessionConfiguration = .ephemeral
    var maxBytes: Int64 = BrowserDragDownloader.defaultMaxBytes
    /// Seam for tests: picks the file name inside a directory (production: first free name).
    var pickDestination: (String, URL) -> URL = DownloadManager.uniqueDestination(for:in:)

    /// `staging` holds partial downloads until they are complete; defaults to `directory`.
    func fetch(_ payload: BrowserDragPayload, into directory: URL, staging: URL? = nil) async throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = staging ?? directory
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        switch payload {
        case .files(let urls): return urls
        case .promise(let delivery):
            guard delivery.destination != nil else { throw BrowserDragError.nothingReceived }
            return try place(await delivery.files(), into: directory)
        case .imageData(let data, let type, let name): return [try write(data, type: type, name: name, into: directory)]
        case .remote(let url, let name): return [try await download(url, name: name, into: directory, staging: staging)]
        }
    }

    private func write(_ data: Data, type: UTType, name: String?, into directory: URL) throws -> URL {
        guard Int64(data.count) <= maxBytes else { throw BrowserDragError.tooLarge }
        let base = BrowserDragNaming.safeName(name ?? "image", fallback: "image")
        let named = BrowserDragNaming.withExtension(base, mime: type.preferredMIMEType)
        return try claim(named, in: directory, source: nil) { try data.write(to: $0, options: .withoutOverwriting) }
    }

    private func download(_ url: URL, name: String?, into directory: URL, staging: URL) async throws -> URL {
        let downloader = BrowserDragDownloader(staging: staging, maxBytes: maxBytes, configuration: configuration)
        let result = try await downloader.download(url)
        do {
            try Task.checkCancellation()
            let final = BrowserDragNaming.finalName(
                contentDisposition: result.response.value(forHTTPHeaderField: "Content-Disposition"),
                suggested: name, url: result.response.url ?? url, mime: result.response.mimeType
            )
            return try claim(final, in: directory, source: url) { try FileManager.default.moveItem(at: result.file, to: $0) }
        } catch {
            try? FileManager.default.removeItem(at: result.file)
            throw error
        }
    }

    /// Promised files are renamed through the same naming rules and moved out of the delivery folder.
    private func place(_ delivered: [URL], into directory: URL) throws -> [URL] {
        try delivered.map { file in
            let name = BrowserDragNaming.withExtension(BrowserDragNaming.safeName(file.lastPathComponent), mime: nil)
            return try claim(name, in: directory, source: nil) { try FileManager.default.moveItem(at: file, to: $0) }
        }
    }

    /// Materializes a file under a free name, retrying with a new name if another writer took it first.
    private func claim(_ name: String, in directory: URL, source: URL?, _ materialize: (URL) throws -> Void) throws -> URL {
        var lastError: Error = BrowserDragError.nothingReceived
        for _ in 0..<Self.nameAttempts {
            let destination = pickDestination(name, directory)
            do {
                try materialize(destination)
                DownloadManager.markAsDownloadedFromInternet(destination, sourceURL: source?.absoluteString)
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                lastError = error
            }
        }
        throw lastError
    }
}
