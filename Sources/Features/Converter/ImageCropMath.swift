import CoreGraphics

enum CropAspect: String, CaseIterable, Identifiable {
    case free, square, fourThree, threeTwo, sixteenNine, nineSixteen

    var id: String { rawValue }

    /// Width / height; nil for a free-form frame.
    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3
        case .threeTwo: return 3.0 / 2
        case .sixteenNine: return 16.0 / 9
        case .nineSixteen: return 9.0 / 16
        }
    }

    /// Vietnamese L10n key for "free"; ratios are language-neutral.
    var title: String {
        switch self {
        case .free: return "Tự do"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .threeTwo: return "3:2"
        case .sixteenNine: return "16:9"
        case .nineSixteen: return "9:16"
        }
    }
}

/// Pure geometry for the crop frame. Rects are normalized (0...1, top-left origin) in the
/// EXIF-oriented image space, so they stay valid at any preview or output resolution.
enum ImageCropMath {
    static let minSide: CGFloat = 0.02
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// True when the frame still covers the whole image, so applying it changes nothing.
    static func isFullFrame(_ rect: CGRect, tolerance: CGFloat = 0.001) -> Bool {
        rect.minX <= tolerance && rect.minY <= tolerance
            && rect.maxX >= 1 - tolerance && rect.maxY >= 1 - tolerance
    }

    /// Keeps the rect inside the image and at least `minSide` wide and tall.
    static func clamped(_ rect: CGRect) -> CGRect {
        let width = min(max(rect.width, minSide), 1)
        let height = min(max(rect.height, minSide), 1)
        return CGRect(
            x: min(max(rect.minX, 0), 1 - width), y: min(max(rect.minY, 0), 1 - height), width: width, height: height
        )
    }

    /// Pixel rect for `CGImage.cropping(to:)`: whole pixels, inside the image, at least 1x1.
    static func pixelRect(_ normalized: CGRect, width: Int, height: Int) -> CGRect {
        let rect = clamped(normalized)
        let x = min(Int((rect.minX * CGFloat(width)).rounded()), width - 1)
        let y = min(Int((rect.minY * CGFloat(height)).rounded()), height - 1)
        let right = min(max(Int((rect.maxX * CGFloat(width)).rounded()), x + 1), width)
        let bottom = min(max(Int((rect.maxY * CGFloat(height)).rounded()), y + 1), height)
        return CGRect(x: x, y: y, width: right - x, height: bottom - y)
    }

    static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        clamped(rect.offsetBy(dx: dx, dy: dy))
    }

    /// Frame spanned by a fixed corner and a dragged corner. With an aspect ratio (width / height in
    /// pixels) the frame shrinks to the largest one of that shape that fits the dragged box.
    static func resized(anchor: CGPoint, to point: CGPoint, aspect: CGFloat?, imageSize: CGSize) -> CGRect {
        let corner = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        var width = abs(corner.x - anchor.x)
        var height = abs(corner.y - anchor.y)
        if let aspect, imageSize.width > 0, imageSize.height > 0 {
            let normalizedRatio = aspect * imageSize.height / imageSize.width
            if width / max(height, .leastNonzeroMagnitude) > normalizedRatio {
                width = height * normalizedRatio
            } else {
                height = width / normalizedRatio
            }
        }
        let x = corner.x >= anchor.x ? anchor.x : anchor.x - width
        let y = corner.y >= anchor.y ? anchor.y : anchor.y - height
        return clamped(CGRect(x: x, y: y, width: width, height: height))
    }

    /// Largest centered frame of the given pixel aspect ratio.
    static func fitted(aspect: CGFloat, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return unit }
        let normalizedRatio = aspect * imageSize.height / imageSize.width
        let width = min(normalizedRatio, 1)
        let height = min(1 / normalizedRatio, 1)
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
}
