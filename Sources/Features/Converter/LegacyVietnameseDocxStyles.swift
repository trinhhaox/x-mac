import Foundation

enum WordML {
    static let namespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
}

extension XMLElement {
    func isWord(_ name: String) -> Bool { localName == name && uri == WordML.namespace }

    func wordChild(_ name: String) -> XMLElement? {
        elements(forLocalName: name, uri: WordML.namespace).first
    }

    func wordAttribute(_ name: String) -> String? {
        attribute(forLocalName: name, uri: WordML.namespace)?.stringValue
    }
}

/// Which font a run inherits when it has no `<w:rFonts>` of its own: character style, paragraph style,
/// the default paragraph style (Normal), then `<w:docDefaults>`.
struct LegacyVietnameseDocxStyles {
    private var fontByStyle: [String: String] = [:]
    private var parentByStyle: [String: String] = [:]
    private var defaultParagraphStyle: String?
    private var documentDefaultFont: String?

    init(styles: XMLElement?) {
        guard let styles else { return }
        documentDefaultFont = styles.wordChild("docDefaults")?.wordChild("rPrDefault")?.wordChild("rPr")
            .flatMap(Self.fontName)
        for style in styles.elements(forLocalName: "style", uri: WordML.namespace) {
            guard let id = style.wordAttribute("styleId") else { continue }
            if let font = style.wordChild("rPr").flatMap(Self.fontName) { fontByStyle[id] = font }
            if let parent = style.wordChild("basedOn")?.wordAttribute("val") { parentByStyle[id] = parent }
            if style.wordAttribute("type") == "paragraph", style.wordAttribute("default") == "1" { defaultParagraphStyle = id }
        }
    }

    func inheritedFont(characterStyle: String?, paragraphStyle: String?) -> String? {
        [characterStyle, paragraphStyle, defaultParagraphStyle].lazy.compactMap { $0.flatMap(font(ofStyle:)) }.first
            ?? documentDefaultFont
    }

    /// The ASCII-slot font a property block declares (hAnsi as fallback), where Vietnamese text lives; nil when it
    /// declares none so inheritance continues. A theme font yields "", which is never legacy but stops the search.
    /// eastAsia and cs never decide.
    static func fontName(in properties: XMLElement) -> String? {
        guard let fonts = properties.wordChild("rFonts") else { return nil }
        if fonts.wordAttribute("asciiTheme") != nil { return "" }
        if let ascii = fonts.wordAttribute("ascii") { return ascii }
        if fonts.wordAttribute("hAnsiTheme") != nil { return "" }
        return fonts.wordAttribute("hAnsi")
    }

    private func font(ofStyle id: String) -> String? {
        var current: String? = id
        for _ in 0..<20 {
            guard let style = current else { return nil }
            if let font = fontByStyle[style] { return font }
            current = parentByStyle[style]
        }
        return nil
    }
}
