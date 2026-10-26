import Foundation
import PDFKit
import Testing
@testable import Xmac

@Suite struct PDFPagesConverterTests {
    private let converter = PDFPagesConverter()

    private func choice(_ id: String) throws -> ConversionTarget {
        try #require(converter.targets(for: URL(fileURLWithPath: "/tmp/a.pdf")).first { $0.id == id })
    }

    private func extract(_ range: String?, pages: Int, in dir: URL) async throws -> URL {
        let input = try ConverterFixtures.writePDF(to: dir.appendingPathComponent("doc.pdf"), pages: pages)
        let out = dir.appendingPathComponent("part.pdf")
        var preset = ConversionPreset()
        preset.pdfPageRange = range
        let request = ConverterFixtures.request([input], try choice(PDFPagesConverter.extractTargetID), output: out, preset: preset)
        try await converter.convert(request, progress: { _ in })
        return out
    }

    @Test func offersChoicesOnlyForPDFs() {
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.png")).isEmpty)
        let ids = converter.targets(for: URL(fileURLWithPath: "/tmp/a.pdf")).map(\.id)
        #expect(ids == [PDFPagesConverter.splitTargetID, PDFPagesConverter.extractTargetID])
    }

    @Test func splitsIntoOnePDFPerPage() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try ConverterFixtures.writePDF(to: dir.appendingPathComponent("doc.pdf"), pages: 3)
        let out = dir.appendingPathComponent("doc-out")
        let request = ConverterFixtures.request([input], try choice(PDFPagesConverter.splitTargetID), output: out)
        try await converter.convert(request, progress: { _ in })
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(names == ["doc - trang 001.pdf", "doc - trang 002.pdf", "doc - trang 003.pdf"])
        #expect(PDFDocument(url: out.appendingPathComponent(names[1]))?.pageCount == 1)
    }

    @Test func extractsSelectedPagesInWrittenOrder() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = try #require(PDFDocument(url: try await extract("4, 1-2", pages: 4, in: dir)))
        #expect(result.pageCount == 3)
        // Fixture pages grow 10pt wider each, so page 4 must come first.
        let widths = (0..<3).compactMap { result.page(at: $0)?.bounds(for: .mediaBox).width }
        #expect(widths.count == 3 && widths[0] > widths[1] && widths[1] < widths[2])
    }

    @Test(arguments: [nil, "", "   "] as [String?])
    func extractWithoutRangeFailsClearly(_ range: String?) async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: ConversionError.failed("Chưa nhập khoảng trang")) {
            _ = try await extract(range, pages: 2, in: dir)
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("part.pdf").path))
    }

    @Test func rangeBeyondPageCountFailsAndLeavesNoOutput() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: ConversionError.self) { _ = try await extract("9-12", pages: 2, in: dir) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("part.pdf").path))
    }
}
