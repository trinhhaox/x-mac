import AppKit
import UniformTypeIdentifiers

/// What a drag pasteboard offers, behind plain values so parsing needs no live NSPasteboard.
struct BrowserDragSnapshot {
    var fileURLs: [URL] = []
    var promiseReceivers: [NSFilePromiseReceiver] = []
    var types: [String] = []
    var read: (String) -> Data? = { _ in nil }

    var hasImage: Bool { BrowserDragPayload.imageTypes.contains { types.contains($0.identifier) } }

    init(fileURLs: [URL] = [], promiseReceivers: [NSFilePromiseReceiver] = [], values: [String: Data] = [:]) {
        self.fileURLs = fileURLs
        self.promiseReceivers = promiseReceivers
        types = Array(values.keys)
        read = { values[$0] }
    }

    init(pasteboard: NSPasteboard) {
        fileURLs = ConverterServiceProvider.fileURLs(from: pasteboard)
        promiseReceivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        types = pasteboard.types?.map(\.rawValue) ?? []
        read = { pasteboard.data(forType: NSPasteboard.PasteboardType($0)) }
    }
}

/// What a drop from Finder or a web browser carries. Precedence: file > promise > image data > remote link.
enum BrowserDragPayload {
    case files([URL])
    case promise(BrowserDragPromiseDelivery)
    case imageData(Data, UTType, suggestedName: String?)
    case remote(URL, suggestedName: String?)

    static let maxDataURLBytes = 64 * 1024 * 1024
    static let nameType = "public.url-name"
    static let linkTypes = ["public.url", "Apple URL pasteboard type", "public.utf8-plain-text"]
    /// Safari offers a decoded TIFF next to the real link, so TIFF is only the last resort.
    static let imageTypes: [UTType] = [.png, .jpeg, .heic, .webP, .gif, .tiff]

    /// Pasteboard types a drop target must register to be offered these drags.
    static var registeredTypes: [NSPasteboard.PasteboardType] {
        let promises = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        let links = linkTypes.map { NSPasteboard.PasteboardType($0) }
        let images = imageTypes.map { NSPasteboard.PasteboardType($0.identifier) }
        return [.fileURL] + promises + links + images
    }

    private static func name(in snapshot: BrowserDragSnapshot) -> String? {
        snapshot.read(nameType).flatMap { String(data: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func linkText(in snapshot: BrowserDragSnapshot) -> [String] {
        linkTypes.compactMap { snapshot.read($0).flatMap { String(data: $0, encoding: .utf8) } }
    }

    /// Placeholder inputs for the donut, decided from types and link text alone: image bytes are never read, so
    /// this is safe on the main thread at drag time. `data:` links are not offered (they need decoding).
    static func peekInputs(_ snapshot: BrowserDragSnapshot) -> [URL]? {
        if !snapshot.fileURLs.isEmpty { return BrowserDragPayload.files(snapshot.fileURLs).placeholderInputs }
        if !snapshot.promiseReceivers.isEmpty {
            return BrowserDragPayload.promise(BrowserDragPromiseDelivery(receivers: snapshot.promiseReceivers)).placeholderInputs
        }
        let name = name(in: snapshot)
        let image = imageTypes.first { snapshot.types.contains($0.identifier) }
        let imageInputs = image?.preferredFilenameExtension.map { placeholder(extension: $0, stem: stem("image", name)) }
        if image != .tiff, let imageInputs { return imageInputs }
        for text in linkText(in: snapshot) {
            if case .remote(let url, let suggested)? = remoteLink(from: text, name: name) {
                return BrowserDragPayload.remote(url, suggestedName: suggested).placeholderInputs
            }
        }
        return imageInputs
    }

    static func parse(_ snapshot: BrowserDragSnapshot) -> BrowserDragPayload? {
        if !snapshot.fileURLs.isEmpty { return .files(snapshot.fileURLs) }
        if !snapshot.promiseReceivers.isEmpty { return .promise(BrowserDragPromiseDelivery(receivers: snapshot.promiseReceivers)) }
        let name = name(in: snapshot)
        let image = imageTypes.lazy
            .filter { snapshot.types.contains($0.identifier) }
            .compactMap { type in snapshot.read(type.identifier).flatMap { $0.isEmpty ? nil : (type, $0) } }
            .first
        if let image, image.0 != .tiff { return .imageData(image.1, image.0, suggestedName: name) }
        if let link = linkText(in: snapshot).lazy.compactMap({ link(from: $0, name: name) }).first { return link }
        return image.map { .imageData($0.1, $0.0, suggestedName: name) }
    }

    /// An http(s) link, or an inline base64 `data:image/…` URL. Any other scheme (javascript:, ftp:, file:) is rejected.
    static func link(from text: String, name: String?) -> BrowserDragPayload? {
        remoteLink(from: text, name: name) ?? dataImage(from: text, name: name)
    }

    static func remoteLink(from text: String, name: String?) -> BrowserDragPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = DownloadManager.validHTTPURL(from: trimmed) else { return nil }
        return .remote(url, suggestedName: name)
    }

    private static func dataImage(from text: String, name: String?) -> BrowserDragPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maxDataURLBytes, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.prefix(11).lowercased() == "data:image/", let comma = trimmed.firstIndex(of: ",") else { return nil }
        let header = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<comma].lowercased()
        let parts = header.split(separator: ";").map(String.init)
        guard parts.last == "base64", let mime = parts.first, let type = UTType(mimeType: mime), type.conforms(to: .image),
              let data = Data(base64Encoded: String(trimmed[trimmed.index(after: comma)...])), !data.isEmpty else { return nil }
        return .imageData(data, type, suggestedName: name)
    }

    /// Extension the converter can list targets for before anything is fetched; nil when unknown.
    var expectedExtension: String? {
        switch self {
        case .files(let urls): return Self.known(urls.first?.pathExtension)
        case .promise(let delivery):
            return delivery.receivers.lazy.flatMap(\.fileTypes).compactMap { UTType($0)?.preferredFilenameExtension }.first
        case .imageData(_, let type, _): return type.preferredFilenameExtension
        case .remote(let url, let name): return Self.known(url.pathExtension) ?? Self.known(name.map { ($0 as NSString).pathExtension })
        }
    }

    /// Stand-in input for target lookup; the registry only looks at the extension.
    var placeholderInputs: [URL]? {
        guard let ext = expectedExtension else { return nil }
        if case .files(let urls) = self { return urls }
        let stem: String
        switch self {
        case .remote(let url, let name): stem = Self.stem(url.deletingPathExtension().lastPathComponent, name)
        case .imageData(_, _, let name): stem = Self.stem("image", name)
        default: stem = "download"
        }
        return Self.placeholder(extension: ext, stem: stem)
    }

    private static func placeholder(extension ext: String, stem: String) -> [URL] {
        let name = DownloadManager.sanitizedFileName("\(stem).\(ext)")
        return [FileManager.default.temporaryDirectory.appendingPathComponent(name)]
    }

    private static func stem(_ fallback: String, _ name: String?) -> String {
        let base = (name.map { ($0 as NSString).deletingPathExtension } ?? fallback)
        return base.isEmpty || base == "/" ? "download" : base
    }

    private static func known(_ ext: String?) -> String? {
        guard let ext = ext?.lowercased(), !ext.isEmpty, ext.count <= 8, BrowserDragNaming.isKnownExtension(ext) else { return nil }
        return ext
    }
}
