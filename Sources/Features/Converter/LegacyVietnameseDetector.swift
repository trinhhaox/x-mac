import Foundation

extension LegacyVietnameseEncoding {
    private static let validNuclei: Set<String> = [
        "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        "ai", "ao", "au", "âu", "ay", "ây", "eo", "êu", "ia", "iê", "iu", "oa", "oă", "oe", "oi", "ôi", "ơi",
        "ua", "uâ", "uê", "ui", "uô", "uơ", "ưa", "ưi", "ưu", "ươ", "ya", "yê",
        "iêu", "yêu", "oai", "oay", "oeo", "uây", "uôi", "ươi", "ươu", "uya", "uyê", "uyu"
    ]
    private static let initials: Set<String> = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh", "nh",
        "p", "ph", "q", "qu", "r", "s", "t", "th", "tr", "v", "x"
    ]
    private static let finals: Set<String> = ["", "c", "ch", "m", "n", "ng", "nh", "p", "t"]
    private static let toneMarks: Set<UInt32> = [0x0300, 0x0301, 0x0303, 0x0309, 0x0323]
    private static let vowels = Set("aăâeêioôơuưy")

    /// Guesses which legacy charset `text` (read as windows-1252 / Latin-1) is in, or nil for Unicode / plain ASCII /
    /// Western text. Words with high characters are decoded both ways; the charset whose output forms the most valid
    /// Vietnamese syllables wins, and only when at least 80 % of those words are valid.
    static func detect(_ text: String) -> LegacyVietnameseCharset? {
        guard !hasUnicodeOnlyLetters(text) else { return nil }
        let words = highWords(in: text)
        guard !words.isEmpty else { return nil }
        let scored = LegacyVietnameseCharset.allCases.map { charset -> (LegacyVietnameseCharset, valid: Int) in
            (charset, words.filter { isVietnameseSyllable(convert($0, from: charset)) }.count)
        }
        guard let best = scored.max(by: { $0.valid < $1.valid }), best.valid > 0,
              Double(best.valid) >= 0.8 * Double(words.count),
              scored.filter({ $0.valid == best.valid }).count == 1 else { return nil }
        return best.0
    }

    /// Maximal runs of ASCII letters and Latin-1 symbols/letters that contain at least one non-ASCII character.
    private static func highWords(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var hasHigh = false
        func flush() {
            if hasHigh { words.append(current) }
            current = ""
            hasHigh = false
        }
        for scalar in text.unicodeScalars {
            if scalar.isASCII, scalar.properties.isAlphabetic {
                current.unicodeScalars.append(scalar)
            } else if (0xA1...0xFF).contains(scalar.value) {
                current.unicodeScalars.append(scalar)
                hasHigh = true
            } else {
                flush()
            }
        }
        flush()
        return words
    }

    /// Initial + nucleus + final shape of one Vietnamese syllable, ignoring tone marks. Rejects stray symbols.
    private static func isVietnameseSyllable(_ word: String) -> Bool {
        var tones = 0
        var stripped = String.UnicodeScalarView()
        for scalar in word.decomposedStringWithCanonicalMapping.unicodeScalars {
            if toneMarks.contains(scalar.value) { tones += 1 } else { stripped.append(scalar) }
        }
        let letters = Array(String(stripped).precomposedStringWithCanonicalMapping.lowercased())
        guard tones <= 1, !letters.isEmpty, letters.allSatisfy({ vowels.contains($0) || $0.isASCII && $0.isLetter || $0 == "đ" }) else {
            return false
        }
        guard let start = letters.firstIndex(where: vowels.contains) else { return false }
        let tail = letters[start...]
        let nucleusEnd = tail.firstIndex { !vowels.contains($0) } ?? letters.endIndex
        let initial = String(letters[..<start])
        let nucleus = String(letters[start..<nucleusEnd])
        let final = String(letters[nucleusEnd...])
        return initials.contains(initial) && validNuclei.contains(nucleus) && finals.contains(final)
    }
}
