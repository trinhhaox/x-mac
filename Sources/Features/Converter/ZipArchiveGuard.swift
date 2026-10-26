import Foundation

/// Pre-extraction checks for untrusted zips (EPUB, KMZ): unsafe paths, entry count and declared unpacked size.
enum ZipArchiveGuard {
    static let maxUncompressedBytes = 512 << 20
    static let maxEntries = 10_000
    private static let zipinfo = URL(fileURLWithPath: "/usr/bin/zipinfo")

    static func validate(_ archive: URL) async throws {
        let names = try await ConverterWorkspace.run(zipinfo, ["-1", archive.path], timeout: 60)
        let summary = try await ConverterWorkspace.run(zipinfo, ["-t", archive.path], timeout: 60)
        try check(listing: String(decoding: names.stdout, as: UTF8.self), summary: String(decoding: summary.stdout, as: UTF8.self))
    }

    static func check(listing: String, summary: String) throws {
        if let unsafe = ArchiveConverter.unsafeEntries(in: listing).first {
            throw ConversionError.failed("Unsafe archive entry: \(unsafe)")
        }
        let entries = listing.split(whereSeparator: \.isNewline).count
        guard entries <= maxEntries, let bytes = uncompressedBytes(in: summary), bytes <= maxUncompressedBytes else {
            throw ConversionError.failed("Archive is too large to unpack safely")
        }
    }

    /// Parses zipinfo's "N files, B bytes uncompressed, …" line; nil when absent or not representable.
    static func uncompressedBytes(in summary: String) -> Int? {
        guard let range = summary.range(of: #"\d+ bytes uncompressed"#, options: .regularExpression) else { return nil }
        return Int(summary[range].prefix { $0.isNumber })
    }
}
