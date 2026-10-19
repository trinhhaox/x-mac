/// The synthetic keystrokes that turn the text on screen into the new word.
struct SyntheticReplacementPlan: Equatable {
    /// Narrow no-break space typed first in browsers: it replaces a selected
    /// autocomplete suggestion, so the Backspaces that follow delete real
    /// characters. It is deleted again by one extra Backspace.
    static let autocompleteBreaker: [UInt16] = [0x202F]

    let leadingText: [UInt16]?
    let backspaceCount: Int
    let textChunks: [[UInt16]]

    var syntheticEventCount: Int {
        ((leadingText == nil ? 0 : 1) + backspaceCount + textChunks.count) * 2
    }

    static func make(backspaceCount: Int, newText: String, isBrowser: Bool) -> SyntheticReplacementPlan {
        guard isBrowser else {
            return SyntheticReplacementPlan(
                leadingText: nil,
                backspaceCount: backspaceCount,
                textChunks: Utf16Chunker.chunks(newText)
            )
        }
        // Web editors map one key event to one input event; several characters
        // in one synthetic key are dropped or misread by some of them.
        return SyntheticReplacementPlan(
            leadingText: backspaceCount > 0 ? autocompleteBreaker : nil,
            backspaceCount: backspaceCount > 0 ? backspaceCount + 1 : 0,
            textChunks: newText.map { Array($0.utf16) }
        )
    }
}
