import Foundation
import PDFKit

/// Splits a PDF into one file per page, or extracts a user-chosen page range into one PDF.
struct PDFPagesConverter: FileConverter {
    static let splitTargetID = "pdf-pages.split"
    static let extractTargetID = "pdf-pages.extract"

    let id = "pdf-pages"
    var requiredTool: ExternalTool? { nil }

    func targets(for input: URL) -> [ConversionTarget] {
        guard input.conversionType == .pdf else { return [] }
        return [
            ConversionTarget(id: Self.splitTargetID, title: "Tách từng trang", fileExtension: "", group: .pdf),
            ConversionTarget(id: Self.extractTargetID, title: "Trích trang đã chọn", fileExtension: "pdf", group: .pdf)
        ]
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        do {
            try await BlockingWork.run { check in
                let document = try Self.open(request.inputs.first)
                switch request.target.id {
                case Self.splitTargetID:
                    let name = request.inputs[0].deletingPathExtension().lastPathComponent
                    try Self.split(document, name: name, to: request.outputURL, check: check, progress: progress)
                case Self.extractTargetID:
                    try Self.extract(document, range: request.preset.pdfPageRange, to: request.outputURL, check: check, progress: progress)
                default: throw ConversionError.unsupportedInput(request.target.id)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }
    }

    private static func split(
        _ document: PDFDocument, name: String, to folder: URL,
        check: BlockingWork.CancellationCheck, progress: (Double) -> Void
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let digits = max(3, String(document.pageCount).count)
        for index in 0..<document.pageCount {
            try check()
            let file = "\(name) - trang " + String(format: "%0\(digits)d", index + 1) + ".pdf"
            try autoreleasepool { try write(pages: [index], of: document, to: folder.appendingPathComponent(file)) }
            progress(Double(index + 1) / Double(document.pageCount))
        }
    }

    private static func extract(
        _ document: PDFDocument, range: String?, to output: URL,
        check: BlockingWork.CancellationCheck, progress: (Double) -> Void
    ) throws {
        guard let range, !range.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConversionError.failed(L10n.text("Chưa nhập khoảng trang"))
        }
        let indices: [Int]
        do { indices = try PageRangeParser.pageIndices(range, pageCount: document.pageCount) } catch let error as PageRangeError {
            throw ConversionError.failed(error.message)
        }
        try check()
        try write(pages: indices, of: document, to: output)
        progress(1)
    }

    private static func write(pages indices: [Int], of source: PDFDocument, to url: URL) throws {
        let result = PDFDocument()
        for index in indices {
            try autoreleasepool {
                // Copy so the page is not moved out of (or shared with) the source document.
                guard let page = source.page(at: index)?.copy() as? PDFPage else {
                    throw ConversionError.failed(L10n.text("Không đọc được tệp"))
                }
                result.insert(page, at: result.pageCount)
            }
        }
        guard result.write(to: url) else { throw ConversionError.failed(L10n.text("Không ghi được tệp đầu ra")) }
    }

    private static func open(_ url: URL?) throws -> PDFDocument {
        guard let url, let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ConversionError.unsupportedInput(L10n.text("Không đọc được tệp"))
        }
        guard !document.isLocked else { throw ConversionError.unsupportedInput(L10n.text("PDF được khóa bằng mật khẩu")) }
        return document
    }
}
