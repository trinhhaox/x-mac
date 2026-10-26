import CoreGraphics
import Foundation

/// TTF/OTF ↔ WOFF 1.0. TTF ↔ OTF is not offered (glyf vs CFF outlines are not a container relabel)
/// and WOFF2 is skipped (needs Brotli plus the glyf/loca transform).
struct FontConverter: FileConverter {
    let id = "font"
    let requiredTool: ExternalTool? = nil

    private static let woffTarget = ConversionTarget(id: "font.woff", title: "Phông WOFF", fileExtension: "woff", group: .document)
    private static let ttfTarget = ConversionTarget(id: "font.ttf", title: "Phông TTF", fileExtension: "ttf", group: .document)
    private static let otfTarget = ConversionTarget(id: "font.otf", title: "Phông OTF", fileExtension: "otf", group: .document)

    init() {}

    func targets(for input: URL) -> [ConversionTarget] {
        switch input.lowercasedExtension {
        case "ttf", "otf": return [Self.woffTarget]
        case "woff": return [Self.ttfTarget, Self.otfTarget]
        default: return []
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, !targets(for: input).isEmpty else {
            throw ConversionError.unsupportedInput(request.target.id)
        }
        let output = try await BlockingWork.run { _ in try Self.transform(input: input, target: request.target) }
        try Task.checkCancellation()
        do {
            try output.write(to: request.outputURL)
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }
        progress(1)
    }

    private static func transform(input: URL, target: ConversionTarget) throws -> Data {
        let data = try Data(contentsOf: input)
        do {
            if target.id == woffTarget.id {
                try validate(sfnt: data)
                return try FontWoffCodec.encode(sfnt: data)
            }
            guard let natural = FontWoffCodec.sfntExtension(forFlavorOf: data) else {
                throw ConversionError.unsupportedInput(L10n.text("Không đọc được tệp"))
            }
            guard natural == target.fileExtension else {
                throw ConversionError.unsupportedInput(L10n.format("Phông này là %@, không phải %@", natural.uppercased(), target.fileExtension.uppercased()))
            }
            let sfnt = try FontWoffCodec.decode(woff: data)
            try validate(sfnt: sfnt)
            return sfnt
        } catch let error as FontWoffCodec.CodecError {
            throw ConversionError.failed(L10n.text(error.message))
        }
    }

    /// CoreGraphics must be able to load the font, otherwise the output would be unusable.
    static func validate(sfnt: Data) throws {
        guard let provider = CGDataProvider(data: sfnt as CFData), CGFont(provider) != nil else {
            throw ConversionError.failed(L10n.text("Không đọc được tệp"))
        }
    }
}
