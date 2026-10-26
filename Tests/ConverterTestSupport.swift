import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
@testable import Xmac

enum ConverterFixtures {
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xmac-converter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A solid red image; `orientation` is written as EXIF so tests can check it is applied.
    @discardableResult
    static func writeImage(
        to url: URL, width: Int = 40, height: Int = 20, type: UTType = .png, orientation: Int? = nil
    ) throws -> URL {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    @discardableResult
    static func writePDF(to url: URL, pages: Int) throws -> URL {
        let document = PDFDocument()
        for index in 0..<pages {
            let image = try makeImage(width: 50 + index * 10, height: 80)
            guard let page = PDFPage(image: image) else { throw CocoaError(.fileWriteUnknown) }
            document.insert(page, at: index)
        }
        guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    private static func makeImage(width: Int, height: Int) throws -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    static func imageSize(at url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image.width, image.height)
    }

    static func request(
        _ inputs: [URL], _ target: ConversionTarget, output: URL, preset: ConversionPreset = ConversionPreset()
    ) -> ConversionRequest {
        ConversionRequest(inputs: inputs, target: target, preset: preset, outputURL: output)
    }
}
