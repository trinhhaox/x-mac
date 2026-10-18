enum Utf16Chunker {
    /// Splits text into UTF-16 chunks of at most `maxUnits`, since apps read only
    /// ~20 units from one synthetic key event. Chunks break on grapheme-cluster
    /// boundaries; a cluster longer than `maxUnits` falls back to scalar
    /// boundaries so surrogate pairs are never split.
    static func chunks(_ text: String, maxUnits: Int = 16) -> [[UInt16]] {
        precondition(maxUnits >= 2, "a surrogate pair needs two units")
        var result: [[UInt16]] = []
        var current: [UInt16] = []

        func append(_ units: [UInt16]) {
            if current.count + units.count > maxUnits, !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }

        for character in text {
            let units = Array(character.utf16)
            if units.count <= maxUnits {
                append(units)
            } else {
                character.unicodeScalars.forEach { append(Array(String($0).utf16)) }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
