import Foundation

/// SRT ↔ VTT ↔ ASS (dialogue lines only, default style). Output is always UTF-8.
struct SubtitleConverter: FileConverter {
    let id = "subtitle"
    var requiredTool: ExternalTool? { nil }

    private static let formats = ["srt", "vtt", "ass"]

    func targets(for input: URL) -> [ConversionTarget] {
        let ext = input.pathExtension.lowercased()
        guard Self.formats.contains(ext) else { return [] }
        return Self.formats.filter { $0 != ext }.map {
            ConversionTarget(id: "subtitle.\($0)", title: "Phụ đề \($0.uppercased())", fileExtension: $0, group: .subtitle)
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, request.target.id.hasPrefix("subtitle.") else {
            throw ConversionError.unsupportedInput(request.target.id)
        }
        let output = String(request.target.id.dropFirst("subtitle.".count))
        let data = try Data(contentsOf: input)
        guard let text = Self.decode(data) else {
            throw ConversionError.unsupportedInput(L10n.text("Không đọc được tệp"))
        }
        let cues = SubtitleFormats.parse(text, format: input.pathExtension.lowercased())
        guard !cues.isEmpty else { throw ConversionError.unsupportedInput(L10n.text("Không tìm thấy dòng phụ đề")) }
        try Task.checkCancellation()
        do {
            try Data(SubtitleFormats.serialize(cues, format: output).utf8).write(to: request.outputURL)
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }
        progress(1)
    }

    /// UTF-8 (with or without BOM) and UTF-16 BOMs first; legacy Vietnamese code page, then Western as fallbacks.
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let vietnamese = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsVietnamese.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: vietnamese)) ?? String(data: data, encoding: .windowsCP1252)
    }
}
