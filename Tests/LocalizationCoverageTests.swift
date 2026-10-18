import Foundation
import Testing

@Suite struct LocalizationCoverageTests {
    private static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func swiftSources() -> [URL] {
        let sources = projectRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private static func catalogKeys() throws -> Set<String> {
        let url = projectRoot.appendingPathComponent("Sources/LocalizationResources/en.lproj/Localizable.strings")
        guard let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Set(dictionary.keys)
    }

    /// Vietnamese (non-ASCII) literals passed to L10n.text / L10n.format / Text.
    private static func vietnameseLiterals(in source: String) throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: #"(?:L10n\.(?:text|format)|Text)\(\s*"((?:[^"\\]|\\.)*)""#)
        let range = NSRange(source.startIndex..., in: source)
        var found = Set<String>()
        for match in pattern.matches(in: source, range: range) {
            guard let literalRange = Range(match.range(at: 1), in: source) else { continue }
            let literal = String(source[literalRange])
            // Skip interpolated strings; they are not catalog keys.
            guard !literal.contains("\\("), literal.unicodeScalars.contains(where: { !$0.isASCII }) else { continue }
            found.insert(literal.replacingOccurrences(of: "\\\"", with: "\""))
        }
        return found
    }

    @Test func everyVietnameseLiteralHasAnEnglishTranslation() throws {
        let keys = try Self.catalogKeys()
        var missing = [String: String]()
        for file in Self.swiftSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for literal in try Self.vietnameseLiterals(in: source) where !keys.contains(literal) {
                missing[literal] = file.lastPathComponent
            }
        }
        let report = missing.sorted { $0.key < $1.key }.map { "\($0.key)  [\($0.value)]" }
        #expect(report.isEmpty, "Missing en.lproj keys:\n\(report.joined(separator: "\n"))")
    }
}
