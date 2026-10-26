import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Xmac

@Suite struct ImageCropMathTests {
    @Test func pixelRectRoundsAndStaysInside() {
        let rect = ImageCropMath.pixelRect(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5), width: 40, height: 20)
        #expect(rect == CGRect(x: 10, y: 10, width: 20, height: 10))
        let tiny = ImageCropMath.pixelRect(CGRect(x: 1, y: 1, width: 0, height: 0), width: 10, height: 10)
        #expect(tiny.width >= 1 && tiny.height >= 1 && tiny.maxX <= 10 && tiny.maxY <= 10)
    }

    @Test func fullFrameIsRecognisedOnlyWhenNothingIsCut() {
        #expect(ImageCropMath.isFullFrame(ImageCropMath.unit))
        #expect(!ImageCropMath.isFullFrame(CGRect(x: 0, y: 0, width: 1, height: 0.9)))
        #expect(!ImageCropMath.isFullFrame(CGRect(x: 0.1, y: 0, width: 0.9, height: 1)))
    }

    @Test func clampKeepsRectInsideUnit() {
        let rect = ImageCropMath.clamped(CGRect(x: -0.2, y: 0.9, width: 2, height: 0.5))
        #expect(rect.minX >= 0 && rect.maxX <= 1 && rect.minY >= 0 && rect.maxY <= 1)
        let moved = ImageCropMath.moved(CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), dx: 1, dy: -2)
        #expect(moved.maxX == 1 && moved.minY == 0)
    }

    @Test func squareFrameOnWideImageIsSquareInPixels() {
        let size = CGSize(width: 400, height: 200)
        let fitted = ImageCropMath.fitted(aspect: 1, imageSize: size)
        #expect(abs(fitted.width * 400 - fitted.height * 200) < 0.001)
        #expect(fitted.height == 1 && abs(fitted.midX - 0.5) < 0.001)
        let dragged = ImageCropMath.resized(anchor: CGPoint(x: 0.1, y: 0.1), to: CGPoint(x: 0.9, y: 0.5), aspect: 16.0 / 9, imageSize: size)
        #expect(abs(dragged.width * 400 / (dragged.height * 200) - 16.0 / 9) < 0.01)
        #expect(dragged.minX == 0.1 && dragged.minY == 0.1)
    }

    @Test func draggingPastTheAnchorFlipsTheFrame() {
        let rect = ImageCropMath.resized(
            anchor: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.2, y: 0.3), aspect: nil, imageSize: CGSize(width: 10, height: 10)
        )
        #expect(abs(rect.minX - 0.2) < 1e-9 && abs(rect.maxY - 0.5) < 1e-9)
    }
}

@Suite struct ImageCropConversionTests {
    /// Stored 40x20: left half red, right half blue, with the given EXIF orientation.
    private func writeTwoToneImage(to url: URL, orientation: Int?) throws {
        guard let context = CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func centerPixel(of url: URL) throws -> (r: Int, b: Int) {
        let image = try ImageIOSupport.loadImage(url, maxPixel: nil)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        return (Int(pixel[0]), Int(pixel[2]))
    }

    private func convert(orientation: Int?, crop: CGRect, maxDimension: Int? = nil) async throws -> (size: (width: Int, height: Int), pixel: (r: Int, b: Int)) {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("in.png")
        try writeTwoToneImage(to: input, orientation: orientation)
        var preset = ConversionPreset()
        preset.cropRect = crop
        preset.maxImageDimension = maxDimension
        let converter = ImageConverter()
        let target = try #require(converter.targets(for: input).first { $0.id == "image.tiff" })
        let out = dir.appendingPathComponent("out.tiff")
        try await converter.convert(ConverterFixtures.request([input], target, output: out, preset: preset), progress: { _ in })
        return (try #require(ConverterFixtures.imageSize(at: out)), try centerPixel(of: out))
    }

    @Test func cropsPlainImage() async throws {
        let result = try await convert(orientation: nil, crop: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(result.size.width == 20 && result.size.height == 20)
        #expect(result.pixel.r > 200 && result.pixel.b < 50)
    }

    @Test func cropUsesOrientedSpaceForExifOrientation6() async throws {
        // Orientation 6 displays the stored left (red) half on top: the top half must be red, the bottom blue.
        let top = try await convert(orientation: 6, crop: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        #expect(top.size.width == 20 && top.size.height == 20)
        #expect(top.pixel.r > 200 && top.pixel.b < 50)
        let bottom = try await convert(orientation: 6, crop: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        #expect(bottom.pixel.b > 200 && bottom.pixel.r < 50)
    }

    @Test func resizesAfterCropping() async throws {
        let result = try await convert(orientation: nil, crop: CGRect(x: 0, y: 0, width: 0.5, height: 1), maxDimension: 10)
        #expect(result.size.width == 10 && result.size.height == 10)
    }
}

@Suite struct ImageDownscaleTests {
    private func floatImage(width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let info = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0, space: space, bitmapInfo: info))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test func extendedRangeFloatImageStillShrinks() throws {
        let scaled = try ImageIOSupport.downscaled(try floatImage(width: 40, height: 20), maxPixel: 10)
        #expect(scaled.width == 10 && scaled.height == 5)
    }

    @Test func neverEnlargesOrResizesWithoutLimit() throws {
        let image = try floatImage(width: 8, height: 4)
        #expect(try ImageIOSupport.downscaled(image, maxPixel: 100).width == 8)
        #expect(try ImageIOSupport.downscaled(image, maxPixel: nil).width == 8)
    }
}
