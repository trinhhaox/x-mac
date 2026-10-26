import Foundation

/// Rewrites an unzipped DOCX in place: text in runs set in legacy fonts becomes Unicode and the
/// legacy font names (in runs and styles) become Times New Roman / Arial.
final class LegacyVietnameseDocxRewriter {
    private static let fontSlots = ["ascii", "hAnsi", "eastAsia", "cs"]

    private let styles: LegacyVietnameseDocxStyles
    private var changes = 0

    private init(styles: LegacyVietnameseDocxStyles) { self.styles = styles }

    /// Returns how many runs and font declarations were changed; 0 means the document had no legacy fonts.
    static func rewrite(package: URL, checkCancellation: () throws -> Void) throws -> Int {
        let word = package.appendingPathComponent("word", isDirectory: true)
        var total = try rewriteFolder(word, checkCancellation: checkCancellation)
        let glossary = word.appendingPathComponent("glossary", isDirectory: true)
        if FileManager.default.fileExists(atPath: glossary.path) {
            total += try rewriteFolder(glossary, checkCancellation: checkCancellation)
        }
        return total
    }

    /// One part folder (`word/` or `word/glossary/`): body parts get their text converted, the style, numbering
    /// and font-table parts only their font declarations.
    private static func rewriteFolder(_ folder: URL, checkCancellation: () throws -> Void) throws -> Int {
        let stylesURL = folder.appendingPathComponent("styles.xml")
        let stylesDocument = try? load(stylesURL)
        let rewriter = LegacyVietnameseDocxRewriter(styles: LegacyVietnameseDocxStyles(styles: stylesDocument?.rootElement()))
        var total = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() where isContentPart(name) {
            try checkCancellation()
            total += try rewriter.rewrite(folder.appendingPathComponent(name), convertingText: true)
        }
        if stylesDocument != nil { total += try rewriter.rewrite(stylesURL, convertingText: false) }
        let numbering = folder.appendingPathComponent("numbering.xml")
        if FileManager.default.fileExists(atPath: numbering.path) { total += try rewriter.rewrite(numbering, convertingText: false) }
        let fontTable = folder.appendingPathComponent("fontTable.xml")
        if FileManager.default.fileExists(atPath: fontTable.path) {
            // Not counted: a font table alone declaring a legacy font does not mean any text uses it.
            _ = try edit(fontTable, LegacyVietnameseDocxFontTable.rewrite)
        }
        return total
    }

    private static func isContentPart(_ name: String) -> Bool {
        guard name.hasSuffix(".xml") else { return false }
        return name == "document.xml" || name == "footnotes.xml" || name == "endnotes.xml" || name == "comments.xml"
            || name.hasPrefix("header") || name.hasPrefix("footer")
    }

    private static func load(_ url: URL) throws -> XMLDocument {
        try XMLDocument(data: Data(contentsOf: url), options: [.nodePreserveAll])
    }

    private static func edit(_ url: URL, _ transform: (XMLElement) -> Int) throws -> Int {
        let document = try load(url)
        guard let root = document.rootElement() else { return 0 }
        let count = transform(root)
        if count > 0 { try document.xmlData(options: [.nodePreserveAll]).write(to: url, options: .atomic) }
        return count
    }

    private func rewrite(_ url: URL, convertingText: Bool) throws -> Int {
        try Self.edit(url) { root in
            changes = 0
            walk(root, paragraphStyle: nil, convertingText: convertingText)
            return changes
        }
    }

    private func walk(_ element: XMLElement, paragraphStyle: String?, convertingText: Bool) {
        var paragraphStyle = paragraphStyle
        if element.isWord("lvl") {
            if LegacyVietnameseDocxNumbering.convertLevelText(element, styles: styles) { changes += 1 }
        } else if element.isWord("p") {
            paragraphStyle = element.wordChild("pPr")?.wordChild("pStyle")?.wordAttribute("val")
            if convertingText { convertParagraph(element, paragraphStyle: paragraphStyle) }
        } else if element.isWord("rFonts") {
            replaceLegacyFonts(in: element)
        }
        for case let child as XMLElement in element.children ?? [] {
            walk(child, paragraphStyle: paragraphStyle, convertingText: convertingText)
        }
    }

