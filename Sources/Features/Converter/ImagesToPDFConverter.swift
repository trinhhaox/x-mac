import AppKit
import Foundation
import PDFKit

/// Combines any number of images into one PDF, one page per image in the given order.
struct ImagesToPDFConverter: FileConverter {
    let id = "images-pdf"
    var requiredTool: ExternalTool? { nil }

    func targets(for input: URL) -> [ConversionTarget] {
        guard ImageIOSupport.isReadable(input.conversionType) else { return [] }
        return [ConversionTarget(
            id: "images-pdf.pdf", title: "Gộp ảnh thành một PDF", fileExtension: "pdf", group: .pdf, combinesInputs: true
        )]
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard !request.inputs.isEmpty else { throw ConversionError.unsupportedInput(request.target.id) }
        try await BlockingWork.run { check in
            let document = PDFDocument()
            // Pixels are laid out at the preset DPI so a 12 MP photo does not become a poster-sized page.
            let pointsPerPixel = 72 / max(request.preset.pdfRenderDPI, 1)
            for (index, url) in request.inputs.enumerated() {
                try check()
                let image = try ImageIOSupport.loadImage(url, maxPixel: request.preset.maxImageDimension)
                let size = NSSize(width: Double(image.width) * pointsPerPixel, height: Double(image.height) * pointsPerPixel)
                guard let page = PDFPage(image: NSImage(cgImage: image, size: size)) else {
                    throw ConversionError.unsupportedInput(url.lastPathComponent)
                }
                document.insert(page, at: index)
                progress(Double(index + 1) / Double(request.inputs.count))
            }
            guard document.write(to: request.outputURL) else {
                try? FileManager.default.removeItem(at: request.outputURL)
                throw ConversionError.failed(L10n.text("Không ghi được tệp đầu ra"))
            }
        }
    }
}
