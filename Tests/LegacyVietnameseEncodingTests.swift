import Foundation
import Testing
@testable import Xmac

@Suite struct LegacyVietnameseEncodingTests {

    @Test func tablesCoverAll134LettersWithUniqueCodes() {
        let rows = LegacyVietnameseTables.rows
        #expect(rows.count == 134)
        #expect(Set(rows.map(\.unicode)).count == 134)
        #expect(Set(rows.map(\.tcvn3)).count == 134)
        #expect(Set(rows.map(\.vni)).count == 134)
    }

    @Test func everyLetterRoundTripsThroughBothCharsets() {
        for row in LegacyVietnameseTables.rows {
            let expected = String(Unicode.Scalar(row.unicode)!)
            for (charset, code) in [(LegacyVietnameseCharset.tcvn3, row.tcvn3), (.vniWindows, row.vni)] {
                let bytes = code > 0xFF ? [UInt8(code >> 8), UInt8(code & 0xFF)] : [UInt8(code)]
                #expect(LegacyVietnameseEncoding.decode(Data(bytes), charset: charset) == expected)
            }
        }
    }

    @Test func tcvn3KnownWords() {
        #expect(LegacyVietnameseEncoding.convert("ViÖt Nam", from: .tcvn3) == "Việt Nam")
        #expect(LegacyVietnameseEncoding.convert("§µ N½ng", from: .tcvn3) == "Đà Nẵng")
        #expect(LegacyVietnameseEncoding.convert("Hµ Néi, 2024!", from: .tcvn3) == "Hà Nội, 2024!")
    }

    @Test func vniKnownWords() {
        #expect(LegacyVietnameseEncoding.convert("Vieät Nam", from: .vniWindows) == "Việt Nam")
        #expect(LegacyVietnameseEncoding.convert("Ñaø Naüng", from: .vniWindows) == "Đà Nẵng")
        #expect(LegacyVietnameseEncoding.convert("Haø Noäi", from: .vniWindows) == "Hà Nội")
    }

    @Test func uppercaseTonedLettersUseTwoBytes() {
        #expect(LegacyVietnameseEncoding.decode(Data([0x41, 0xB8, 0x4E, 0xA1]), charset: .tcvn3) == "ÁNĂ")
        #expect(LegacyVietnameseEncoding.convert("VIEÄT NAM", from: .vniWindows) == "VIỆT NAM")
        #expect(LegacyVietnameseEncoding.convert("ÑAØ NAÜNG", from: .vniWindows) == "ĐÀ NẴNG")
    }

    @Test func decodeFromRawBytesMatchesConvert() {
        let bytes = Data([0x56, 0x69, 0xD6, 0x74, 0x20, 0x4E, 0x61, 0x6D])
        #expect(LegacyVietnameseEncoding.decode(bytes, charset: .tcvn3) == "Việt Nam")
    }

    @Test func outputIsNFC() {
        let result = LegacyVietnameseEncoding.convert("ViÖt", from: .tcvn3)
        #expect(result.unicodeScalars.count == 4)
        #expect(result == result.precomposedStringWithCanonicalMapping)
    }

    @Test func asciiAndUnicodeTextIsUnchanged() {
        for charset in LegacyVietnameseCharset.allCases {
            #expect(LegacyVietnameseEncoding.convert("Hello, World 123", from: charset) == "Hello, World 123")
            #expect(LegacyVietnameseEncoding.convert("Việt Nam à á", from: charset) == "Việt Nam à á")
            #expect(LegacyVietnameseEncoding.convert("", from: charset) == "")
        }
    }

    @Test func unmappedHighScalarsPassThrough() {
        #expect(LegacyVietnameseEncoding.convert("Vieät — 😀", from: .vniWindows) == "Việt — 😀")
    }

    @Test func detectsEachCharset() {
        #expect(LegacyVietnameseEncoding.detect("ViÖt Nam") == .tcvn3)
        #expect(LegacyVietnameseEncoding.detect("Hµ Néi vµ §µ N½ng") == .tcvn3)
        #expect(LegacyVietnameseEncoding.detect("Vieät Nam") == .vniWindows)
        #expect(LegacyVietnameseEncoding.detect("Ñaø Naüng, Haø Noäi") == .vniWindows)
    }

    @Test func detectReturnsNilForUnicodeAsciiAndWestern() {
        #expect(LegacyVietnameseEncoding.detect("Việt Nam") == nil)
        #expect(LegacyVietnameseEncoding.detect("Hello world") == nil)
        #expect(LegacyVietnameseEncoding.detect("") == nil)
        #expect(LegacyVietnameseEncoding.detect("Café Zürich über Straße") == nil)
    }

    @Test func vniCapitalWithLowercaseMarkIsUppercased() {
        #expect(LegacyVietnameseEncoding.convert("Aù Eâ", from: .vniWindows) == "Á Ê")
        #expect(LegacyVietnameseEncoding.convert("Vieät", from: .vniWindows) == "Việt")
    }
}
