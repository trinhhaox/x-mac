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

    static func make(
        backspaceCount: Int,
        newText: String,
        isBrowser: Bool,
        isElectronOrChatApp: Bool = false,
        useAutocompleteBreaker: Bool = false
    ) -> SyntheticReplacementPlan {
        let needsSingleChars = isBrowser || isElectronOrChatApp
        guard needsSingleChars else {
            return SyntheticReplacementPlan(
                leadingText: nil,
                backspaceCount: backspaceCount,
                textChunks: Utf16Chunker.chunks(newText)
            )
        }
        // Web and Electron editors (Chrome, Zalo, VS Code, Slack) map one key event
        // to one input event. By default we omit the U+202F breaker because it corrupts
        // contentEditable DOMs (Google Docs, web chats, Notion) and adds backspace delay.
        let shouldBreak = useAutocompleteBreaker && isBrowser && backspaceCount > 0
        return SyntheticReplacementPlan(
            leadingText: shouldBreak ? autocompleteBreaker : nil,
            backspaceCount: shouldBreak ? backspaceCount + 1 : backspaceCount,
            textChunks: newText.map { Array($0.utf16) }
        )
    }
}
