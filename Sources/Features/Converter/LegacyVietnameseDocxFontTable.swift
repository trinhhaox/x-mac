import Foundation

/// `word/fontTable.xml`: legacy font entries are renamed to their Unicode replacement, or dropped when the
/// table already lists that replacement, so no `<w:font>` name appears twice.
enum LegacyVietnameseDocxFontTable {
    /// Embedded copies of the legacy font; they would keep supplying the old glyphs under the new name.
    private static let embeddedFontTags = ["embedRegular", "embedBold", "embedItalic", "embedBoldItalic"]

    /// Returns how many entries were renamed or removed.
    static func rewrite(_ fonts: XMLElement) -> Int {
        var names = Set(fonts.wordChildren("font").compactMap { $0.wordAttribute("name") }
            .filter { LegacyVietnameseFont(name: $0) == nil })
        var changes = 0
        for entry in fonts.wordChildren("font") {
            guard let nameNode = entry.wordAttributeNode("name"), let name = nameNode.stringValue,
                  let legacy = LegacyVietnameseFont(name: name) else { continue }
            changes += 1
            if names.insert(legacy.replacement).inserted {
                nameNode.stringValue = legacy.replacement
                embeddedFontTags.flatMap(entry.wordChildren).forEach { $0.detach() }
            } else {
                entry.detach()
            }
        }
        return changes
    }
}
