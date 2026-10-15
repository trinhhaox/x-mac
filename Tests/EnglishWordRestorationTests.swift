import Testing
@testable import Xmac

@Suite struct EnglishWordRestorationTests {
    @MainActor @Test func dictionaryRestoresPushAndPreservesVietnamese() {
        #expect(EnglishWordRestoration.shouldRestore(raw: "push", composed: "púh"))
        #expect(EnglishWordRestoration.shouldRestore(raw: "PUSH", composed: "PÚH"))
        #expect(!EnglishWordRestoration.shouldRestore(raw: "tieengs", composed: "tiếng"))
    }

    @Test func englishWordsWithInvalidVietnameseEndingsAreCandidates() {
        #expect(EnglishWordRestoration.isCandidate(raw: "push", composed: "púh"))
        #expect(EnglishWordRestoration.isCandidate(raw: "PUSH", composed: "PÚH"))
        #expect(EnglishWordRestoration.isCandidate(raw: "task", composed: "ták"))
    }

    @Test func vietnameseAndAmbiguousWordsArePreserved() {
        #expect(!EnglishWordRestoration.isCandidate(raw: "tieengs", composed: "tiếng"))
        #expect(!EnglishWordRestoration.isCandidate(raw: "Vieetj", composed: "Việt"))
        #expect(!EnglishWordRestoration.isCandidate(raw: "as", composed: "á"))
        #expect(!EnglishWordRestoration.isCandidate(raw: "hello", composed: "hello"))
        #expect(!EnglishWordRestoration.isCandidate(raw: "push1", composed: "púh1"))
    }
}
