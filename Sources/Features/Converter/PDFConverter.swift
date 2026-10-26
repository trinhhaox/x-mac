import CoreGraphics
import Foundation
import PDFKit
import Quartz
import UniformTypeIdentifiers

/// PDF → page images (into a folder), merge, and compress via the system Quartz filter.
struct PDFConverter: FileConverter {
    static let mergeTargetID = "pdf.merge"
    static let compressFilterURL = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")

    let id = "pdf"
    var requiredTool: ExternalTool? { nil }

    private let compressFilterExists: Bool

    init(fileManager: FileManager = .default) {
        compressFilterExists = fileManager.fileExists(atPath: Self.compressFilterURL.path)
    }

    func targets(for input: URL) -> [ConversionTarget] {
        guard input.conversionType == .pdf else { return [] }
        var targets = [
            ConversionTarget(id: "pdf.png", title: "Ảnh PNG theo trang", fileExtension: "", group: .pdf),
            ConversionTarget(id: "pdf.jpg", title: "Ảnh JPG theo trang", fileExtension: "", group: .pdf),
            ConversionTarget(id: Self.mergeTargetID, title: "Gộp các PDF", fileExtension: "pdf", group: .pdf, combinesInputs: true)
        ]
        if compressFilterExists {
            targets.append(ConversionTarget(id: "pdf.compress", title: "Nén PDF", fileExtension: "pdf", group: .pdf))
        }
        return targets
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        do {
            try await BlockingWork.run { check in
                switch request.target.id {
                case "pdf.png": try renderPages(request, type: .png, fileExtension: "png", check: check, progress: progress)
                case "pdf.jpg": try renderPages(request, type: .jpeg, fileExtension: "jpg", check: check, progress: progress)
                case Self.mergeTargetID: try merge(request, check: check, progress: progress)
                case "pdf.compress": try compress(request, check: check, progress: progress)
                default: throw ConversionError.unsupportedInput(request.target.id)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }
    }

    private func renderPages(
        _ request: ConversionRequest, type: UTType, fileExtension: String,
        check: BlockingWork.CancellationCheck, progress: (Double) -> Void
    ) throws {
        let document = try Self.open(request.inputs.first)
        try FileManager.default.createDirectory(at: request.outputURL, withIntermediateDirectories: false)
        let digits = max(3, String(document.pageCount).count)
        let scale = request.preset.pdfRenderDPI / 72
        let isJPEG = type == .jpeg
        for index in 0..<document.pageCount {
            try check()
            guard let page = document.page(at: index), let image = PDFPageDrawing.render(page, scale: scale, maxPixel: request.preset.maxImageDimension) else {
                throw ConversionError.failed(L10n.text("Không đọc được tệp"))
            }
            let name = "page-" + String(format: "%0\(digits)d", index + 1) + "." + fileExtension
            try ImageIOSupport.write(
                image, to: request.outputURL.appendingPathComponent(name), type: type,
                quality: isJPEG ? request.preset.imageQuality : nil
            )
            progress(Double(index + 1) / Double(document.pageCount))
        }
    }

    private func merge(_ request: ConversionRequest, check: BlockingWork.CancellationCheck, progress: (Double) -> Void) throws {
        guard request.inputs.count >= 2 else {
            throw ConversionError.unsupportedInput(L10n.text("Cần ít nhất 2 tệp PDF"))
        }
        let merged = PDFDocument()
        for (index, url) in request.inputs.enumerated() {
            try check()
            let source = try Self.open(url)
            for pageIndex in 0..<source.pageCount {
                if let page = source.page(at: pageIndex) { merged.insert(page, at: merged.pageCount) }
            }
            progress(Double(index + 1) / Double(request.inputs.count))
        }
        guard merged.write(to: request.outputURL) else {
            throw ConversionError.failed(L10n.text("Không ghi được tệp đầu ra"))
        }
    }

    private func compress(_ request: ConversionRequest, check: BlockingWork.CancellationCheck, progress: (Double) -> Void) throws {
        let document = try Self.open(request.inputs.first)
        guard let filter = QuartzFilter(url: Self.compressFilterURL),
              let context = CGContext(request.outputURL as CFURL, mediaBox: nil, nil),
              filter.apply(to: context) else {
            throw ConversionError.failed(L10n.text("Không ghi được tệp đầu ra"))
        }
        for index in 0..<document.pageCount {
            try check()
            guard let page = document.page(at: index) else { continue }
            PDFPageDrawing.copy(page, to: context)
            progress(Double(index + 1) / Double(document.pageCount))
        }
        context.closePDF()
    }

    private static func open(_ url: URL?) throws -> PDFDocument {
        guard let url, let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ConversionError.unsupportedInput(L10n.text("Không đọc được tệp"))
        }
        guard !document.isLocked else {
            throw ConversionError.unsupportedInput(L10n.text("PDF được khóa bằng mật khẩu"))
        }
        return document
    }
}

enum PDFPageDrawing {
    /// Visible size in points, with the page's own rotation applied.
    private static func size(of page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    private static func draw(_ page: PDFPage, in context: CGContext, rect: CGRect) {
        guard let ref = page.pageRef else { return }
        context.concatenate(ref.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
    }

    static func render(_ page: PDFPage, scale: Double, maxPixel: Int?) -> CGImage? {
        let points = size(of: page)
        var factor = scale
        if let maxPixel, maxPixel > 0, max(points.width, points.height) * factor > Double(maxPixel) {
            factor = Double(maxPixel) / max(points.width, points.height)
        }
        let width = max(1, Int((points.width * factor).rounded()))
        let height = max(1, Int((points.height * factor).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        draw(page, in: context, rect: rect)
        return context.makeImage()
    }

    static func copy(_ page: PDFPage, to context: CGContext) {
        let rect = CGRect(origin: .zero, size: size(of: page))
        var mediaBox = rect
        let info = [kCGPDFContextMediaBox as String: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)] as CFDictionary
        context.beginPDFPage(info)
        draw(page, in: context, rect: rect)
        context.endPDFPage()
    }
}
