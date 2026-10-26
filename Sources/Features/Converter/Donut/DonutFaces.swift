import Foundation

/// The donut's faces: the front holds the most relevant targets, the back (if any) the rest.
struct DonutFaces: Equatable {
    let faces: [[DonutSlot]]

    init(targets: [ConversionTarget], recentIDs: [String]) {
        let ordered = DonutRecentTargets.ordered(targets, recentIDs: recentIDs)
        let front = DonutSlot.face(ordered)
        // With overflow the front reserves its last slice for "Khác…", so the back starts after the targets shown.
        let rest = ordered.count > DonutGeometry.maxSlots ? Array(ordered.dropFirst(DonutGeometry.maxSlots - 1)) : []
        faces = rest.isEmpty ? [front] : [front, DonutSlot.face(rest)]
    }
}

/// Which face is drawn. Hit-testing, highlight and drop all read this one value.
struct DonutFlipState: Equatable {
    let faceCount: Int
    private(set) var index = 0

    init(faceCount: Int) {
        self.faceCount = max(faceCount, 1)
    }

    var label: String { "\(index + 1)/\(faceCount)" }

    /// Returns false when there is nothing to flip to.
    @discardableResult
    mutating func flip() -> Bool {
        guard faceCount > 1 else { return false }
        index = (index + 1) % faceCount
        return true
    }
}

/// Turns a stream of wheel notches into discrete turns: notches less than `gap` after the previous one
/// belong to the same turn, so a fast scroll (or trackpad inertia) flips once.
struct WheelTurnDebouncer {
    static let gap: TimeInterval = 0.25

    private var lastNotch: TimeInterval?

    /// `time` is the event timestamp (seconds); true when this notch starts a new turn.
    mutating func isNewTurn(at time: TimeInterval) -> Bool {
        defer { lastNotch = time }
        guard let last = lastNotch else { return true }
        return time - last >= Self.gap
    }
}
