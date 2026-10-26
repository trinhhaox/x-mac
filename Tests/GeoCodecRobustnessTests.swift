import Foundation
import Testing
@testable import Xmac

@Suite struct GeoCodecRobustnessTests {
    private func kml(_ inner: String) -> Data { Data("<kml><Document>\(inner)</Document></kml>".utf8) }

    @Test func multiGeometryOutsidePlacemarkDoesNotTrap() throws {
        let features = try GeoKMLCodec.parse(kml("<MultiGeometry><Point><coordinates>1,2</coordinates></Point></MultiGeometry>"))
        #expect(features.isEmpty)
    }

    @Test func oddNestingNeverTraps() throws {
        let fragments = [
            "<MultiGeometry><MultiGeometry/></MultiGeometry>",
            "<Placemark><MultiGeometry><Placemark><Point><coordinates>1,2</coordinates></Point></Placemark></MultiGeometry></Placemark>",
            "<Placemark><Placemark><MultiGeometry/></Placemark></Placemark>",
            "<Placemark><Polygon><Polygon/></Polygon></Placemark>",
            "<LinearRing><coordinates>1,2 3,4</coordinates></LinearRing><Polygon/>",
            "<Placemark><MultiGeometry><Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 1,1 1,0 0,0</coordinates></LinearRing></outerBoundaryIs></Polygon></MultiGeometry></Placemark></MultiGeometry>",
        ]
        for fragment in fragments { _ = try? GeoKMLCodec.parse(kml(fragment)) }
        for gpx in ["<gpx><trkpt lat=\"1\" lon=\"2\"/></gpx>", "<gpx><trk><trk><trkseg/></trk></trk></gpx>", "<gpx><ele>3</ele><name>x</name></gpx>"] {
            _ = try? GeoGPXCodec.parse(Data(gpx.utf8))
        }
    }

    @Test func pointWithoutCoordinatesDoesNotReuseEarlierOnes() throws {
        let features = try GeoKMLCodec.parse(kml("""
        <Placemark><Point><coordinates>1,2</coordinates></Point></Placemark><Placemark><Point/></Placemark>
        """))
        #expect(features.count == 1)
    }

    @Test func polygonWithoutRingsIsSkipped() throws {
        let features = try GeoKMLCodec.parse(kml("<Placemark><name>x</name><Polygon/></Placemark>"))
        #expect(features.isEmpty)
    }

    @Test func csvNeutralisesTabAndCarriageReturnPrefixes() throws {
        let c = try GeoCoordinate(lon: 1, lat: 2)
        let csv = GeoText.csv([
            GeoFeature(name: "\tcmd", description: nil, geometry: .point(c)),
            GeoFeature(name: "\r\nx", description: nil, geometry: .point(c)),
        ])
        #expect(csv.contains("'\tcmd,") && csv.contains("\"'\r\nx\","))
    }
}
