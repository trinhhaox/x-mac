import Foundation

/// Merges an EPUB's chapters into one self-contained, inert HTML document (see EPUBHTMLSanitizer).
enum EPUBHTMLBuilder {
    static let maxTotalBytes = 256 << 20
    private static let policy = "default-src 'none'; img-src data:; style-src 'unsafe-inline'"

    static func html(for package: EPUBPackage) throws -> String {
        let sanitizer = EPUBHTMLSanitizer(root: package.root)
        var body = ""
        var consumed = 0
        for file in package.chapterFiles {
            try Task.checkCancellation()
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            consumed += size
            guard consumed <= maxTotalBytes else { throw ConversionError.failed("EPUB content is too large") }
            let chapter = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            body += "<section>\n\(sanitizer.sanitize(chapter, chapterFile: file))\n</section>\n"
            guard body.utf8.count <= maxTotalBytes else { throw ConversionError.failed("EPUB content is too large") }
        }
        let title = EPUBHTMLSanitizer.escape(package.title)
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="\(policy)"><title>\(title)</title></head>
        <body>
        <h1>\(title)</h1>
        \(body)</body></html>
        """
    }
}
