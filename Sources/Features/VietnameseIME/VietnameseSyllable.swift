import Foundation

/// Structural validator for a single Vietnamese syllable (onset + nucleus +
/// coda + tone). It decides whether Telex/VNI output can be real Vietnamese,
/// so English words such as "use" ("úe") or "text" ("tẽt") are restored.
enum VietnameseSyllable {
    private static let toneMarks: Set<UInt32> = [0x0300, 0x0301, 0x0303, 0x0309, 0x0323]
    private static let stopToneMarks: Set<UInt32> = [0x0301, 0x0323] // sắc, nặng
    private static let letters = Set("abcdđeghiklmnopqrstuvxyăâêôơư")
    private static let vowels = Set("aăâeêioôơuưy")
    private static let onsets = ["ngh", "gh", "gi", "kh", "ng", "nh", "ph", "qu", "th", "tr", "ch",
                                 "b", "c", "d", "đ", "g", "h", "k", "l", "m", "n", "p", "r", "s",
                                 "t", "v", "x", ""]
    private static let codas: Set<String> = ["", "c", "ch", "m", "n", "ng", "nh", "p", "t"]
    private static let stopCodas: Set<String> = ["c", "ch", "p", "t"]

    private static let openOnlyNuclei: Set<String> = [
        "ai", "ao", "au", "ay", "âu", "ây", "eo", "êu", "ia", "iu", "oi", "ôi", "ơi", "ua", "ui",
        "ưa", "ưi", "ưu", "iêu", "yêu", "uôi", "ươi", "ươu", "oai", "oao", "oay", "oeo", "uây",
        "uya", "uyu", "uơ"
    ]
    private static let closedOnlyNuclei: Set<String> = ["ă", "â", "iê", "yê", "uô", "ươ", "uyê", "oă", "uâ", "oo"]
    private static let freeNuclei: Set<String> = [
        "a", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y", "oa", "oe", "uê", "uy"
    ]
    /// "ch"/"nh" only follow these nuclei: anh, ếch, ính, oanh, huếch, huỳnh.
    private static let palatalCodaNuclei: Set<String> = ["a", "ê", "i", "y", "oa", "uê", "uy"]

    static func isValid(_ word: String) -> Bool {
        guard let (base, tone) = splitTone(word.lowercased()), !base.isEmpty,
              base.allSatisfy({ letters.contains($0) }) else { return false }

        return onsets.contains { onset in
            base.hasPrefix(onset) && isValidRhyme(
                String(base.dropFirst(onset.count)),
                onset: onset,
                tone: tone
            )
        }
    }

    /// Separates the tone mark from the shaped letters: "đường" -> ("đương", huyền).
    private static func splitTone(_ word: String) -> (String, UInt32?)? {
        var tone: UInt32?
        var scalars = String.UnicodeScalarView()
        for scalar in word.decomposedStringWithCanonicalMapping.unicodeScalars {
            if toneMarks.contains(scalar.value) {
                guard tone == nil else { return nil } // two tones
                tone = scalar.value
            } else {
                scalars.append(scalar)
            }
        }
        return (String(scalars).precomposedStringWithCanonicalMapping, tone)
    }

    private static func isValidRhyme(_ rhyme: String, onset: String, tone: UInt32?) -> Bool {
        let nucleus = String(rhyme.prefix { vowels.contains($0) })
        let coda = String(rhyme.dropFirst(nucleus.count))
        guard !nucleus.isEmpty, codas.contains(coda) else { return false }

        if openOnlyNuclei.contains(nucleus) {
            guard coda.isEmpty else { return false }
        } else if closedOnlyNuclei.contains(nucleus) {
            guard !coda.isEmpty else { return false }
        } else if !freeNuclei.contains(nucleus) {
            return false
        }

        if (coda == "ch" || coda == "nh") && !palatalCodaNuclei.contains(nucleus) { return false }
        if stopCodas.contains(coda), let tone, !stopToneMarks.contains(tone) { return false }

        // Spelling rules: k/gh/ngh only before front vowels, c never before them.
        let startsFront = nucleus.first.map { "eêiy".contains($0) } ?? false
        if ["k", "gh", "ngh"].contains(onset) && !startsFront { return false }
        if onset == "c" && startsFront { return false }
        return true
    }
}
