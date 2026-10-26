import Foundation

/// GeoJSON ↔ KML/KMZ ↔ GPX, plus a CSV of coordinates. `.json` is not claimed: deciding would mean reading the file.
struct GeoConverter: FileConverter {
    let id = "geo"
    let requiredTool: ExternalTool? = nil

    private static let maxInputBytes = 256 << 20
    private static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    private static let inputs = ["geojson", "kml", "kmz", "gpx"]
    private static let outputs: [(ext: String, title: String)] = [
        ("geojson", "GeoJSON"), ("kml", "KML"), ("gpx", "GPX"), ("csv", "CSV (toạ độ)"),
    ]

    init() {}

    func targets(for input: URL) -> [ConversionTarget] {
        let ext = input.lowercasedExtension
        guard Self.inputs.contains(ext) else { return [] }
        let same = ext == "kmz" ? "" : ext
        return Self.outputs.filter { $0.ext != same }.map {
            ConversionTarget(id: "geo.\($0.ext)", title: $0.title, fileExtension: $0.ext, group: .document)
        }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, targets(for: input).contains(request.target) else {
            throw ConversionError.unsupportedInput(request.target.id)
        }
        let target = request.target.fileExtension
        let format = input.lowercasedExtension
        let output: Data
        if format == "kmz" {
            output = try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
                let kml = try await Self.extractKML(from: input, into: directory)
                return try await BlockingWork.run { _ in try Self.convert(kml, from: "kml", to: target) }
            }
        } else {
            output = try await BlockingWork.run { _ in try Self.convert(input, from: format, to: target) }
        }
        try Task.checkCancellation()
        do {
            try output.write(to: request.outputURL)
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }
        progress(1)
    }

    private static func convert(_ file: URL, from format: String, to target: String) throws -> Data {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxInputBytes else { throw ConversionError.unsupportedInput(L10n.text("Tệp quá lớn")) }
        let data = try Data(contentsOf: file)
        do {
            let features: [GeoFeature]
            switch format {
            case "geojson": features = try GeoJSONCodec.parse(data)
            case "kml": features = try GeoKMLCodec.parse(data)
            default: features = try GeoGPXCodec.parse(data)
            }
            guard !features.isEmpty else { throw GeoError(message: "Không tìm thấy đối tượng địa lý") }
            switch target {
            case "geojson": return try GeoJSONCodec.write(features)
            case "kml": return GeoKMLCodec.write(features)
            case "gpx": return GeoGPXCodec.write(features)
            default: return Data(GeoText.csv(features).utf8)
            }
        } catch let error as GeoError {
            throw ConversionError.unsupportedInput(L10n.text(error.message))
        }
    }

    /// KMZ is a zip whose main entry is `doc.kml` (or the first .kml).
    private static func extractKML(from kmz: URL, into directory: URL) async throws -> URL {
        try await ZipArchiveGuard.validate(kmz)
        try await ConverterWorkspace.run(ditto, ["-x", "-k", kmz.path, directory.path], timeout: 120)
        let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        let kml = entries.filter { $0.lowercasedExtension == "kml" }
        guard let main = kml.first(where: { $0.lastPathComponent.lowercased() == "doc.kml" }) ?? kml.min(by: { $0.path < $1.path }) else {
            throw ConversionError.unsupportedInput(L10n.text("KMZ không chứa tệp KML"))
        }
        return main
    }
}
