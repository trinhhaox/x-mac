import Foundation

/// A legacy Vietnamese Word font: ".Vn*" (TCVN3) or "VNI-*", and the Unicode font that replaces it.
struct LegacyVietnameseFont {
    let charset: LegacyVietnameseCharset
    let replacement: String
    /// ".VnTimeH"-style fonts draw lowercase codes as capitals, so decoded text must be uppercased.
    let isAllCaps: Bool

    init?(name: String) {
        let lower = name.lowercased()
        if lower.hasPrefix(".vn") {
            charset = .tcvn3
            isAllCaps = name.hasSuffix("H")
        } else if lower.hasPrefix("vni-") {
            charset = .vniWindows
            isAllCaps = false
        } else {
            return nil
        }
        replacement = lower.contains("arial") || lower.contains("helve") ? "Arial" : "Times New Roman"
    }

    func unicode(from text: String) -> String {
        let converted = LegacyVietnameseEncoding.convert(text, from: charset)
        return isAllCaps ? converted.uppercased() : converted
    }
}
