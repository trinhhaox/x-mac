import AppKit
import os

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
    private static let cache = OSAllocatedUnfairLock(initialState: [String: Bool]())
    private static let cacheLimit = 2_000
    /// Common English words (especially coding/chat words matching Telex keys)
    /// checked instantly in-memory without waiting for the main thread.
    private static let commonWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her",
        "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "man", "new",
        "now", "old", "see", "two", "way", "who", "boy", "did", "its", "let", "put", "say",
        "she", "too", "use", "push", "test", "text", "type", "case", "code", "user", "view",
        "file", "open", "save", "load", "send", "post", "date", "time", "name", "help", "home",
        "page", "line", "link", "list", "item", "icon", "menu", "mode", "pass", "fail", "true",
        "null", "func", "init", "main", "play", "stop", "wait", "read", "free", "full", "size",
        "data", "form", "card", "font", "edit", "copy", "move", "find", "done", "info", "show",
        "hide", "next", "back", "task", "step", "auto", "self", "call", "rate", "lock", "safe",
        "base", "disk", "port", "host", "path", "peer", "rule", "cert", "sync", "drop", "tool",
        "auth", "hash", "salt", "team", "site", "chat", "mail", "blog", "feed", "meta", "fast",
        "slow", "best", "good", "nice", "cool", "well", "real", "easy", "hard", "fine", "sure",
        "more", "most", "less", "last", "left", "right", "down", "long", "even", "much", "also",
        "only", "just", "like", "some", "them", "then", "they", "this", "that", "with", "from",
        "have", "here", "make", "were", "what", "when", "know", "take", "come", "look", "give",
        "want", "year", "work", "feel", "seem", "hand", "high", "keep", "hold", "tell", "turn",
        "hear", "talk", "live", "server", "class", "off", "as", "is", "at", "to", "in", "on"
    ]

    /// How long the event tap thread may wait for the main thread. A busy main
    /// thread must not stall typing; reduced to 10ms to keep tap thread responsive.
    static let tapThreadTimeout: DispatchTimeInterval = .milliseconds(10)

    static func contains(_ word: String) -> Bool {
        let key = word.lowercased()
        if commonWords.contains(key) { return true }
        if let cached = cache.withLock({ $0[key] }) { return cached }
        if Thread.isMainThread { return lookUp(key) }

        // NSSpellChecker is AppKit API: ask it on the main thread.
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            _ = lookUp(key)
            done.signal()
        }
        let result = TypingLatencyMonitor.shared.measureSpellWait {
            done.wait(timeout: .now() + tapThreadTimeout)
        }
        guard result == .success else { return false }
        return cache.withLock { $0[key] } ?? false
    }

    private static func lookUp(_ key: String) -> Bool {
        let misspelled = NSSpellChecker.shared.checkSpelling(
            of: key,
            startingAt: 0,
            language: "en",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        let known = misspelled.location == NSNotFound
        cache.withLock { cache in
            // Drop half rather than everything, so common words stay warm.
            if cache.count >= cacheLimit {
                cache = Dictionary(uniqueKeysWithValues: cache.prefix(cacheLimit / 2).map { ($0.key, $0.value) })
            }
            cache[key] = known
        }
        return known
    }

    /// Loads the dictionary off the typing path so the first lookup is fast.
    static func warmUp() {
        _ = contains("warm")
    }
}
