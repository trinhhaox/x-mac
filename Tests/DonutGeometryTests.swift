import CoreGraphics
import Foundation
import Testing
@testable import Xmac

@Suite struct DonutGeometryTests {
    private let geometry = DonutGeometry(slotCount: 4, innerRadius: 40, outerRadius: 100)

    @Test func windowFitsRingWithMargin() {
        #expect(geometry.windowSide == (100 + DonutGeometry.margin) * 2)
    }

    @Test func slicesAreCentredClockwiseFromTop() {
        #expect(geometry.slotIndex(at: CGPoint(x: 0, y: 70)) == 0)
        #expect(geometry.slotIndex(at: CGPoint(x: 70, y: 0)) == 1)
        #expect(geometry.slotIndex(at: CGPoint(x: 0, y: -70)) == 2)
        #expect(geometry.slotIndex(at: CGPoint(x: -70, y: 0)) == 3)
    }

    @Test func sliceBoundaryBelongsToNextSlice() {
        let justBefore = CGPoint(x: 70 * sin(0.7853), y: 70 * cos(0.7853))
        let justAfter = CGPoint(x: 70 * sin(0.7855), y: 70 * cos(0.7855))
        #expect(geometry.slotIndex(at: justBefore) == 0)
        #expect(geometry.slotIndex(at: justAfter) == 1)
    }

    @Test func ringRadiiAreInclusiveAndHoleAndOutsideMiss() {
        #expect(geometry.slotIndex(at: .zero) == nil)
        #expect(geometry.slotIndex(at: CGPoint(x: 0, y: 39.9)) == nil)
        #expect(geometry.slotIndex(at: CGPoint(x: 0, y: 40)) == 0)
        #expect(geometry.slotIndex(at: CGPoint(x: 0, y: 100)) == 0)
        #expect(geometry.slotIndex(at: CGPoint(x: 0, y: 100.1)) == nil)
    }

    @Test func singleSlotCoversWholeRing() {
        let single = DonutGeometry(slotCount: 1)
        #expect(single.slotIndex(at: CGPoint(x: -70, y: -10)) == 0)
        #expect(single.slotIndex(at: CGPoint(x: 70, y: 10)) == 0)
    }

    @Test func labelOffsetSitsOnMidRing() {
        let offset = geometry.labelOffset(of: 1)
        #expect(abs(offset.x - 70) < 0.001)
        #expect(abs(offset.y) < 0.001)
    }

    @Test func centreIsClampedInsideScreen() {
        let frame = CGRect(x: 0, y: 25, width: 1000, height: 700)
        #expect(DonutGeometry.clampedCentre(CGPoint(x: 5, y: 30), in: frame, radius: 100) == CGPoint(x: 100, y: 125))
        #expect(DonutGeometry.clampedCentre(CGPoint(x: 999, y: 720), in: frame, radius: 100) == CGPoint(x: 900, y: 625))
        #expect(DonutGeometry.clampedCentre(CGPoint(x: 500, y: 300), in: frame, radius: 100) == CGPoint(x: 500, y: 300))
    }

    @Test func centreOnSecondaryScreenWithOffsetOrigin() {
        let frame = CGRect(x: -1440, y: 100, width: 1440, height: 800)
        #expect(DonutGeometry.clampedCentre(CGPoint(x: -1, y: 899), in: frame, radius: 100) == CGPoint(x: -100, y: 800))
    }

    @Test func frameSmallerThanDonutCentresOnAxis() {
        let frame = CGRect(x: 0, y: 0, width: 150, height: 150)
        #expect(DonutGeometry.clampedCentre(CGPoint(x: 0, y: 0), in: frame, radius: 100) == CGPoint(x: 75, y: 75))
    }

    @Test func slotCountIsClampedToAtLeastOne() {
        #expect(DonutGeometry(slotCount: 0).slotCount == 1)
    }
}
