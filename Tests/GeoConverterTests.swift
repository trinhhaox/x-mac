import Foundation
import Testing
@testable import Xmac

@Suite struct GeoConverterTests {
    private let converter = GeoConverter()

    private func convert(_ text: String, file: String, to ext: String) async throws -> String {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent(file)
        try Data(text.utf8).write(to: input)
        return try await convert(input, to: ext, in: dir)
    }

    private func convert(_ input: URL, to ext: String, in dir: URL) async throws -> String {
        let target = try #require(converter.targets(for: input).first { $0.fileExtension == ext })
        let out = dir.appendingPathComponent("out.\(ext)")
        try await converter.convert(ConverterFixtures.request([input], target, output: out), progress: { _ in })
        return try String(contentsOf: out, encoding: .utf8)
    }

    private let geojson = """
    {"type":"FeatureCollection","features":[
     {"type":"Feature","properties":{"name":"Hồ <Gươm> & \\"Tháp\\"","description":"Trung tâm"},"geometry":{"type":"Point","coordinates":[105.8522,21.0287,12.5]}},
     {"type":"Feature","properties":{"name":"Tuyến"},"geometry":{"type":"MultiLineString","coordinates":[[[105,21],[106,22]],[[107,23],[108,24]]]}},
     {"type":"Feature","properties":{"name":"Ô"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]],[[2,2],[3,2],[3,3],[2,2]]]}}
    ]}
    """

    @Test func targetsFollowExtension() {
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.geojson")).map(\.fileExtension) == ["kml", "gpx", "csv"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.kmz")).map(\.fileExtension) == ["geojson", "kml", "gpx", "csv"])
        #expect(converter.targets(for: URL(fileURLWithPath: "/tmp/a.json")).isEmpty)
    }

    @Test func geoJSONToKMLKeepsOrderHolesAndEscapes() async throws {
        let kml = try await convert(geojson, file: "a.geojson", to: "kml")
        #expect(kml.contains("<coordinates>105.8522,21.0287,12.5</coordinates>"))
        #expect(kml.contains("Hồ &lt;Gươm&gt; &amp; &quot;Tháp&quot;"))
        #expect(kml.contains("<innerBoundaryIs>"))
        let back = try GeoKMLCodec.parse(Data(kml.utf8))
        #expect(back == (try GeoJSONCodec.parse(Data(geojson.utf8))))
    }

    @Test func geoJSONToGPXAndBack() async throws {
        let gpx = try await convert(geojson, file: "a.geojson", to: "gpx")
        #expect(gpx.contains("<wpt lat=\"21.0287\" lon=\"105.8522\"><ele>12.5</ele>"))
        #expect(gpx.contains("<trk><name>Tuyến</name><trkseg>") && gpx.contains("</trkseg><trkseg>"))
        #expect(gpx.contains("Polygon exported as a track"))
        let features = try GeoGPXCodec.parse(Data(gpx.utf8))
        #expect(features[0].geometry == .point(try GeoCoordinate(lon: 105.8522, lat: 21.0287, ele: 12.5)))
        guard case .multiLineString(let lines) = features[1].geometry else { Issue.record("expected MultiLineString"); return }
        #expect(lines.count == 2)
        guard case .lineString(let ring) = features[2].geometry else { Issue.record("expected outer ring track"); return }
        #expect(ring.count == 5)
    }

    @Test func gpxRouteAndWaypointToGeoJSON() async throws {
        let gpx = """
        <gpx version="1.1"><metadata><name>ignored</name></metadata>
        <wpt lat="10.5" lon="106.7"><name>A</name><desc>d</desc></wpt>
        <rte><name>R</name><rtept lat="1" lon="2"/><rtept lat="3" lon="4"/></rte></gpx>
        """
        let json = try await convert(gpx, file: "t.gpx", to: "geojson")
        let features = try GeoJSONCodec.parse(Data(json.utf8))
        #expect(features.count == 2)
        #expect(features[0].geometry == .point(try GeoCoordinate(lon: 106.7, lat: 10.5)))
        #expect(features[0].name == "A" && features[0].description == "d")
        #expect(features[1].geometry == .lineString([try GeoCoordinate(lon: 2, lat: 1), try GeoCoordinate(lon: 4, lat: 3)]))
    }

    @Test func kmlMultiGeometryAndCDATA() throws {
        let kml = """
        <kml xmlns="http://www.opengis.net/kml/2.2"><Document><Placemark><name>M</name><description><![CDATA[<b>x</b>]]></description>
        <MultiGeometry><Point><coordinates>1,2</coordinates></Point><Point><coordinates>3,4,5</coordinates></Point></MultiGeometry></Placemark>
        <Placemark><name>none</name></Placemark></Document></kml>
        """
        let features = try GeoKMLCodec.parse(Data(kml.utf8))
        #expect(features.count == 1)
        #expect(features[0].description == "<b>x</b>")
        #expect(features[0].geometry == .multiPoint([try GeoCoordinate(lon: 1, lat: 2), try GeoCoordinate(lon: 3, lat: 4, ele: 5)]))
    }

    @Test func csvHasOneRowPerVertexLatBeforeLon() async throws {
        let csv = try await convert(geojson, file: "a.geojson", to: "csv")
        let lines = csv.split(separator: "\n")
        #expect(lines[0] == "name,lat,lon,ele")
        #expect(lines[1].hasSuffix(",21.0287,105.8522,12.5"))
        let expectedRows: Int = 15
        #expect(lines.count == expectedRows)
        #expect(lines[1].hasPrefix("\"Hồ <Gươm> & \"\"Tháp\"\"\""))
    }

    @Test func kmzIsReadThroughDitto() async throws {
        let dir = try ConverterFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let staging = dir.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let kml = "<kml><Placemark><name>K</name><Point><coordinates>106,10</coordinates></Point></Placemark></kml>"
        try Data(kml.utf8).write(to: staging.appendingPathComponent("doc.kml"))
        let kmz = dir.appendingPathComponent("a.kmz")
        try await ConverterWorkspace.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", staging.path, kmz.path])
        let json = try await convert(kmz, to: "geojson", in: dir)
        #expect(try GeoJSONCodec.parse(Data(json.utf8)).first?.name == "K")
    }

    @Test func invalidInputIsRejected() async throws {
        await #expect(throws: ConversionError.self) { _ = try await convert("{\"type\":\"Point\",\"coordinates\":[200,95]}", file: "a.geojson", to: "kml") }
        await #expect(throws: ConversionError.self) { _ = try await convert("<gpx><wpt lat=\"x\" lon=\"1\"/></gpx>", file: "a.gpx", to: "kml") }
        await #expect(throws: ConversionError.self) { _ = try await convert("not xml", file: "a.kml", to: "gpx") }
    }
}
