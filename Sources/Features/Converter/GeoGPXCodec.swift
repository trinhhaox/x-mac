import Foundation

/// GPX 1.1: wpt ↔ Point, trk/trkseg ↔ (Multi)LineString, rte → LineString. Elevation is kept.
enum GeoGPXCodec {
    private static let polygonNote = "<!-- Polygon exported as a track along its outer ring; holes are not representable in GPX -->"

    static func parse(_ data: Data) throws -> [GeoFeature] {
        let reader = Reader()
        try reader.run(data)
        return reader.features
    }

    static func write(_ features: [GeoFeature]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            + "<gpx version=\"1.1\" creator=\"Xmac\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        for feature in features { xml += elements(feature.geometry, feature) }
        return Data((xml + "</gpx>\n").utf8)
    }

    private static func label(_ feature: GeoFeature) -> String {
        (feature.name.map { "<name>\(GeoText.xmlEscaped($0))</name>" } ?? "")
            + (feature.description.map { "<desc>\(GeoText.xmlEscaped($0))</desc>" } ?? "")
    }

    private static func point(_ tag: String, _ c: GeoCoordinate, _ inner: String = "") -> String {
        let ele = c.ele.map { "<ele>\(GeoText.number($0))</ele>" } ?? ""
        return "<\(tag) lat=\"\(GeoText.number(c.lat))\" lon=\"\(GeoText.number(c.lon))\">\(ele)\(inner)</\(tag)>"
    }

    private static func track(_ segments: [[GeoCoordinate]], _ feature: GeoFeature, note: String = "") -> String {
        let body = segments.map { "<trkseg>" + $0.map { point("trkpt", $0) }.joined() + "</trkseg>" }.joined()
        return "<trk>\(label(feature))\(note)\(body)</trk>\n"
    }

    private static func elements(_ geometry: GeoGeometry, _ feature: GeoFeature) -> String {
        switch geometry {
        case .point(let c): return point("wpt", c, label(feature)) + "\n"
        case .multiPoint(let l): return l.map { point("wpt", $0, label(feature)) + "\n" }.joined()
        case .lineString(let l): return track([l], feature)
        case .multiLineString(let l): return track(l, feature)
        case .polygon(let r): return track(r.prefix(1).map { $0 }, feature, note: polygonNote)
        case .multiPolygon(let p): return track(p.compactMap(\.first), feature, note: polygonNote)
        case .collection(let parts): return parts.map { elements($0, feature) }.joined()
        }
    }

    // MARK: Reading

    private final class Reader: GeoXMLHandler {
        var features: [GeoFeature] = []
        private var name: String?
        private var summary: String?
        private var current: (lat: Double, lon: Double, ele: Double?)?
        private var segment: [GeoCoordinate] = []
        private var segments: [[GeoCoordinate]] = []

        override func start(_ element: String, _ attributes: [String: String]) {
            switch element {
            case "wpt", "trkpt", "rtept":
                guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) else {
                    return fail(GeoError(message: "Toạ độ không hợp lệ"))
                }
                current = (lat, lon, nil)
                if element == "wpt" { name = nil; summary = nil }
            case "trk", "rte": name = nil; summary = nil; segments = []; segment = []
            case "trkseg": segment = []
            default: break
            }
        }

        override func end(_ element: String, text: String) {
            switch element {
            case "ele": current?.ele = Double(text)
            case "name" where Self.owners.contains(parent ?? ""): name = text
            case "desc" where Self.owners.contains(parent ?? ""): summary = text
            case "wpt":
                if let c = coordinate() { features.append(GeoFeature(name: name, description: summary, geometry: .point(c))) }
            case "trkpt", "rtept": if let c = coordinate() { segment.append(c) }
            case "trkseg": segments.append(segment)
            case "trk": finishLine(segments)
            case "rte": finishLine([segment])
            default: break
            }
        }

        private static let owners: Set<String> = ["wpt", "trk", "rte"]

        private func coordinate() -> GeoCoordinate? {
            guard let current else { return nil }
            defer { self.current = nil }
            do { return try GeoCoordinate(lon: current.lon, lat: current.lat, ele: current.ele) } catch { fail(error); return nil }
        }

        private func finishLine(_ candidates: [[GeoCoordinate]]) {
            let lines = candidates.filter { $0.count >= 2 }
            guard let first = lines.first else { return }
            let geometry: GeoGeometry = lines.count == 1 ? .lineString(first) : .multiLineString(lines)
            features.append(GeoFeature(name: name, description: summary, geometry: geometry))
        }
    }
}
