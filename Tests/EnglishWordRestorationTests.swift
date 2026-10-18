import Testing
@testable import Xmac

@Suite struct EnglishWordRestorationTests {
    @Test func smartRestorationRestoresEnglishAndPreservesVietnamese() {
        #expect(EnglishWordRestoration.shouldRestore(raw: "push", composed: "púh"))
        #expect(EnglishWordRestoration.shouldRestore(raw: "PUSH", composed: "PÚH"))
        #expect(EnglishWordRestoration.shouldRestore(raw: "coffee", composed: "coffê"))
        #expect(EnglishWordRestoration.shouldRestore(raw: "software", composed: "sòftware"))
        #expect(EnglishWordRestoration.shouldRestore(raw: "meeting", composed: "mêting"))
        #expect(EnglishWordRestoration.shouldRestore(raw: "Xmac", composed: "Xmác"))
        #expect(!EnglishWordRestoration.shouldRestore(raw: "tieengs", composed: "tiếng"))
    }

    @Test func englishWordsWithInvalidVietnameseEndingsAreCandidates() {
        #expect(EnglishWordRestoration.isCandidate(raw: "push", composed: "púh"))
        #expect(EnglishWordRestoration.isCandidate(raw: "PUSH", composed: "PÚH"))
        #expect(EnglishWordRestoration.isCandidate(raw: "task", composed: "ták"))
        #expect(EnglishWordRestoration.isCandidate(raw: "coffee", composed: "coffê"))
        #expect(EnglishWordRestoration.isCandidate(raw: "address", composed: "ađress"))
    }

    @Test func vietnameseAndAmbiguousWordsArePreserved() {
        #expect(!EnglishWordRestoration.isCandidate(raw: "tieengs", composed: "tiếng"))
        #expect(!EnglishWordRestoration.isCandidate(raw: "Vieetj", composed: "Việt"))
        #expect(!EnglishWordRestoration.isCandidate(raw: "as", composed: "á"))
        #expect(!EnglishWordRestoration.isCandidate(raw: "hello", composed: "hello"))
        #expect(!EnglishWordRestoration.isCandidate(raw: "push1", composed: "púh1"))
    }

    @Test func vietnameseSyllableValidationCoversCommonStructures() {
        #expect(EnglishWordRestoration.isPlausibleVietnameseSyllable("tiếng"))
        #expect(EnglishWordRestoration.isPlausibleVietnameseSyllable("Việt"))
        #expect(EnglishWordRestoration.isPlausibleVietnameseSyllable("đường"))
        #expect(EnglishWordRestoration.isPlausibleVietnameseSyllable("quyền"))
        #expect(!EnglishWordRestoration.isPlausibleVietnameseSyllable("coffê"))
        #expect(!EnglishWordRestoration.isPlausibleVietnameseSyllable("sòftware"))
        #expect(!EnglishWordRestoration.isPlausibleVietnameseSyllable("mêting"))
    }

    @Test func telexEscapesAreNeverReinsertedAtTheBoundary() {
        let lexicon: Set<String> = ["push", "class", "ass", "as", "process", "server", "sever", "off", "of"]
        let isWord: (String) -> Bool = { lexicon.contains($0.lowercased()) }
        // "puss" escapes the tone, so the user meant "push", not "pussh".
        #expect(EnglishWordRestoration.restoration(raw: "pussh", composed: "push", isEnglishWord: isWord) == nil)
        #expect(EnglishWordRestoration.restoration(raw: "class", composed: "clas", isEnglishWord: isWord) == "class")
        #expect(EnglishWordRestoration.restoration(raw: "process", composed: "proces", isEnglishWord: isWord) == "process")
        #expect(EnglishWordRestoration.restoration(raw: "ass", composed: "as", isEnglishWord: isWord) == nil)
        #expect(EnglishWordRestoration.restoration(raw: "off", composed: "of", isEnglishWord: isWord) == nil)
        // A tone key cancelled mid-word is not an escape: "server" must survive.
        #expect(EnglishWordRestoration.restoration(raw: "server", composed: "sever", isEnglishWord: isWord) == "server")
    }

    @Test func invalidNucleiAndToneCodaPairsAreRestored() {
        #expect(EnglishWordRestoration.isCandidate(raw: "use", composed: "úe"))
        #expect(EnglishWordRestoration.isCandidate(raw: "case", composed: "cáe"))
        #expect(EnglishWordRestoration.isCandidate(raw: "house", composed: "hóue"))
        #expect(EnglishWordRestoration.isCandidate(raw: "text", composed: "tẽt"))
        #expect(EnglishWordRestoration.isCandidate(raw: "yes", composed: "ýe"))
    }

    @Test func realVietnameseSyllablesStayValid() {
        for word in ["người", "thuở", "khuya", "giữa", "gì", "xoong", "quốc", "oanh", "huỳnh", "kìa",
                     "yêu", "nghiêng", "xoăn", "ếch", "ăn", "khoẻ", "hoà", "thuý", "uống", "giếng"] {
            #expect(VietnameseSyllable.isValid(word), "\(word)")
        }
        for word in ["úe", "tẽt", "ă", "kan", "cé", "ghá", "anhh", "ủe", "ìch"] {
            #expect(!VietnameseSyllable.isValid(word), "\(word)")
        }
    }

    @Test func systemSpellCheckerRecognisesEnglishWords() {
        #expect(EnglishLexicon.contains("class"))
        #expect(EnglishLexicon.contains("Push"))
        #expect(!EnglishLexicon.contains("pussh"))
        #expect(!EnglishLexicon.contains("clas"))
    }
}
