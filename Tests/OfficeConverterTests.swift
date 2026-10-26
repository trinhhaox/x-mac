import Testing
import Foundation
@testable import Xmac

@Suite struct OfficeConverterTests {
    private let converter = OfficeConverter()

    @Test func offersPdfPlusCounterpartFormats() {
        func ids(_ name: String) -> [String] { converter.targets(for: URL(fileURLWithPath: "/x/\(name)")).map(\.id) }
        #expect(ids("a.doc") == ["office.pdf", "office.docx"])
        #expect(ids("a.docx") == ["office.pdf", "office.doc"])
        #expect(ids("a.XLSX") == ["office.pdf", "office.xls"])
        #expect(ids("a.ods") == ["office.pdf", "office.xlsx"])
        #expect(ids("a.odp") == ["office.pdf", "office.pptx"])
        #expect(ids("a.pages") == ["office.pdf"])
        #expect(ids("a.png").isEmpty)
        #expect(converter.requiredTool == .soffice)
    }

    @Test func missingBinaryThrowsToolMissing() async throws {
        let suite = "OfficeConverterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/nonexistent/soffice", forKey: ExternalTool.soffice.overrideDefaultsKey)
        let missing = OfficeConverter(locator: BinaryLocator(defaults: defaults))
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let request = try ConverterToolTestSupport.request(
            missing, input: dir.appendingPathComponent("a.docx"), targetID: "office.pdf", outputIn: dir)
        await #expect(throws: ConversionError.toolMissing(.soffice)) { try await missing.convert(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: request.outputURL.path))
    }

    @Test(.enabled(if: BinaryLocator().locate(.soffice) != nil))
    func convertsCsvToPdf() async throws {
        let dir = try ConverterToolTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("table.csv")
        try Data("a,b\n1,2\n".utf8).write(to: source)
        let request = try ConverterToolTestSupport.request(converter, input: source, targetID: "office.pdf", outputIn: dir)
        try await converter.convert(request) { _ in }
        #expect(try Data(contentsOf: request.outputURL).prefix(4) == Data("%PDF".utf8))
    }
}