    /// Consecutive runs in the same legacy charset are converted as one text, because a letter's base and mark
    /// bytes can be split across runs.
    private func convertParagraph(_ paragraph: XMLElement, paragraphStyle: String?) {
        var nodes: [XMLElement] = []
        var groupFont: LegacyVietnameseFont?
        func flush() {
            if let font = groupFont { convert(nodes, as: font) }
            nodes = []
            groupFont = nil
        }
        for run in Self.runs(in: paragraph) {
            guard let font = legacyFont(of: run, paragraphStyle: paragraphStyle) else { flush(); continue }
            changes += 1
            if let current = groupFont, current.charset != font.charset || current.isAllCaps != font.isAllCaps { flush() }
            groupFont = font
            nodes += Self.textNodes(of: run, charset: font.charset)
        }
        flush()
    }

    /// Runs of this paragraph in order, including those inside hyperlinks / revisions, but not those of nested paragraphs.
    private static func runs(in element: XMLElement) -> [XMLElement] {
        var found: [XMLElement] = []
        for case let child as XMLElement in element.children ?? [] {
            if child.isWord("r") { found.append(child) } else if !child.isWord("p") { found += runs(in: child) }
        }
        return found
    }

    private func legacyFont(of run: XMLElement, paragraphStyle: String?) -> LegacyVietnameseFont? {
        let properties = run.wordChild("rPr")
        let name = properties.flatMap(LegacyVietnameseDocxStyles.fontName)
            ?? styles.inheritedFont(
                characterStyle: properties?.wordChild("rStyle")?.wordAttribute("val"), paragraphStyle: paragraphStyle)
        return name.flatMap(LegacyVietnameseFont.init(name:))
    }

    /// Visible and tracked-deleted text. In TCVN3 a soft hyphen (byte 0xAD) is "ư", which Word may store as `<w:softHyphen/>`.
    private static func textNodes(of run: XMLElement, charset: LegacyVietnameseCharset) -> [XMLElement] {
        if charset == .tcvn3 {
            for case let hyphen as XMLElement in run.children ?? [] where hyphen.isWord("softHyphen") {
                let text = XMLElement(name: hyphen.prefix.map { "\($0):t" } ?? "t", uri: hyphen.uri)
                text.stringValue = "\u{AD}"
                run.replaceChild(at: hyphen.index, with: text)
            }
        }
        return (run.children ?? []).compactMap { node in
            guard let element = node as? XMLElement, element.isWord("t") || element.isWord("delText") else { return nil }
            return element
        }
    }

    private func convert(_ nodes: [XMLElement], as font: LegacyVietnameseFont) {
        var previous: XMLElement?
        for node in nodes {
            guard var text = node.stringValue, !text.isEmpty else { continue }
            if let previous, var head = previous.stringValue, let last = head.unicodeScalars.last,
               let first = text.unicodeScalars.first,
               LegacyVietnameseEncoding.joins(last.value, first.value, charset: font.charset) {
                head.unicodeScalars.append(first)
                text.unicodeScalars.removeFirst()
                previous.stringValue = head
                node.stringValue = text
            }
            if !text.isEmpty { previous = node }
        }
        for node in nodes {
            if let text = node.stringValue { node.stringValue = font.unicode(from: text) }
        }
    }

    private func replaceLegacyFonts(in fonts: XMLElement) {
        for slot in Self.fontSlots {
            guard let attribute = fonts.wordAttributeNode(slot),
                  let name = attribute.stringValue, let font = LegacyVietnameseFont(name: name) else { continue }
            attribute.stringValue = font.replacement
            changes += 1
        }
    }
}
