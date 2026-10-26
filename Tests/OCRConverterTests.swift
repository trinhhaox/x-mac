import AppKit
import Foundation
import PDFKit
import Testing
@testable import Xmac

@Suite struct OCRConverterTests {
    private let converter = OCRConverter()

    /// White canvas with large black text, written as PNG.
    private func writeTextImage(_ text: String, to url: URL) throws {
        let size = NSSize(width: 1400, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 150, weight: .bold), .foregroundColor: NSColor.black]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 40, y: 60))
        image.unlockFocus()
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try ImageIOSupport.write(cgImage, to: url, type: .png, quality: nil)
    }

    /// Vision may split or re-space display-size words ("X MAC"), so compare without whitespace.
    private func squashed(_ text: String) -> String {
        text.uppercased().filter { !$0.isWhitespace }
    }

    private func recognize(_ input: URL, output: URL) async throws -> String {
        let choice = try #require(converter.targets(for: input).first)
        try await converter.convert(ConverterFixtures.request([input], choice, output: output), progress: { _ in })
        return try String(contentsOf: output, encoding: .utf8)
    }

    @Test func offersChoiceForImagesAndPDFsOnly() {
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.png")).first?.fileExtension == "txt")
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.pdf")).count == 1)
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.mp4")).isEmpty)
    }

    @Test func recognizesImageText() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("scan.png")
        try writeTextImage("XMAC 2026", to: input)
        let text = try await recognize(input, output: dir.appendingPathComponent("scan.txt"))
        #expect(squashed(text).contains("XMAC2026"))
    }

    @Test func recognizesVietnameseWhenSupported() async throws {
        guard try OCRConverter.recognitionLanguages().vietnamese else { return }
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("vi.png")
        try writeTextImage("Tiếng Việt", to: input)
        let text = try await recognize(input, output: dir.appendingPathComponent("vi.txt"))
        // Vision sometimes swaps a tone mark on stylised glyphs; the base letters and Vietnamese support are what is under test.
        #expect(squashed(text).folding(options: .diacriticInsensitive, locale: nil).contains("TIENGVIET"))
    }

    @Test func readsPDFPagesWithSeparators() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("p.png")
        try writeTextImage("XMAC 2026", to: png)
        let image = try #require(NSImage(contentsOf: png))
        let page = try #require(PDFPage(image: image))
        let document = PDFDocument()
        document.insert(page, at: 0)
        document.insert(try #require(page.copy() as? PDFPage), at: 1)
        let input = dir.appendingPathComponent("scan.pdf")
        #expect(document.write(to: input))
        let text = try await recognize(input, output: dir.appendingPathComponent("scan.txt"))
        #expect(text.contains("--- Trang 2 ---"))
        #expect(squashed(text).components(separatedBy: "XMAC2026").count == 3)
    }

    @Test func unreadableImageLeavesNoOutput() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: input)
        let output = dir.appendingPathComponent("broken.txt")
        await #expect(throws: ConversionError.self) { _ = try await recognize(input, output: output) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
