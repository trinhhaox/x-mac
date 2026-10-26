import CoreGraphics
import Foundation
import UniformTypeIdentifiers

public enum ConversionGroup: String, CaseIterable, Codable {
    case image, pdf, document, office, media, archive, subtitle
}

/// One choice offered for a set of input files, e.g. "PNG" or "Merge into one PDF".
public struct ConversionTarget: Hashable, Codable, Identifiable {
    /// Stable id, unique across converters: "<converterID>.<target>" (e.g. "image.png").
    public let id: String
    /// Vietnamese display name; also its L10n key.
    public let title: String
    /// Output file extension without the dot; empty when the output is a folder (extract).
    public let fileExtension: String
    public let group: ConversionGroup
    /// True when all selected inputs produce a single output (merge, ZIP, images → PDF).
    public let combinesInputs: Bool

    public init(id: String, title: String, fileExtension: String, group: ConversionGroup, combinesInputs: Bool = false) {
        self.id = id
        self.title = title
        self.fileExtension = fileExtension
        self.group = group
        self.combinesInputs = combinesInputs
    }
}

public struct ConversionPreset: Codable, Equatable {
    /// Lossy image quality, 0...1.
    public var imageQuality: Double = 0.85
    /// Longest edge in pixels for image output; nil keeps the original size.
    public var maxImageDimension: Int?
    public var pdfRenderDPI: Double = 150
    /// Video output height (e.g. 720); nil keeps the original.
    public var maxVideoHeight: Int?
    /// Page range for "Trích trang đã chọn", e.g. "1-3, 5, 8-"; nil/blank means not set.
    public var pdfPageRange: String?
    /// Normalized (0...1, top-left origin, in EXIF-oriented space) crop applied before resizing.
    /// Set per job by the manager; never persisted with the saved presets.
    public var cropRect: CGRect?

    public init() {}
}

/// Everything a converter needs for one run. `outputURL` is already reserved and
/// free; the converter writes exactly there (a file, or a folder for extraction).
public struct ConversionRequest {
    public let inputs: [URL]
    public let target: ConversionTarget
    public let preset: ConversionPreset
    public let outputURL: URL

    public init(inputs: [URL], target: ConversionTarget, preset: ConversionPreset, outputURL: URL) {
        self.inputs = inputs
        self.target = target
        self.preset = preset
        self.outputURL = outputURL
    }
}

public enum ConversionError: Error, Equatable {
    case unsupportedInput(String)
    case toolMissing(ExternalTool)
    case failed(String)
}

public protocol FileConverter {
    var id: String { get }
    /// External binary this converter needs; nil for native converters.
    var requiredTool: ExternalTool? { get }
    /// Targets offered for one input file. Return [] when the file is not handled.
    func targets(for input: URL) -> [ConversionTarget]
    /// `progress` takes 0...1 and may be called from any thread. Must honour Task cancellation
    /// and must not leave a partial file at `request.outputURL` when it throws.
    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws
}

extension URL {
    /// The input's type from its extension; avoids touching the file.
    var conversionType: UTType? { UTType(filenameExtension: pathExtension.lowercased()) }
}
