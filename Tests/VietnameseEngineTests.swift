import Testing
@testable import Xmac

@Suite struct VietnameseEngineTests {
    private let engine = VietnameseEngine.shared

    @Test func telexTransformsVietnameseLettersAndTone() {
        #expect(type("dd", method: .telex) == "đ")
        #expect(type("aas", method: .telex) == "ấ")
        #expect(type("tieengs", method: .telex) == "tiếng")
    }

    @Test func telexRemovesTone() {
        #expect(type("asz", method: .telex) == "a")
    }

    @Test func repeatedTelexKeysCancelTheConversionForLiteralEnglishText() {
        #expect(type("ass", method: .telex) == "as")
        #expect(type("aaa", method: .telex) == "aa")
        #expect(type("eee", method: .telex) == "ee")
        #expect(type("ooo", method: .telex) == "oo")
        #expect(type("ddd", method: .telex) == "dd")
        #expect(type("aww", method: .telex) == "aw")
        #expect(type("awws", method: .telex) == "áw")
    }

    @Test func telexWOnUOClusterProducesUHornOHorn() {
        #expect(type("nguowif", method: .telex) == "người")
        #expect(type("duowngf", method: .telex) == "dường")
        #expect(type("uwow", method: .telex) == "ươ")
        #expect(type("NGUOWI", method: .telex) == "NGƯƠI")
        #expect(type("quow", method: .telex) == "quơ")
        #expect(type("uoww", method: .telex) == "uow")
    }

    @Test func telexWAfterFinalConsonantShapesTheNucleus() {
        #expect(type("tangw", method: .telex) == "tăng")
        #expect(type("tangwj", method: .telex) == "tặng")
        #expect(type("tangjw", method: .telex) == "tặng")
        #expect(type("duongwf", method: .telex) == "dường")
        #expect(type("nguoiwf", method: .telex) == "người")
        #expect(type("hoangwf", method: .telex) == "hoằng")
        #expect(type("quangw", method: .telex) == "quăng")
        #expect(type("tungw", method: .telex) == "tưng")
        #expect(type("Tangw", method: .telex) == "Tăng")
    }

    @Test func secondFreeOrderWUndoesTheHorn() {
        #expect(type("tangww", method: .telex) == "tangw")
        #expect(type("tangwjw", method: .telex) == "tạngw")
    }

    @Test func freeOrderWKeepsNonSyllableEndingsLiteral() {
        #expect(type("tw", method: .telex) == "tw")
        #expect(type("tasw", method: .telex) == "tắ")
        #expect(type("bowl", method: .telex) == "bơl")
        #expect(type("tabw", method: .telex) == "tabw")
    }

    @Test func repeatedVNIKeyCancelsToneForLiteralInput() {
        #expect(type("a11", method: .vni) == "a1")
        #expect(type("a66", method: .vni) == "a6")
        #expect(type("u77", method: .vni) == "u7")
        #expect(type("a88", method: .vni) == "a8")
        #expect(type("d99", method: .vni) == "d9")
    }

    @Test func vniTransformsVietnameseLettersAndTone() {
        #expect(type("d9", method: .vni) == "đ")
        #expect(type("a61", method: .vni) == "ấ")
    }

    @Test func modernAndTraditionalOpenVowelPlacement() {
        #expect(type("hoaf", method: .telex) == "hòa")
        #expect(type("hoaf", method: .telex, modernOrthography: false) == "hoà")
        #expect(type("thuys", method: .telex) == "thúy")
        #expect(type("thuys", method: .telex, modernOrthography: false) == "thuý")
    }

    @Test func openDiphthongsAndGlidesUseCorrectToneVowel() {
        #expect(type("muas", method: .telex) == "múa")
        #expect(type("meos", method: .telex) == "méo")
        #expect(type("quaf", method: .telex) == "quà")
        #expect(type("gias", method: .telex) == "giá")
    }

    private func type(
        _ input: String,
        method: TypingMethod,
        modernOrthography: Bool = true
    ) -> String {
        input.reduce(into: "") { word, character in
            word = engine.processWord(
                currentWord: word,
                newChar: character,
                method: method,
                modernOrthography: modernOrthography
            ).transformed
        }
    }
}
