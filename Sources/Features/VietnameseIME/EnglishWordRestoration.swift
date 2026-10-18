import AppKit

/// Decides what a word should become at a word boundary in Vietnamese mode,
/// so mixed Vietnamese-English sentences stay usable without guessing on
/// genuinely ambiguous inputs such as `as` -> `á`.
enum EnglishWordRestoration {
    /// Returns the text that should replace `composed`, or nil to keep it.
    ///
    /// - Composed text with Vietnamese letters is restored to the raw keys only
    ///   when it cannot be a Vietnamese syllable ("púh" -> "push").
    /// - Plain Latin composed text only exists after Telex escapes ("pussh" ->
    ///   "push", "class" -> "clas", "server" -> "sever"). The raw keys win only
    ///   when they form an English word, so an escape typed on purpose is never
    ///   re-inserted. A doubled key at the very end ("ass" -> "as", "off" -> "of")
    ///   is the standard way to type such a word, so it is kept when the result
    ///   is itself English.
    static func restoration(
        raw: String,
        composed: String,
        isEnglishWord: (String) -> Bool = EnglishLexicon.contains
    ) -> String? {
        guard raw != composed, raw.count >= 3,
              raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) })
        else { return nil }

        if composed.utf8.allSatisfy({ $0 < 128 }) {
            guard isEnglishWord(raw) else { return nil }
            if isTrailingEscape(raw: raw, composed: composed), isEnglishWord(composed) { return nil }
            return raw
        }
        return isPlausibleVietnameseSyllable(composed) ? nil : raw
    }

    private static func isTrailingEscape(raw: String, composed: String) -> Bool {
        let keys = Array(raw.lowercased())
        return keys.count >= 2 && keys[keys.count - 1] == keys[keys.count - 2]
            && String(raw.dropLast()) == composed
    }

    static func shouldRestore(raw: String, composed: String) -> Bool {
        restoration(raw: raw, composed: composed) != nil
    }

    static func isCandidate(raw: String, composed: String) -> Bool {
        restoration(raw: raw, composed: composed, isEnglishWord: { _ in false }) != nil
    }

    static func isPlausibleVietnameseSyllable(_ word: String) -> Bool {
        VietnameseSyllable.isValid(word)
    }
}

/// English word lookup backed by the system spell checker. Only consulted for
/// Telex escapes at a word boundary, and cached, so the event tap stays fast.
enum EnglishLexicon {
    private static var cache: [String: Bool] = [:]

    static func contains(_ word: String) -> Bool {
        let key = word.lowercased()
        if let cached = cache[key] { return cached }
        let misspelled = NSSpellChecker.shared.checkSpelling(
            of: key,
            startingAt: 0,
            language: "en",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        let known = misspelled.location == NSNotFound
        if cache.count > 2_000 { cache.removeAll() }
        cache[key] = known
        return known
    }

    /// Loads the dictionary off the typing path so the first lookup is fast.
    static func warmUp() {
        _ = contains("warm")
    }
}
