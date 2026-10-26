import Foundation

/// `word/numbering.xml`: a list level whose `<w:rPr>` uses a legacy font stores its bullet / number text
/// (`<w:lvlText w:val="..."/>`) in that charset. `%1`-style level placeholders are kept verbatim.
enum LegacyVietnameseDocxNumbering {
    /// Converts the level's text; true when it changed. A level without its own font inherits from its linked
    /// paragraph style, then the document defaults. Must run before the level's fonts are renamed.
    static func convertLevelText(_ level: XMLElement, styles: LegacyVietnameseDocxStyles) -> Bool {
        let fontName = level.wordChild("rPr").flatMap(LegacyVietnameseDocxStyles.fontName)
            ?? styles.inheritedFont(characterStyle: nil, paragraphStyle: level.wordChild("pStyle")?.wordAttribute("val"))
        guard let font = fontName.flatMap(LegacyVietnameseFont.init(name:)),
              let node = level.wordChild("lvlText")?.wordAttributeNode("val"), let text = node.stringValue else { return false }
        let converted = convert(text, with: font)
        guard converted != text else { return false }
        node.stringValue = converted
        return true
    }

    private static func convert(_ text: String, with font: LegacyVietnameseFont) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = ""
        var pending = ""
        var index = 0
        while index < scalars.count {
            if scalars[index] == "%", index + 1 < scalars.count, ("0"..."9").contains(scalars[index + 1]) {
                result += font.unicode(from: pending)
                pending = ""
                result.unicodeScalars.append(contentsOf: scalars[index...index + 1])
                index += 2
            } else {
                pending.unicodeScalars.append(scalars[index])
                index += 1
            }
        }
        return result + font.unicode(from: pending)
    }
}
