import Foundation

/// Shared XMLParser plumbing for the KML and GPX readers: element path, trimmed text, abort-on-error.
class GeoXMLHandler: NSObject, XMLParserDelegate {
    private(set) var path: [String] = []
    private var text = ""
    private var failure: Error?
    private weak var activeParser: XMLParser?

    func start(_ name: String, _ attributes: [String: String]) {}
    func end(_ name: String, text: String) {}

    var parent: String? { path.count >= 2 ? path[path.count - 2] : nil }

    func fail(_ error: Error) {
        failure = failure ?? error
        activeParser?.abortParsing()
    }

    func run(_ data: Data) throws {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        activeParser = parser
        let finished = parser.parse()
        if let failure { throw failure }
        if !finished { throw GeoError(message: "XML không hợp lệ") }
    }

    private func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        let name = local(elementName)
        path.append(name)
        text = ""
        start(name, attributes)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        end(local(elementName), text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        if !path.isEmpty { path.removeLast() }
        text = ""
    }
}
