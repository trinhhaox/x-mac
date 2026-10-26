import Foundation
import UniformTypeIdentifiers

/// Builds a `BrowserDragPayload` from the NSItemProvider SwiftUI hands to `onDrop`.
/// Representations are loaded lazily in the same precedence as `BrowserDragPayload.parse`: image > link > TIFF > any image.
enum BrowserDragProviderReader {
    /// Dragged address-bar text arrives as plain text; only a lone http(s) link in it becomes a download.
    private static let linkIdentifiers = BrowserDragPayload.linkTypes + [UTType.plainText.identifier]

    static func payload(from provider: NSItemProvider) async -> BrowserDragPayload? {
        let registered = Set(provider.registeredTypeIdentifiers)
        let name = await suggestedName(of: provider, registered: registered)
        for type in BrowserDragPayload.imageTypes where type != .tiff && registered.contains(type.identifier) {
            if let data = await data(of: provider, type.identifier) { return .imageData(data, type, suggestedName: name) }
        }
        for identifier in linkIdentifiers where registered.contains(identifier) {
            guard let text = await data(of: provider, identifier).flatMap({ String(data: $0, encoding: .utf8) }),
                  let link = BrowserDragPayload.link(from: text, name: name) else { continue }
            return link
        }
        if registered.contains(UTType.tiff.identifier), let data = await data(of: provider, UTType.tiff.identifier) {
            return .imageData(data, .tiff, suggestedName: name)
        }
        return await anyImage(in: provider, name: name)
    }

    private static func suggestedName(of provider: NSItemProvider, registered: Set<String>) async -> String? {
        var name = provider.suggestedName
        if registered.contains(BrowserDragPayload.nameType), let data = await data(of: provider, BrowserDragPayload.nameType),
           let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            name = text
        }
        return name
    }

    /// Promised images (Chrome, Arc) only expose generic image types; asking for one makes the system fulfil the promise.
    private static func anyImage(in provider: NSItemProvider, name: String?) async -> BrowserDragPayload? {
        let candidates = provider.registeredTypeIdentifiers.compactMap { UTType($0) }.filter { $0.conforms(to: .image) }
        for type in candidates {
            if let data = await data(of: provider, type.identifier) { return .imageData(data, type, suggestedName: name) }
        }
        return nil
    }

    private static func data(of provider: NSItemProvider, _ identifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                if let error { NSLog("Converter: could not read dropped \(identifier): \(error)") }
                continuation.resume(returning: data.flatMap { $0.isEmpty ? nil : $0 })
            }
        }
    }
}
