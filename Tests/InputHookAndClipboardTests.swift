import Testing
@testable import Xmac

struct CtrlShiftToggleDetectorTests {
    private func fire(_ d: inout CtrlShiftToggleDetector, _ c: Bool, _ s: Bool, _ o: Bool = false) -> Bool {
        d.handleFlagsChanged(control: c, shift: s, other: o)
    }

    @Test func cleanCtrlShiftTapTogglesOnRelease() {
        var detector = CtrlShiftToggleDetector()
        #expect(!fire(&detector, true, false, false))
        #expect(!fire(&detector, true, true, false))
        #expect(fire(&detector, true, false, false))
        #expect(!fire(&detector, false, false, false))
    }

    @Test func keyPressWhileHeldCancels() {
        var detector = CtrlShiftToggleDetector()
        _ = detector.handleFlagsChanged(control: true, shift: true, other: false)
        detector.handleKeyDown() // e.g. Ctrl+Shift+Tab
        #expect(!fire(&detector, true, false, false))
        #expect(!fire(&detector, false, false, false))
    }

    @Test func extraModifierCancels() {
        var detector = CtrlShiftToggleDetector()
        _ = detector.handleFlagsChanged(control: true, shift: true, other: false)
        _ = detector.handleFlagsChanged(control: true, shift: true, other: true) // + Command
        #expect(!fire(&detector, true, true, false))
        #expect(!fire(&detector, false, false, false))
    }

    @Test func togglesAgainAfterFullRelease() {
        var detector = CtrlShiftToggleDetector()
        _ = detector.handleFlagsChanged(control: true, shift: true, other: false)
        #expect(fire(&detector, false, true, false))
        #expect(!fire(&detector, false, false, false))
        _ = detector.handleFlagsChanged(control: true, shift: true, other: false)
        #expect(fire(&detector, false, false, false))
    }

    @Test func singleModifiersNeverToggle() {
        var detector = CtrlShiftToggleDetector()
        #expect(!fire(&detector, false, true, false))
        #expect(!fire(&detector, false, false, false))
    }
}

struct Utf16ChunkerTests {
    @Test func shortTextIsOneChunk() {
        #expect(Utf16Chunker.chunks("xin chào") == [Array("xin chào".utf16)])
        #expect(Utf16Chunker.chunks("").isEmpty)
    }

    @Test func longTextSplitsWithinLimitAndRoundTrips() {
        let text = String(repeating: "Việt Nam 🇻🇳 👨‍👩‍👧 ", count: 8)
        let chunks = Utf16Chunker.chunks(text)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 16 })
        #expect(String(decoding: chunks.flatMap { $0 }, as: UTF16.self) == text)
    }

    @Test func neverSplitsSurrogatePairsOrClusters() {
        let text = String(repeating: "a😀", count: 20)
        for chunk in Utf16Chunker.chunks(text) {
            #expect(String(utf16CodeUnits: chunk, count: chunk.count).unicodeScalars.allSatisfy { $0 != "\u{FFFD}" })
        }
        let cluster = String(repeating: "👨‍", count: 12) + "👩" // one grapheme > 16 units
        let chunks = Utf16Chunker.chunks(cluster)
        #expect(chunks.allSatisfy { $0.count <= 16 })
        #expect(String(decoding: chunks.flatMap { $0 }, as: UTF16.self) == cluster)
    }
}

struct ClipboardBlockedTypesTests {
    @Test func skipsPasswordManagerAndTransientMarkers() {
        for type in ["com.typeit4me.clipping", "de.petermaurer.TransientPasteboardType", "org.nspasteboard.ConcealedType"] {
            #expect(ClipboardHistory.blocked(types: [type], source: "x", exclusions: "", secure: false))
        }
        #expect(!ClipboardHistory.blocked(types: ["public.utf8-plain-text"], source: "x", exclusions: "", secure: false))
    }
}
