import Foundation
import Testing
@testable import Xmac

@Suite struct PageRangeParserTests {
    private func pages(_ text: String, count: Int = 10) throws -> [Int] {
        try PageRangeParser.pageIndices(text, pageCount: count)
    }

    @Test func parsesRangesSinglesAndOpenEnd() throws {
        #expect(try pages("1-3, 5, 8-") == [0, 1, 2, 4, 7, 8, 9])
    }

    @Test func ignoresSpacesAndEmptyPieces() throws {
        #expect(try pages(" 2 - 3 ,, 5 ") == [1, 2, 4])
    }

    @Test func keepsWrittenOrderAndDropsDuplicates() throws {
        #expect(try pages("5, 1-3, 2-6") == [4, 0, 1, 2, 3, 5])
    }

    @Test func clampsToPageCount() throws {
        #expect(try pages("3-99", count: 5) == [2, 3, 4])
        #expect(try pages("2, 40", count: 5) == [1])
    }

    @Test func rejectsEverythingBeyondPageCount() {
        #expect(throws: PageRangeError.outOfRange) { try pages("20-30", count: 5) }
    }

    @Test func rejectsEmptyInput() {
        #expect(throws: PageRangeError.empty) { try pages("") }
        #expect(throws: PageRangeError.empty) { try pages("  , ") }
    }

    @Test(arguments: ["0", "0-3", "5-3", "abc", "1-2-3", "-3", "1.5", "٣"])
    func rejectsInvalidSyntax(_ text: String) {
        #expect(throws: PageRangeError.self) { try pages(text) }
        #expect(PageRangeParser.validationMessage(text) != nil)
    }

    @Test func validationAcceptsGoodSyntaxWithoutPageCount() {
        #expect(PageRangeParser.validationMessage("1-3, 5, 8-") == nil)
    }

    @Test func oldSavedPresetWithoutRangeStillDecodes() throws {
        let json = Data(#"{"imageQuality":0.7,"pdfRenderDPI":200}"#.utf8)
        let preset = try JSONDecoder().decode(ConversionPreset.self, from: json)
        #expect(preset.pdfPageRange == nil && preset.pdfRenderDPI == 200)
    }
}
