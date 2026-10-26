import Foundation

struct GeoError: Error { let message: String }

struct GeoCoordinate: Equatable {
    let lon: Double
    let lat: Double
    let ele: Double?

    /// Rejects out-of-range and non-finite values, so no codec can emit NaN or an impossible position.
    init(lon: Double, lat: Double, ele: Double? = nil) throws {
        guard (-180.0...180.0).contains(lon), (-90.0...90.0).contains(lat) else {
            throw GeoError(message: "Toạ độ nằm ngoài phạm vi")
        }
        self.lon = lon
        self.lat = lat
        self.ele = ele.flatMap { $0.isFinite ? $0 : nil }
    }
}

indirect enum GeoGeometry: Equatable {
    case point(GeoCoordinate)
    case lineString([GeoCoordinate])
    /// First ring is the outer boundary, the rest are holes.
    case polygon([[GeoCoordinate]])
    case multiPoint([GeoCoordinate])
    case multiLineString([[GeoCoordinate]])
    case multiPolygon([[[GeoCoordinate]]])
    case collection([GeoGeometry])

    /// Every point and vertex in document order.
    var vertices: [GeoCoordinate] {
        switch self {
        case .point(let c): return [c]
        case .lineString(let line), .multiPoint(let line): return line
        case .polygon(let rings): return rings.flatMap { $0 }
        case .multiLineString(let lines): return lines.flatMap { $0 }
        case .multiPolygon(let polygons): return polygons.flatMap { $0.flatMap { $0 } }
        case .collection(let parts): return parts.flatMap(\.vertices)
        }
    }
}

struct GeoFeature: Equatable {
    var name: String?
    var description: String?
    var geometry: GeoGeometry
}

enum GeoText {
    static func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func number(_ value: Double) -> String { "\(value)" }

    /// One row per point/vertex. Leading `= + - @`, tab or CR in names is neutralised against spreadsheet formula injection.
    static func csv(_ features: [GeoFeature]) -> String {
        var lines = ["name,lat,lon,ele"]
        for feature in features {
            let name = csvField(feature.name ?? "")
            for c in feature.geometry.vertices {
                lines.append("\(name),\(number(c.lat)),\(number(c.lon)),\(c.ele.map(number) ?? "")")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        var text = value
        if let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) { text = "'" + text }
        guard text.unicodeScalars.contains(where: { ",\"\n\r".unicodeScalars.contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
