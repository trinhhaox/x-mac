import Foundation

enum PageRangeError: Error, Equatable {
    case empty
    case invalid(String)
    case outOfRange

    var message: String {
        switch self {
        case .empty: return L10n.text("Chưa nhập khoảng trang")
        case .invalid(let part): return L10n.format("Khoảng trang không hợp lệ: %@", part)
        case .outOfRange: return L10n.text("Khoảng trang vượt quá số trang của tệp")
        }
    }
}

/// Parses 1-based page ranges such as "1-3, 5, 8-" (an open end means "to the last page").
/// Result indices are 0-based, in the order written, with duplicates dropped (first mention wins).
enum PageRangeParser {
    private struct Part {
        let first: Int
        /// nil = through the last page.
        let last: Int?
    }

    /// Syntax-only check, for live feedback before a page count is known. Nil when valid.
    static func validationMessage(_ text: String) -> String? {
        do { _ = try parts(text) } catch let error as PageRangeError { return error.message } catch { return nil }
        return nil
    }

    /// Pages beyond `pageCount` are clamped away; throws `.outOfRange` when nothing is left.
    static func pageIndices(_ text: String, pageCount: Int) throws -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for part in try parts(text) {
            let last = min(part.last ?? pageCount, pageCount)
            guard part.first <= last else { continue }
            for page in part.first...last where seen.insert(page).inserted { result.append(page - 1) }
        }
        guard !result.isEmpty else { throw PageRangeError.outOfRange }
        return result
    }

    private static func parts(_ text: String) throws -> [Part] {
        let pieces = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.filter { !$0.isWhitespace } }
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else { throw PageRangeError.empty }
        return try pieces.map { try part(String($0)) }
    }

    private static func part(_ piece: String) throws -> Part {
        let bounds = piece.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard bounds.count <= 2, let first = pageNumber(bounds[0]) else { throw PageRangeError.invalid(piece) }
        guard bounds.count == 2 else { return Part(first: first, last: first) }
        if bounds[1].isEmpty { return Part(first: first, last: nil) }
        guard let last = pageNumber(bounds[1]), last >= first else { throw PageRangeError.invalid(piece) }
        return Part(first: first, last: last)
    }

    private static func pageNumber(_ text: String) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), value >= 1 else { return nil }
        return value
    }
}
