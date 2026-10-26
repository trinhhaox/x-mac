import Foundation
import PDFKit
import Testing
@testable import Xmac

@Suite struct PDFConverterTests {
    private let converter = PDFConverter()

    private func target(_ id: String) throws -> ConversionTarget {
        try #require(converter.targets(for: URL(fileURLWithPath: "/tmp/a.pdf")).first { $0.id == id })
    }

    @Test func targetsOnlyForPDFs() {
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.png")).isEmpty)
        let ids = converter.targets(for: URL(fileURLWithPath: "/tmp/a.pdf")).map(\.id)
        #expect(ids.contains("pdf.png") && ids.contains("pdf.jpg") && ids.contains(PDFConverter.mergeTargetID))
    }

    @Test func rendersOneImagePerPageIntoFolder() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try ConverterFixtures.writePDF(to: dir.appendingPathComponent("doc.pdf"), pages: 3)
        let out = dir.appendingPathComponent("doc")
        try await converter.convert(ConverterFixtures.request([input], try target("pdf.png"), output: out), progress: { _ in })
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(names == ["page-001.png", "page-002.png", "page-003.png"])
        let size = try #require(ConverterFixtures.imageSize(at: out.appendingPathComponent("page-001.png")))
        #expect(size.width > 50 && size.height > 80)
    }

    @Test func mergeJoinsPagesInOrder() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try ConverterFixtures.writePDF(to: dir.appendingPathComponent("a.pdf"), pages: 2)
        let second = try ConverterFixtures.writePDF(to: dir.appendingPathComponent("b.pdf"), pages: 3)
        let out = dir.appendingPathComponent("merged.pdf")
        try await converter.convert(ConverterFixtures.request([first, second], try target(PDFConverter.mergeTargetID), output: out), progress: { _ in })
        #expect(PDFDocument(url: out)?.pageCount == 5)
    }

    @Test func mergeNeedsAtLeastTwoInputs() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let only = try ConverterFixtures.writePDF(to: dir.appendingPathComponent("a.pdf"), pages: 1)
        let out = dir.appendingPathComponent("merged.pdf")
        await #expect(throws: ConversionError.self) {
            try await converter.convert(ConverterFixtures.request([only], try target(PDFConverter.mergeTargetID), output: out), progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func compressKeepsPageCount() async throws {
        guard FileManager.default.fileExists(atPath: PDFConverter.compressFilterURL.path) else { return }
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try ConverterFixtures.writePDF(to: dir.appendingPathComponent("a.pdf"), pages: 2)
        let out = dir.appendingPathComponent("small.pdf")
        try await converter.convert(ConverterFixtures.request([input], try target("pdf.compress"), output: out), progress: { _ in })
        #expect(PDFDocument(url: out)?.pageCount == 2)
    }

    @Test func corruptPDFFailsWithoutOutput() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("bad.pdf")
        try Data("%PDF-garbage".utf8).write(to: input)
        let out = dir.appendingPathComponent("bad")
        await #expect(throws: ConversionError.self) {
            try await converter.convert(ConverterFixtures.request([input], try target("pdf.png"), output: out), progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func imagesCombineIntoOnePagePerImagePDF() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let images = try ["1", "2"].map { try ConverterFixtures.writeImage(to: dir.appendingPathComponent("\($0).png")) }
        let combiner = ImagesToPDFConverter()
        let target = try #require(combiner.targets(for: images[0]).first)
        #expect(target.combinesInputs)
        let out = dir.appendingPathComponent("all.pdf")
        try await combiner.convert(ConverterFixtures.request(images, target, output: out), progress: { _ in })
        let document = try #require(PDFDocument(url: out))
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).width ?? 0 > 0)
    }
}
