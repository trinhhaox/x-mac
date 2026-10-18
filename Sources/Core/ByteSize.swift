import Foundation

/// Byte sizes for display. Foundation spells zero as "Zero KB", an English word
/// in a Vietnamese UI; numeric formatting keeps it "0 KB" in every language.
enum ByteSize {
    static func string(_ bytes: Int64, countStyle: ByteCountFormatter.CountStyle = .file) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = countStyle
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
