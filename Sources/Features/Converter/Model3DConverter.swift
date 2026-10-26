import Foundation
import ModelIO

/// 3D mesh conversion with ModelIO. Formats are filtered at runtime by what ModelIO can import/export.
/// OBJ output is a single file: the `.mtl` ModelIO writes beside it (materials) is not kept.
struct Model3DConverter: FileConverter {
    let id = "model3d"
    let requiredTool: ExternalTool? = nil

    static let previewTarget = ConversionTarget(
        id: "model3d.png", title: "PNG (ảnh xem trước)", fileExtension: "png", group: .image)
    private static let importable = ["obj", "stl", "ply", "usd", "usda", "usdc", "usdz", "abc"]
    private static let exportable: [(ext: String, title: String)] = [
        ("obj", "Mô hình 3D OBJ"), ("stl", "Mô hình 3D STL"), ("ply", "Mô hình 3D PLY"),
        ("usd", "Mô hình 3D USD"), ("usda", "Mô hình 3D USDA"), ("usdc", "Mô hình 3D USDC"),
    ]

    init() {}

    func targets(for input: URL) -> [ConversionTarget] {
        let ext = input.lowercasedExtension
        guard Self.importable.contains(ext), MDLAsset.canImportFileExtension(ext) else { return [] }
        let formats = Self.exportable.filter { $0.ext != ext && MDLAsset.canExportFileExtension($0.ext) }.map {
            ConversionTarget(id: "model3d.\($0.ext)", title: $0.title, fileExtension: $0.ext, group: .document)
        }
        return formats + [Self.previewTarget]
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first, targets(for: input).contains(request.target) else {
            throw ConversionError.unsupportedInput(request.target.id)
        }
        let isPreview = request.target.id == Self.previewTarget.id
        let ext = request.target.fileExtension
        try await ConverterWorkspace.withTempDirectory(near: request.outputURL) { directory in
            let produced = try await BlockingWork.run { check in
                let asset = MDLAsset(url: input)
                guard asset.count > 0 else { throw ConversionError.unsupportedInput(L10n.text("Không đọc được tệp")) }
                try check()
                guard isPreview else { return try Self.export(asset, as: ext, in: directory) }
                let png = directory.appendingPathComponent("preview.png")
                try Model3DPreview.render(asset, to: png)
                try check()
                return png
            }
            progress(0.9)
            try ConverterWorkspace.publish(produced, to: request.outputURL)
        }
        progress(1)
    }

    private static func export(_ asset: MDLAsset, as ext: String, in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent("model.\(ext)")
        do {
            try asset.export(to: file)
        } catch {
            throw ConversionError.failed(error.localizedDescription)
        }
        guard ext == "obj" else { return file }
        let materials = file.deletingPathExtension().appendingPathExtension("mtl")
        guard FileManager.default.fileExists(atPath: materials.path) else { return file }
        try dropMaterialReferences(from: file)
        return file
    }

    private static func dropMaterialReferences(from obj: URL) throws {
        let text = try String(contentsOf: obj, encoding: .utf8)
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("mtllib") && !$0.hasPrefix("usemtl") }
        try kept.joined(separator: "\n").write(to: obj, atomically: true, encoding: .utf8)
    }
}
