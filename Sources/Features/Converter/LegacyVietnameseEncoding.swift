import Foundation

enum LegacyVietnameseCharset: String, CaseIterable {
    case tcvn3, vniWindows
}

/// TCVN3 (ABC) and VNI-Windows → Unicode. Legacy text is a byte stream; once a file was read as
/// windows-1252 / Latin-1 each byte is the scalar of the same value, so both entry points share one core.
enum LegacyVietnameseEncoding {
    /// Legacy code (one byte, or base letter + mark byte packed big-endian) → Unicode scalar.
    private static let letters: [LegacyVietnameseCharset: [UInt16: UInt16]] = Dictionary(
        uniqueKeysWithValues: LegacyVietnameseCharset.allCases.map { charset in
            (charset, Dictionary(uniqueKeysWithValues: LegacyVietnameseTables.rows.map {
                (charset == .tcvn3 ? $0.tcvn3 : $0.vni, $0.unicode)
            }))
        }
    )

    /// Vietnamese letters outside Latin-1 (ă, đ, ơ, ư, tone-marked vowels): present only in text that is already Unicode.
    private static let unicodeOnlyLetters = Set(LegacyVietnameseTables.rows.map { UInt32($0.unicode) }.filter { $0 > 0xFF })

    static func hasUnicodeOnlyLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { unicodeOnlyLetters.contains($0.value) }
    }

    /// Raw file bytes (as stored by legacy software) → NFC Unicode.
    static func decode(_ data: Data, charset: LegacyVietnameseCharset) -> String {
        convert(scalars: data.map { UInt32($0) }, charset: charset)
    }

    /// Text that was already decoded as windows-1252 / Latin-1 → NFC Unicode.
    /// Text that already holds Vietnamese-only Unicode letters is returned unchanged.
    static func convert(_ text: String, from charset: LegacyVietnameseCharset) -> String {
        hasUnicodeOnlyLetters(text) ? text : convert(scalars: text.unicodeScalars.map(\.value), charset: charset)
    }

    /// True when `second` is the mark byte that turns `first` into one letter (a pair spanning two runs must be re-joined).
    static func joins(_ first: UInt32, _ second: UInt32, charset: LegacyVietnameseCharset) -> Bool {
        pairLetter(first, second, charset: charset) != nil
    }

    private static func pairLetter(_ first: UInt32, _ second: UInt32, charset: LegacyVietnameseCharset) -> UInt32? {
        guard first <= 0xFF, second <= 0xFF, let table = letters[charset] else { return nil }
        if let letter = table[UInt16(first) << 8 | UInt16(second)] { return UInt32(letter) }
        // VNI also writes a capital's mark in its lowercase form ("Aù" for "Á").
        guard charset == .vniWindows, (0x41...0x5A).contains(first),
              let lower = table[UInt16(first + 0x20) << 8 | UInt16(second)],
              let scalar = Unicode.Scalar(UInt32(lower)) else { return nil }
        return String(Character(scalar)).uppercased().unicodeScalars.first?.value
    }

    /// Scalars above 0xFF are not legacy bytes and pass through; a pair is tried before a single byte.
    private static func convert(scalars: [UInt32], charset: LegacyVietnameseCharset) -> String {
        let table = letters[charset] ?? [:]
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let first = scalars[index]
            var mapped: UInt32?
            var consumed = 1
            if first <= 0xFF {
                if index + 1 < scalars.count, let pair = pairLetter(first, scalars[index + 1], charset: charset) {
                    mapped = pair
                    consumed = 2
                } else {
                    mapped = table[UInt16(first)].map(UInt32.init)
                }
            }
            if let scalar = Unicode.Scalar(mapped ?? first) {
                output.append(scalar)
            }
            index += consumed
        }
        return String(output).precomposedStringWithCanonicalMapping
    }
}
