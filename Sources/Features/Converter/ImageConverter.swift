import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Image format conversion via ImageIO. Quality and max size come from the preset.
struct ImageConverter: FileConverter {
    let id = "image"
    var requiredTool: ExternalTool? { nil }

    private struct Format {
        let key: String
        let type: UTType
        let isLossy: Bool
        let hasAlpha: Bool
    }

    private static let formats: [Format] = [
        Format(key: "jpg", type: .jpeg, isLossy: true, hasAlpha: false),
        Format(key: "png", type: .png, isLossy: false, hasAlpha: true),
        Format(key: "heic", type: .heic, isLossy: true, hasAlpha: true),
        Format(key: "tiff", type: .tiff, isLossy: false, hasAlpha: true),
        Format(key: "gif", type: .gif, isLossy: false, hasAlpha: false),
        Format(key: "bmp", type: .bmp, isLossy: false, hasAlpha: false),
        Format(key: "icns", type: .icns, isLossy: false, hasAlpha: true)
    ]

    func targets(for input: URL) -> [ConversionTarget] {
        guard let type = input.conversionType, ImageIOSupport.isReadable(type) else { return [] }
        return Self.formats
            .filter { ImageIOSupport.writableIdentifiers.contains($0.type.identifier) && $0.type != type }
            .map { ConversionTarget(id: "image.\($0.key)", title: $0.key.uppercased(), fileExtension: $0.key, group: .image) }
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first,
              let format = Self.formats.first(where: { "image.\($0.key)" == request.target.id }) else {
            throw ConversionError.unsupportedInput(request.target.id)
        }
        try await BlockingWork.run { check in
            try check()
            var image: CGImage
            if let crop = request.preset.cropRect {
                // Crop needs the full-size oriented image; resizing comes after it.
                let full = try ImageIOSupport.loadImage(input, maxPixel: nil)
                image = try ImageIOSupport.downscaled(
                    ImageIOSupport.cropped(full, to: crop), maxPixel: request.preset.maxImageDimension
                )
            } else {
                image = try ImageIOSupport.loadImage(input, maxPixel: request.preset.maxImageDimension)
            }
            if !format.hasAlpha { image = ImageIOSupport.flattenedOnWhite(image) }
            progress(0.5)
            try check()
            try ImageIOSupport.write(
                image, to: request.outputURL, type: format.type,
                quality: format.isLossy ? request.preset.imageQuality : nil
            )
        }
        progress(1)
    }
}
