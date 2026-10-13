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

    @Test func vniTransformsVietnameseLettersAndTone() {
        #expect(type("d9", method: .vni) == "đ")
        #expect(type("a61", method: .vni) == "ấ")
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
