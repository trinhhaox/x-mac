import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared ImageIO helpers for the image and images-to-PDF converters.
enum ImageIOSupport {
    static let readableTypes: [UTType] = typeIdentifiers(CGImageSourceCopyTypeIdentifiers())
    static let writableIdentifiers: Set<String> = Set(typeIdentifiers(CGImageDestinationCopyTypeIdentifiers()).map(\.identifier))

    private static func typeIdentifiers(_ list: CFArray) -> [UTType] {
        ((list as? [String]) ?? []).compactMap { UTType($0) }
    }

    static func isReadable(_ type: UTType?) -> Bool {
        guard let type else { return false }
        return readableTypes.contains { type.conforms(to: $0) }
    }

    /// Decodes the first frame with EXIF orientation applied. `maxPixel` only ever shrinks.
    static func loadImage(_ url: URL, maxPixel: Int?) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ConversionError.unsupportedInput(L10n.text("Không đọc được tệp"))
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height, 1)
        let limit = min(maxPixel.flatMap { $0 > 0 ? $0 : nil } ?? longest, longest)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ConversionError.unsupportedInput(L10n.text("Không đọc được tệp"))
        }
        return image
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double?) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.failed(L10n.text("Không ghi được tệp đầu ra"))
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw ConversionError.failed(L10n.text("Không ghi được tệp đầu ra"))
        }
    }

    /// Formats without alpha (JPEG, BMP) would otherwise turn transparency black.
    static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }
}
