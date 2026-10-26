import Foundation

enum ConverterCLITargetResolver {
    /// Exact id first; then a unique output extension ("jpg", ".JPG"); then a unique title match.
    static func resolve(_ spec: String, among available: [ConversionTarget]) throws -> ConversionTarget {
        if let exact = available.first(where: { $0.id == spec }) { return exact }
        let key = spec.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var matches = available.filter { !$0.fileExtension.isEmpty && $0.fileExtension.lowercased() == key }
        if matches.isEmpty { matches = available.filter { $0.title.lowercased() == key } }
        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            let ids = available.map(\.id).joined(separator: ", ")
            throw ConverterCLIUsageError(message: "no target \"\(spec)\" for these files. Available: \(ids.isEmpty ? "none" : ids)")
        default:
            let ids = matches.map(\.id).joined(separator: ", ")
            throw ConverterCLIUsageError(message: "\"\(spec)\" is ambiguous; use one of: \(ids)")
        }
    }
}
