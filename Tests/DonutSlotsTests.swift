import Foundation
import Testing
@testable import Xmac

@Suite struct DonutSlotsTests {
    private func targets(_ count: Int) -> [ConversionTarget] {
        (0..<count).map { ConversionTarget(id: "image.t\($0)", title: "T\($0)", fileExtension: "t\($0)", group: .image) }
    }

    private func titles(_ slots: [DonutSlot]) -> [String] { slots.map(\.title) }

    @Test func upToEightTargetsGetOneSliceEach() {
        let slots = DonutSlot.make(targets: targets(8), recentIDs: [])
        #expect(slots.count == 8)
        #expect(!slots.contains(.more))
    }

    @Test func moreThanEightTurnsLastSliceIntoMore() {
        let slots = DonutSlot.make(targets: targets(12), recentIDs: [])
        #expect(slots.count == DonutGeometry.maxSlots)
        #expect(slots.last == .more)
        #expect(titles(slots).last == "Khác…")
        #expect(titles(slots).prefix(7).elementsEqual((0..<7).map { "T\($0)" }))
    }

    @Test func recentTargetsComeFirstNewestFirst() {
        let slots = DonutSlot.make(targets: targets(5), recentIDs: ["image.t3", "image.t1", "unknown.x"])
        #expect(titles(slots) == ["T3", "T1", "T0", "T2", "T4"])
    }

    @Test func recentTargetBeyondEighthIsPromotedIntoVisibleSlices() {
        let slots = DonutSlot.make(targets: targets(12), recentIDs: ["image.t11"])
        #expect(titles(slots).first == "T11")
    }

    @Test func recordKeepsNewestFirstWithoutDuplicatesAndCapsList() throws {
        let suite = "DonutSlotsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DonutRecentTargets(defaults: defaults)
        store.record("a")
        store.record("b")
        store.record("a")
        #expect(store.ids == ["a", "b"])
        (0..<30).forEach { store.record("id\($0)") }
        #expect(store.ids.count == DonutRecentTargets.limit)
        #expect(store.ids.first == "id29")
    }
}
