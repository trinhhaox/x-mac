import Foundation
import UniformTypeIdentifiers

/// Picks the file name for something fetched from a browser drag.
enum BrowserDragNaming {
    static let maxStemBytes = 200
    static let maxExtensionLength = 16

    /// Unknown extensions still yield a (dynamic) UTType, so declared-ness is what counts.
    static func isKnownExtension(_ ext: String) -> Bool {
        UTType(filenameExtension: ext).map { !$0.isDynamic } ?? false
    }

    /// Name from `Content-Disposition`; `filename*=` (RFC 5987) wins over `filename=`.
    static func contentDispositionFileName(_ header: String?) -> String? {
        guard let header else { return nil }
        var plain: String?
        for part in splitParameters(header).dropFirst() {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var value = part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key == "filename*" {
                let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                if pieces.count == 3, pieces[0].lowercased() == "utf-8", let decoded = pieces[2].removingPercentEncoding, !decoded.isEmpty {
                    return decoded
                }
            } else if key == "filename" {
                if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
                if !value.isEmpty { plain = value }
            }
        }
        return plain
    }

    /// Splits on `;` outside double quotes.
    private static func splitParameters(_ header: String) -> [Substring] {
        var parts: [Substring] = []
        var start = header.startIndex
        var quoted = false
        for index in header.indices {
            if header[index] == "\"" { quoted.toggle() }
            else if header[index] == ";", !quoted {
                parts.append(header[start..<index])
                start = header.index(after: index)
            }
        }
        parts.append(header[start...])
        return parts
    }

    /// Control, line-separator and bidi-override characters can disguise an extension (`photo<RLO>gnp.command`).
    static func strippingUnsafeCharacters(_ name: String) -> String {
        let bidi: [ClosedRange<UInt32>] = [0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069]
        return String(name.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return false
            default: return !bidi.contains { $0.contains(scalar.value) }
            }
        })
    }

    static func safeName(_ raw: String, fallback: String = "download") -> String {
        DownloadManager.sanitizedFileName(strippingUnsafeCharacters(raw), fallback: fallback)
    }

    /// Preferred extension for a response `Content-Type`; nil for generic or unknown types.
    static func fileExtension(forMIME mime: String?) -> String? {
        guard let essence = mime?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased(),
              !essence.isEmpty, let type = UTType(mimeType: essence) else { return nil }
        return type.preferredFilenameExtension
    }

    /// Content-Disposition → suggested name → last URL component → "download", then an extension from the MIME type if missing.
    static func finalName(contentDisposition: String?, suggested: String?, url: URL, mime: String?) -> String {
        let lastComponent = url.path.count > 1 ? url.lastPathComponent : nil
        let candidates = [contentDisposition.flatMap(contentDispositionFileName), suggested, lastComponent]
        let raw = candidates.lazy.compactMap { $0 }.map { safeName($0, fallback: "") }.first { !$0.isEmpty }
        return withExtension(raw ?? "download", mime: mime)
    }

    static func withExtension(_ name: String, mime: String?) -> String {
        var ext = (name as NSString).pathExtension
        var stem = (name as NSString).deletingPathExtension
        if ext.isEmpty || !isKnownExtension(ext), let added = fileExtension(forMIME: mime) {
            stem = name
            ext = added
        }
        return bounded(stem: stem, ext: ext)
    }

    /// Stem capped at `maxStemBytes` UTF-8 bytes on a Character boundary; an over-long extension is dropped.
    static func bounded(stem: String, ext: String) -> String {
        var kept = ""
        var bytes = 0
        for character in stem {
            bytes += character.utf8.count
            if bytes > maxStemBytes { break }
            kept.append(character)
        }
        if kept.isEmpty { kept = "download" }
        return ext.isEmpty || ext.count > maxExtensionLength ? kept : "\(kept).\(ext)"
    }
}
