import AppKit

/// Restore dictionary-recognized English words only when Telex produced an
/// impossible Vietnamese ending. Ambiguous words such as "as" remain Vietnamese.
enum EnglishWordRestoration {
    static func shouldRestore(raw: String, composed: String) -> Bool {
        guard isCandidate(raw: raw, composed: composed) else { return false }
        let range = NSSpellChecker.shared.checkSpelling(
            of: raw.lowercased(), startingAt: 0, language: "en_US",
            wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound
    }

    static func isCandidate(raw: String, composed: String) -> Bool {
        guard raw != composed, raw.count >= 3,
              raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) })
        else { return false }

        let plain = composed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
        let vowels = Set("aeiouy")
        guard let lastVowel = plain.lastIndex(where: { vowels.contains($0) }) else { return false }
        let ending = String(plain[plain.index(after: lastVowel)...])
        return !["", "c", "ch", "m", "n", "ng", "nh", "p", "t"].contains(ending)
    }
}
