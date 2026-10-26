import Foundation

/// An unpacked EPUB: title plus the content documents in reading (spine) order.
struct EPUBPackage {
    let title: String
    let chapterFiles: [URL]
    /// Resolved extraction root; every file the package refers to must stay inside it.
    let root: URL

    private static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")

    /// Extracts `epub` into `directory` (rejecting zip-slip entries) and reads container.xml → OPF → spine.
    static func load(_ epub: URL, extractingInto directory: URL) async throws -> EPUBPackage {
        try await ZipArchiveGuard.validate(epub)
        try await ConverterWorkspace.run(ditto, ["-x", "-k", epub.path, directory.path], timeout: 120)

        let root = directory.resolvingSymlinksInPath()
        let container = root.appendingPathComponent("META-INF/container.xml")
        guard let data = try? Data(contentsOf: container),
              let opfPath = EPUBXMLReader.parse(data).rootfilePath,
              let opfURL = resolve(opfPath, relativeTo: root.appendingPathComponent("x"), root: root),
              let opfData = try? Data(contentsOf: opfURL) else {
            throw ConversionError.failed("Not a valid EPUB (container.xml / OPF missing)")
        }
        let opf = EPUBXMLReader.parse(opfData)
        var chapters: [URL] = []
        for idref in opf.spine {
            guard let item = opf.manifest[idref], isContentDocument(item) else { continue }
            guard let url = resolve(item.href, relativeTo: opfURL, root: root) else {
                throw ConversionError.failed("Unsafe path in EPUB: \(item.href)")
            }
            chapters.append(url)
        }
        guard !chapters.isEmpty else { throw ConversionError.failed("EPUB has no readable chapters") }
        let fallbackTitle = epub.deletingPathExtension().lastPathComponent
        let title = opf.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return EPUBPackage(title: title.isEmpty ? fallbackTitle : title, chapterFiles: chapters, root: root)
    }

    /// Resolves a manifest/img href against the referring file. Nil when it is absolute,
    /// escapes `root` (also through symlinks), or does not decode.
    static func resolve(_ href: String, relativeTo file: URL, root: URL) -> URL? {
        let withoutFragment = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? href
        let path = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? withoutFragment
        guard let decoded = path.removingPercentEncoding, !decoded.isEmpty,
              !decoded.hasPrefix("/"), !decoded.contains("\0"), !decoded.contains("://") else { return nil }
        let candidate = file.deletingLastPathComponent().appendingPathComponent(decoded)
            .standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.resolvingSymlinksInPath().path
        return candidate.path.hasPrefix(rootPath + "/") ? candidate : nil
    }

    private static func isContentDocument(_ item: EPUBXMLReader.ManifestItem) -> Bool {
        let type = item.mediaType.lowercased()
        if type.contains("html") { return true }
        return ["xhtml", "html", "htm"].contains((item.href as NSString).pathExtension.lowercased())
    }
}

/// Collects the few EPUB container/OPF facts we need; DTDs and external entities are never loaded.
final class EPUBXMLReader: NSObject, XMLParserDelegate {
    struct ManifestItem { let href: String; let mediaType: String }

    private(set) var rootfilePath: String?
    private(set) var manifest: [String: ManifestItem] = [:]
    private(set) var spine: [String] = []
    private(set) var title = ""
    private var readingTitle = false

    static func parse(_ data: Data) -> EPUBXMLReader {
        let reader = EPUBXMLReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        parser.parse()
        return reader
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        switch name {
        case "rootfile" where rootfilePath == nil:
            rootfilePath = attributes["full-path"]
        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = ManifestItem(href: href, mediaType: attributes["media-type"] ?? "")
            }
        case "itemref":
            if let idref = attributes["idref"] { spine.append(idref) }
        case "dc:title" where title.isEmpty:
            readingTitle = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingTitle { title += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "dc:title" { readingTitle = false }
    }
}
