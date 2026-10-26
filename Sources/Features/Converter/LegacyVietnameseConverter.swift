import Foundation

/// Re-encodes plain-text files written in TCVN3 (ABC) or VNI-Windows as UTF-8 Unicode.
/// The output keeps the input's extension, so the queue names it "name 1.txt" next to the original.
struct LegacyVietnameseConverter: FileConverter {
    let id = "vn-legacy"
    let requiredTool: ExternalTool? = nil

    private static let inputs: Set<String> = ["txt", "srt", "vtt", "ass", "csv", "html", "htm", "md"]
    private static let sources: [(charset: LegacyVietnameseCharset, suffix: String, title: String)] = [
        (.tcvn3, "tcvn3", "Unicode (từ TCVN3)"),
        (.vniWindows, "vni", "Unicode (từ VNI)")
    ]
    private static let charsetDeclaration = try? NSRegularExpression(
        pattern: #"(<meta[^>]*?charset\s*=\s*["']?)[A-Za-z0-9_\-]+"#, options: .caseInsensitive)

    init() {}

    func targets(for input: URL) -> [ConversionTarget] {
        guard Self.inputs.contains(input.lowercasedExtension) else { return [] }
        return Self.sources.map {
            ConversionTarget(id: "\(id).\($0.suffix)", title: $0.title, fileExtension: input.lowercasedExtension, group: .document)
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.inputs.count == 1,
              Self.inputs.contains(input.lowercasedExtension),
              let source = Self.sources.first(where: { "\(id).\($0.suffix)" == request.target.id }) else {
            throw ConversionError.unsupportedInput(request.target.id)
        }
        let data = try Data(contentsOf: input)
        try Task.checkCancellation()
        var text = Self.unicode(from: data, charset: source.charset)
        if ["html", "htm"].contains(input.lowercasedExtension) { text = Self.declareUTF8(in: text) }
        do {
            try Data(text.utf8).write(to: request.outputURL)
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }
        progress(1)
    }

    /// UTF-8 (BOM dropped) is converted as text; UTF-16 by BOM; anything else is raw legacy bytes.
    static func unicode(from data: Data, charset: LegacyVietnameseCharset) -> String {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return LegacyVietnameseEncoding.convert(text, from: charset)
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return LegacyVietnameseEncoding.convert(text, from: charset)
        }
        if let text = String(data: data, encoding: .utf8) { return LegacyVietnameseEncoding.convert(text, from: charset) }
        return LegacyVietnameseEncoding.decode(data, charset: charset)
    }

    private static func declareUTF8(in html: String) -> String {
        guard let charsetDeclaration else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return charsetDeclaration.stringByReplacingMatches(in: html, range: range, withTemplate: "$1utf-8")
    }
}
