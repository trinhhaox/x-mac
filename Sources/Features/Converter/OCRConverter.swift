import CoreGraphics
import Foundation
import PDFKit
import Vision

/// Image or PDF → one UTF-8 text file via Vision text recognition, all on device.
struct OCRConverter: FileConverter {
    static let targetID = "ocr.txt"
    private static let english = "en-US"

    let id = "ocr"
    var requiredTool: ExternalTool? { nil }

    func targets(for input: URL) -> [ConversionTarget] {
        guard input.conversionType == .pdf || ImageIOSupport.isReadable(input.conversionType) else { return [] }
        return [ConversionTarget(id: Self.targetID, title: "Văn bản (OCR)", fileExtension: "txt", group: .document)]
    }

    func convert(_ request: ConversionRequest, progress: @escaping (Double) -> Void) async throws {
        guard let input = request.inputs.first else { throw ConversionError.unsupportedInput(request.target.id) }
        do {
            try await BlockingWork.run { check in
                let pages = try Self.pageImages(of: input, preset: request.preset)
                let languages = try Self.recognitionLanguages()
                var texts: [String] = []
                for index in 0..<pages.count {
                    try check()
                    try autoreleasepool { texts.append(try Self.recognize(try pages.image(index), languages: languages.codes)) }
                    progress(Double(index + 1) / Double(pages.count))
                }
                var output = texts.enumerated().map { $0.offset == 0 ? $0.element : "\n\n--- Trang \($0.offset + 1) ---\n\n" + $0.element }
                    .joined()
                if !languages.vietnamese { output = L10n.text("[OCR: macOS này chưa hỗ trợ tiếng Việt, chỉ nhận dạng tiếng Anh]") + "\n\n" + output }
                try output.write(to: request.outputURL, atomically: true, encoding: .utf8)
            }
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }
    }

    /// Lazily decoded pages so a long PDF never holds every rendered bitmap in memory.
    private struct Pages {
        let count: Int
        let image: (Int) throws -> CGImage
    }

    private static func pageImages(of input: URL, preset: ConversionPreset) throws -> Pages {
        guard input.conversionType == .pdf else {
            return Pages(count: 1) { _ in try ImageIOSupport.loadImage(input, maxPixel: nil) }
        }
        guard let document = PDFDocument(url: input), document.pageCount > 0 else {
            throw ConversionError.unsupportedInput(L10n.text("Không đọc được tệp"))
        }
        guard !document.isLocked else { throw ConversionError.unsupportedInput(L10n.text("PDF được khóa bằng mật khẩu")) }
        return Pages(count: document.pageCount) { index in
            guard let page = document.page(at: index),
                  let image = PDFPageDrawing.render(page, scale: preset.pdfRenderDPI / 72, maxPixel: preset.maxImageDimension) else {
                throw ConversionError.failed(L10n.text("Không đọc được tệp"))
            }
            return image
        }
    }

    static func recognitionLanguages() throws -> (codes: [String], vietnamese: Bool) {
        let supported = try VNRecognizeTextRequest().supportedRecognitionLanguages()
        // Vision names Vietnamese "vi-VT"; match by prefix so a future "vi-VN" works too.
        guard let vietnamese = supported.first(where: { $0.hasPrefix("vi") }) else { return ([english], false) }
        return ([vietnamese, english], true)
    }

    static func recognize(_ image: CGImage, languages: [String]) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch {
            throw ConversionError.failed(error.localizedDescription)
        }
        return lines(from: request.results ?? [])
    }

    /// Reading order: rows top to bottom (Vision's origin is bottom-left), cells left to right.
    private static func lines(from observations: [VNRecognizedTextObservation]) -> String {
        let cells = observations.compactMap { observation in
            observation.topCandidates(1).first.map { (box: observation.boundingBox, text: $0.string) }
        }.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(box: CGRect, text: String)]] = []
        for cell in cells {
            if let last = rows.last?.first, abs(last.box.midY - cell.box.midY) < min(last.box.height, cell.box.height) / 2 {
                rows[rows.count - 1].append(cell)
            } else {
                rows.append([cell])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }
}
