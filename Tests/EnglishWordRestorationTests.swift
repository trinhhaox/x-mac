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
}
