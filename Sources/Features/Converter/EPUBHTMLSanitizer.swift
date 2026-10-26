import Foundation

/// Allow-list HTML sanitiser for EPUB chapters. Output is inert and offline: no scripts, styles, forms or
/// remote loads; images only as data: URIs; links only http(s)/mailto and never auto-loaded.
final class EPUBHTMLSanitizer {
    static let maxInlineImageBytes = 2 * 1024 * 1024
    static let maxTotalInlineBytes = 50 * 1024 * 1024
    private static let maxDepth = 100

    private static let mimeTypes = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "webp": "image/webp", "svg": "image/svg+xml", "bmp": "image/bmp",
    ]
    private static let dataImage = try? NSRegularExpression(
        pattern: #"^data:image/(png|jpe?g|gif|webp|bmp|svg\+xml);base64,[A-Za-z0-9+/]+={0,2}$"#, options: [.caseInsensitive])
    private static let voidTags: Set<String> = ["br", "hr", "img"]
    private static let allowedTags: Set<String> = [
        "p", "div", "span", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "thead", "tbody", "tr", "th", "td",
        "blockquote", "pre", "code", "em", "strong", "b", "i", "u", "s", "sub", "sup", "br", "hr", "img", "a",
        "figure", "figcaption", "section", "article", "header", "footer", "nav", "aside",
    ]
    /// Dropped together with their content.
    private static let droppedTags: Set<String> = [
        "script", "style", "iframe", "object", "embed", "meta", "base", "link", "form", "input", "button", "select", "textarea",
        "svg", "math", "video", "audio", "source", "track", "canvas", "applet", "frame", "frameset", "noscript", "template", "head", "title",
    ]
    private static let numeric: Set<String> = ["width", "height", "colspan", "rowspan"]

    private let root: URL
    private var inlineBytesLeft = EPUBHTMLSanitizer.maxTotalInlineBytes

    init(root: URL) { self.root = root }

    func sanitize(_ html: String, chapterFile: URL) -> String {
        guard let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let top = document.rootElement() else { return Self.escape(Self.plainText(html)) }
        let body = top.elements(forName: "body").first ?? top
        return (body.children ?? []).map { render($0, chapterFile, depth: 0) }.joined()
    }

    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func render(_ node: XMLNode, _ file: URL, depth: Int) -> String {
        if node.kind == .text { return Self.escape(node.stringValue ?? "") }
        guard node.kind == .element, let element = node as? XMLElement, depth < Self.maxDepth else { return "" }
        let name = (element.localName ?? element.name ?? "").lowercased()
        if Self.droppedTags.contains(name) { return "" }
        if name == "img" { return image(element, file) }
        let inner = (element.children ?? []).map { render($0, file, depth: depth + 1) }.joined()
        guard Self.allowedTags.contains(name) else { return inner }
        if Self.voidTags.contains(name) { return "<\(name)\(attributes(element, name))>" }
        return "<\(name)\(attributes(element, name))>\(inner)</\(name)>"
    }

    private func attributes(_ element: XMLElement, _ tag: String) -> String {
        var result = ""
        for attribute in element.attributes ?? [] {
            let key = (attribute.localName ?? attribute.name ?? "").lowercased()
            let value = (attribute.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let keep: Bool
            switch key {
            case "lang", "dir": keep = value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && !value.isEmpty
            case "href": keep = tag == "a" && Self.isSafeLink(value)
            case "colspan", "rowspan": keep = (tag == "td" || tag == "th") && Self.isSmallNumber(value)
            default: keep = false
            }
            if keep { result += " \(key)=\"\(Self.escape(value))\"" }
        }
        return result
    }

    static func isSafeLink(_ value: String) -> Bool {
        let lower = value.lowercased()
        return ["http://", "https://", "mailto:"].contains { lower.hasPrefix($0) }
    }

    private static func isSmallNumber(_ value: String) -> Bool { !value.isEmpty && value.count <= 5 && value.allSatisfy(\.isASCII) && value.allSatisfy(\.isNumber) }

    // MARK: Images

    /// An inline data: image, or just the alt text when the image is missing, remote, oversized or over budget.
    private func image(_ element: XMLElement, _ file: URL) -> String {
        let alt = element.attribute(forName: "alt")?.stringValue ?? ""
        guard let src = element.attribute(forName: "src")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let uri = dataURI(for: src, chapterFile: file), claim(uri.count) else { return Self.escape(alt) }
        var sizes = ""
        for key in ["width", "height"] {
            if let value = element.attribute(forName: key)?.stringValue, Self.isSmallNumber(value) { sizes += " \(key)=\"\(value)\"" }
        }
        return "<img src=\"\(uri)\" alt=\"\(Self.escape(alt))\"\(sizes)>"
    }

    private func dataURI(for src: String, chapterFile: URL) -> String? {
        if src.lowercased().hasPrefix("data:") {
            let range = NSRange(src.startIndex..., in: src)
            let valid = src.count <= Self.maxInlineImageBytes * 4 / 3 + 64 && Self.dataImage?.firstMatch(in: src, range: range) != nil
            return valid ? src : nil
        }
        guard let file = EPUBPackage.resolve(src, relativeTo: chapterFile, root: root),
              let mime = Self.mimeTypes[file.pathExtension.lowercased()],
              let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= Self.maxInlineImageBytes, size <= inlineBytesLeft,
              let data = try? Data(contentsOf: file) else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private func claim(_ bytes: Int) -> Bool {
        guard bytes <= inlineBytesLeft else { return false }
        inlineBytesLeft -= bytes
        return true
    }
}
