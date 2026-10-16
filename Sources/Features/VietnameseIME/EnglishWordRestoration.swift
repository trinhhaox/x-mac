import Foundation

/// Restores a Latin word when Telex/VNI produced text that cannot be a
/// Vietnamese syllable. This keeps mixed Vietnamese-English sentences usable
/// without guessing on genuinely ambiguous inputs such as `as` -> `á`.
enum EnglishWordRestoration {
    static func shouldRestore(raw: String, composed: String) -> Bool {
        // Structural validation is deterministic and also covers product names,
        // technical terms and proper nouns absent from the system dictionary.
        isCandidate(raw: raw, composed: composed)
    }

    static func isCandidate(raw: String, composed: String) -> Bool {
        guard raw != composed, raw.count >= 3,
              raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) })
        else { return false }

        return !isPlausibleVietnameseSyllable(composed)
    }

    static func isPlausibleVietnameseSyllable(_ word: String) -> Bool {
        let normalized = word
            .precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .lowercased()
        guard !normalized.isEmpty else { return false }

        let vietnameseLetters = Set("abcdđeghiklmnopqrstuvxy")
        guard normalized.allSatisfy({ vietnameseLetters.contains($0) }) else { return false }

        let vowels = Set("aeiouy")
        let onsets = ["ngh", "ch", "gh", "gi", "kh", "ng", "nh", "ph", "qu", "th", "tr",
                      "b", "c", "d", "đ", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "x", ""]
        let codas: Set<String> = ["", "c", "ch", "m", "n", "ng", "nh", "p", "t"]

        guard let onset = onsets.first(where: { normalized.hasPrefix($0) }) else { return false }
        var remainder = String(normalized.dropFirst(onset.count))
        guard !remainder.isEmpty else { return false }

        var nucleus = ""
        while let first = remainder.first, vowels.contains(first) {
            nucleus.append(first)
            remainder.removeFirst()
        }

        guard !nucleus.isEmpty, nucleus.count <= 3 else { return false }
        return codas.contains(remainder)
    }
}
