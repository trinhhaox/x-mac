import Foundation

/// KML 2.2 Placemarks: Point, LineString, Polygon (outer + inner boundaries), MultiGeometry.
enum GeoKMLCodec {
    static func parse(_ data: Data) throws -> [GeoFeature] {
        let reader = Reader()
        try reader.run(data)
        return reader.features
    }

    static func write(_ features: [GeoFeature]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n<Document>\n"
        for feature in features {
            xml += "<Placemark>"
            if let name = feature.name { xml += "<name>\(GeoText.xmlEscaped(name))</name>" }
            if let description = feature.description { xml += "<description>\(GeoText.xmlEscaped(description))</description>" }
            xml += element(feature.geometry) + "</Placemark>\n"
        }
        return Data((xml + "</Document>\n</kml>\n").utf8)
    }

    private static func coordinates(_ line: [GeoCoordinate]) -> String {
        let list = line.map { c in ([c.lon, c.lat] + (c.ele.map { [$0] } ?? [])).map(GeoText.number).joined(separator: ",") }
        return "<coordinates>\(list.joined(separator: " "))</coordinates>"
    }

    private static func polygon(_ rings: [[GeoCoordinate]]) -> String {
        func ring(_ r: [GeoCoordinate]) -> String { "<LinearRing>\(coordinates(r))</LinearRing>" }
        guard let outer = rings.first else { return "" }
        return "<Polygon><outerBoundaryIs>\(ring(outer))</outerBoundaryIs>"
            + rings.dropFirst().map { "<innerBoundaryIs>\(ring($0))</innerBoundaryIs>" }.joined() + "</Polygon>"
    }

    private static func element(_ geometry: GeoGeometry) -> String {
        switch geometry {
        case .point(let c): return "<Point>\(coordinates([c]))</Point>"
        case .lineString(let l): return "<LineString>\(coordinates(l))</LineString>"
        case .polygon(let r): return polygon(r)
        case .multiPoint(let l): return multi(l.map { .point($0) })
        case .multiLineString(let l): return multi(l.map { .lineString($0) })
        case .multiPolygon(let p): return multi(p.map { .polygon($0) })
        case .collection(let parts): return multi(parts)
        }
    }

    private static func multi(_ parts: [GeoGeometry]) -> String { "<MultiGeometry>" + parts.map(element).joined() + "</MultiGeometry>" }

    // MARK: Reading

    private final class Reader: GeoXMLHandler {
        var features: [GeoFeature] = []
        private var name: String?
        private var summary: String?
        /// One list of finished geometries per open Placemark / MultiGeometry.
        private var containers: [[GeoGeometry]] = []
        private var coordinateList: [GeoCoordinate] = []
        private var polygonRings: [[GeoCoordinate]]?

        override func start(_ element: String, _ attributes: [String: String]) {
            switch element {
            case "Placemark": name = nil; summary = nil; containers = [[]]
            case "MultiGeometry": if !containers.isEmpty { containers.append([]) }
            case "Polygon": polygonRings = []
            case "Point", "LineString", "LinearRing", "coordinates": coordinateList = []
            default: break
            }
        }

        override func end(_ element: String, text: String) {
            guard !containers.isEmpty else { return }
            switch element {
            case "name" where parent == "Placemark": name = text
            case "description" where parent == "Placemark": summary = text
            case "coordinates":
                do { coordinateList = try Self.parseCoordinates(text) } catch { fail(error) }
            case "Point": if let first = coordinateList.first { containers[containers.count - 1].append(.point(first)) }
            case "LineString": containers[containers.count - 1].append(.lineString(coordinateList))
            case "LinearRing":
                if path.contains("outerBoundaryIs") { polygonRings?.insert(coordinateList, at: 0) } else { polygonRings?.append(coordinateList) }
            case "Polygon":
                if let rings = polygonRings, !rings.isEmpty { containers[containers.count - 1].append(.polygon(rings)) }
                polygonRings = nil
            case "MultiGeometry":
                guard containers.count >= 2 else { return }
                let parts = containers.removeLast()
                containers[containers.count - 1].append(Self.merge(parts))
            case "Placemark":
                let parts = containers.removeLast()
                if !parts.isEmpty { features.append(GeoFeature(name: name, description: summary, geometry: parts.count == 1 ? parts[0] : .collection(parts))) }
                containers = []
            default: break
            }
        }

        private static func parseCoordinates(_ text: String) throws -> [GeoCoordinate] {
            try text.split(whereSeparator: \.isWhitespace).map { tuple in
                let values = tuple.split(separator: ",", omittingEmptySubsequences: false).map { Double($0) }
                guard values.count >= 2, let lon = values[0], let lat = values[1] else { throw GeoError(message: "Toạ độ không hợp lệ") }
                return try GeoCoordinate(lon: lon, lat: lat, ele: values.count > 2 ? values[2] : nil)
            }
        }

        /// Homogeneous MultiGeometry becomes the matching Multi* type, anything else a collection.
        private static func merge(_ parts: [GeoGeometry]) -> GeoGeometry {
            if case .point = parts.first, case let points = parts.compactMap({ if case .point(let c) = $0 { c } else { nil } }), points.count == parts.count {
                return .multiPoint(points)
            }
            if case .lineString = parts.first, case let lines = parts.compactMap({ if case .lineString(let l) = $0 { l } else { nil } }), lines.count == parts.count {
                return .multiLineString(lines)
            }
            if case .polygon = parts.first, case let polygons = parts.compactMap({ if case .polygon(let p) = $0 { p } else { nil } }), polygons.count == parts.count {
                return .multiPolygon(polygons)
            }
            return .collection(parts)
        }
    }
}
