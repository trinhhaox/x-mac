import CoreGraphics
import Foundation

/// Pure helpers for reading text out of a screenshot; reuses the converter's Vision setup.
enum ScreenTextRecognizer {
    static let screencapture = URL(fileURLWithPath: "/usr/sbin/screencapture")

    static var isCaptureAvailable: Bool { FileManager.default.isExecutableFile(atPath: screencapture.path) }

    /// Interactive region selection, no shutter sound; Esc leaves no file behind.
    static func captureArguments(output: URL) -> [String] { ["-i", "-x", output.path] }

    static func recognizeText(in image: CGImage) throws -> String {
        let languages = try OCRConverter.recognitionLanguages()
        return try OCRConverter.recognize(image, languages: languages.codes)
    }

    /// Without Screen Recording permission macOS hands back an image with nothing in it; test for pure black on a 16x16 downsample.
    static func isBlank(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0xFF, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn && pixels.allSatisfy { $0 < 3 }
    }
}
