import Foundation
import Testing
@testable import Xmac

@Suite struct DonutFacesTests {
    private func targets(_ count: Int) -> [ConversionTarget] {
        (0..<count).map { ConversionTarget(id: "image.t\($0)", title: "T\($0)", fileExtension: "t\($0)", group: .image) }
    }

    private func titles(_ slots: [DonutSlot]) -> [String] { slots.map(\.title) }

    @Test func exactlyEightTargetsHaveNoBackFace() {
        let faces = DonutFaces(targets: targets(8), recentIDs: []).faces
        #expect(faces.count == 1)
        #expect(faces[0].count == 8)
        #expect(!faces[0].contains(.more))
    }

    @Test func nineTargetsPutTheRemainderOnTheBack() {
        let faces = DonutFaces(targets: targets(9), recentIDs: []).faces
        #expect(faces.count == 2)
        #expect(faces[0].last == .more)
        #expect(titles(faces[1]) == ["T7", "T8"])
    }

    @Test func backFaceHoldsUpToEightWithoutMore() {
        let faces = DonutFaces(targets: targets(15), recentIDs: []).faces
        #expect(titles(faces[1]) == (7..<15).map { "T\($0)" })
        #expect(!faces[1].contains(.more))
    }

    @Test func beyondSixteenBackFaceEndsWithMore() {
        let faces = DonutFaces(targets: targets(20), recentIDs: []).faces
        #expect(faces.count == 2)
        #expect(faces[1].count == DonutGeometry.maxSlots)
        #expect(faces[1].last == .more)
        #expect(titles(faces[1]).prefix(7).elementsEqual((7..<14).map { "T\($0)" }))
    }

    @Test func recentTargetsLeadTheFrontFace() {
        let faces = DonutFaces(targets: targets(12), recentIDs: ["image.t11"]).faces
        #expect(titles(faces[0]).first == "T11")
        #expect(!titles(faces[1]).contains("T11"))
    }

    @Test func flipCyclesFacesAndLabels() {
        var state = DonutFlipState(faceCount: 2)
        #expect(state.label == "1/2")
        let r1 = state.flip()
        #expect(r1)
        #expect(state.index == 1 && state.label == "2/2")
        let r2 = state.flip()
        #expect(r2)
        #expect(state.index == 0)
    }

    @Test func singleFaceNeverFlips() {
        var state = DonutFlipState(faceCount: 1)
        let r3 = state.flip()
        #expect(!r3)
        #expect(state.index == 0)
    }

    @Test func wheelNotchesCloserThanGapAreOneTurn() {
        var wheel = WheelTurnDebouncer()
        let r4 = wheel.isNewTurn(at: 10.0)
        #expect(r4)
        let r5 = wheel.isNewTurn(at: 10.1)
        #expect(!r5)
        let r6 = wheel.isNewTurn(at: 10.3)
        #expect(!r6)
        let r7 = wheel.isNewTurn(at: 10.6)
        #expect(r7)
    }

    @Test func pauseAtLeastTheGapStartsANewTurn() {
        var wheel = WheelTurnDebouncer()
        let r8 = wheel.isNewTurn(at: 1)
        #expect(r8)
        let r9 = wheel.isNewTurn(at: 1 + WheelTurnDebouncer.gap)
        #expect(r9)
    }
}
