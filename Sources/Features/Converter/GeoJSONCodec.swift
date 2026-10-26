import Foundation

/// RFC 7946 GeoJSON. Coordinates are [longitude, latitude, elevation?]; only `name`/`description` properties are kept.
enum GeoJSONCodec {
    static func parse(_ data: Data) throws -> [GeoFeature] {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GeoError(message: "Không phải GeoJSON hợp lệ")
        }
        guard let object = root as? [String: Any], let type = object["type"] as? String else {
            throw GeoError(message: "Không phải GeoJSON hợp lệ")
        }
        switch type {
        case "FeatureCollection":
            return try (object["features"] as? [[String: Any]] ?? []).compactMap(feature)
        case "Feature":
            return try feature(object).map { [$0] } ?? []
        default:
            return [GeoFeature(name: nil, description: nil, geometry: try geometry(object))]
        }
    }

    static func write(_ features: [GeoFeature]) throws -> Data {
        let items: [[String: Any]] = features.map { feature in
            var properties: [String: Any] = [:]
            if let name = feature.name { properties["name"] = name }
            if let description = feature.description { properties["description"] = description }
            return ["type": "Feature", "properties": properties, "geometry": json(feature.geometry)]
        }
        return try JSONSerialization.data(
            withJSONObject: ["type": "FeatureCollection", "features": items],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Reading

    private static func feature(_ object: [String: Any]) throws -> GeoFeature? {
        guard let raw = object["geometry"] as? [String: Any] else { return nil }
        let properties = object["properties"] as? [String: Any]
        return GeoFeature(
            name: properties?["name"] as? String, description: properties?["description"] as? String,
            geometry: try geometry(raw))
    }

    private static func geometry(_ object: [String: Any]) throws -> GeoGeometry {
        guard let type = object["type"] as? String else { throw GeoError(message: "Hình học không hợp lệ") }
        if type == "GeometryCollection" {
            return .collection(try (object["geometries"] as? [[String: Any]] ?? []).map(geometry))
        }
        guard let raw = object["coordinates"] else { throw GeoError(message: "Hình học không hợp lệ") }
        switch type {
        case "Point": return .point(try coordinate(raw))
        case "LineString": return .lineString(try line(raw))
        case "Polygon": return .polygon(try rings(raw))
        case "MultiPoint": return .multiPoint(try line(raw))
        case "MultiLineString": return .multiLineString(try list(raw, line))
        case "MultiPolygon": return .multiPolygon(try list(raw, rings))
        default: throw GeoError(message: "Hình học không hợp lệ")
        }
    }

    private static func coordinate(_ raw: Any) throws -> GeoCoordinate {
        guard let values = raw as? [Double], values.count >= 2 else { throw GeoError(message: "Toạ độ không hợp lệ") }
        return try GeoCoordinate(lon: values[0], lat: values[1], ele: values.count > 2 ? values[2] : nil)
    }

    private static func list<T>(_ raw: Any, _ parse: (Any) throws -> T) throws -> [T] {
        guard let items = raw as? [Any] else { throw GeoError(message: "Toạ độ không hợp lệ") }
        return try items.map(parse)
    }

    private static func line(_ raw: Any) throws -> [GeoCoordinate] { try list(raw, coordinate) }
    private static func rings(_ raw: Any) throws -> [[GeoCoordinate]] { try list(raw, line) }

    // MARK: Writing

    private static func position(_ c: GeoCoordinate) -> [Double] {
        c.ele.map { [c.lon, c.lat, $0] } ?? [c.lon, c.lat]
    }

    private static func json(_ geometry: GeoGeometry) -> [String: Any] {
        switch geometry {
        case .point(let c): return ["type": "Point", "coordinates": position(c)]
        case .lineString(let l): return ["type": "LineString", "coordinates": l.map(position)]
        case .polygon(let r): return ["type": "Polygon", "coordinates": r.map { $0.map(position) }]
        case .multiPoint(let l): return ["type": "MultiPoint", "coordinates": l.map(position)]
        case .multiLineString(let l): return ["type": "MultiLineString", "coordinates": l.map { $0.map(position) }]
        case .multiPolygon(let p): return ["type": "MultiPolygon", "coordinates": p.map { $0.map { $0.map(position) } }]
        case .collection(let parts): return ["type": "GeometryCollection", "geometries": parts.map(json)]
        }
    }
}
