import Foundation
import Testing
@testable import Xmac

@Suite struct FileSearchEngineTests {
    @Test func parsesFSearchInspiredFiltersAndModes() {
        let expression = FileSearchExpression.parse("\"kế hoạch quý\" ^bao-cao final$ !draft ext:pdf,docx type:document mtime:<7d")

        #expect(expression.terms == [
            FileSearchTerm(value: "kế hoạch quý", mode: .contains, excluded: false),
            FileSearchTerm(value: "bao-cao", mode: .prefix, excluded: false),
            FileSearchTerm(value: "final", mode: .suffix, excluded: false),
            FileSearchTerm(value: "draft", mode: .contains, excluded: true)
        ])
        #expect(expression.extensions == ["docx", "pdf"])
        #expect(expression.kind == .documents)
        #expect(expression.modifiedWithinDays == 7)
    }

    @Test func rankingKeepsOldExactMatchesBeyondTheRecencyWindow() {
        func result(_ name: String, daysOld: Double) -> FileSearchResult {
            FileSearchResult(path: "/tmp/\(name)", name: name, kind: "Tệp", size: 0,
                             modifiedAt: Date().addingTimeInterval(-daysOld * 86_400), isDirectory: false)
        }
        // 300 recent partial matches, then one very old exact match that a recency cut-off would drop.
        var items = (0..<300).map { result("report-\($0).txt", daysOld: 0) }
        items.append(result("report", daysOld: 400))
        let ranked = FileSearchEngine.rank(items, expression: FileSearchExpression.parse("'report"), limit: 200)
        #expect(ranked.count == 200)
        #expect(ranked.first?.name == "report")
    }

    @Test func exactAndEmptyQueriesAreHandled() {
        let exact = FileSearchExpression.parse("'README.md")
        #expect(exact.terms == [FileSearchTerm(value: "README.md", mode: .exact, excluded: false)])
        #expect(!exact.isEmpty)
        #expect(FileSearchExpression.parse("   ").isEmpty)
    }

    @Test func unsafeOrUnknownFiltersStayPlainSearchTerms() {
        let expression = FileSearchExpression.parse("type:unknown size:>5mb mtime:<oops")
        #expect(expression.kind == nil)
        #expect(expression.terms.map(\.value) == ["size:>5mb", "mtime:<oops"])
    }

    @Test func predicateUsesOnlyArgumentSubstitution() {
        let expression = FileSearchExpression.parse("\"report' OR 1 == 1\" ext:pdf !secret")
        let predicate = FileSearchEngine.predicate(
            for: expression,
            selectedKind: .documents,
            includeContents: true,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let format = predicate.predicateFormat
        #expect(format.contains("kMDItemFSName"))
        #expect(format.contains("kMDItemTextContent"))
        #expect(format.contains("kMDItemContentTypeTree"))
        #expect(format.contains("report' OR 1 == 1"))
        #expect(expression.terms.count == 2)
    }

    @Test func singleConditionsAreNotWrappedInInvalidMetadataCompounds() {
        let namePredicate = FileSearchEngine.predicate(
            for: FileSearchExpression.parse("README"),
            selectedKind: .all,
            includeContents: false
        )
        let extensionPredicate = FileSearchEngine.predicate(
            for: FileSearchExpression.parse("ext:md"),
            selectedKind: .all,
            includeContents: false
        )
        #expect(!(namePredicate is NSCompoundPredicate))
        #expect(!(extensionPredicate is NSCompoundPredicate))
    }
}
