import CoreGraphics

/// Pure layout maths for the donut. Slot 0 is centred at the top; slots run clockwise.
/// Offsets are relative to the donut centre with y pointing up (AppKit view coordinates).
struct DonutGeometry: Equatable {
    static let maxSlots = 8
    static let margin: CGFloat = 6

    let slotCount: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    init(slotCount: Int, innerRadius: CGFloat = 40, outerRadius: CGFloat = 112) {
        self.slotCount = max(slotCount, 1)
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
    }

    /// Side of the square window that holds the donut.
    var windowSide: CGFloat { (outerRadius + Self.margin) * 2 }

    var sliceAngle: Double { 2 * .pi / Double(slotCount) }

    /// Clockwise angle from the top, in radians, of the slice middle.
    func midAngle(of index: Int) -> Double { Double(index) * sliceAngle }

    func labelOffset(of index: Int) -> CGPoint {
        let radius = Double(innerRadius + outerRadius) / 2
        let angle = midAngle(of: index)
        return CGPoint(x: radius * sin(angle), y: radius * cos(angle))
    }

    /// Slice under `offset`; nil in the hole and outside the ring (radii inclusive).
    func slotIndex(at offset: CGPoint) -> Int? {
        let distance = hypot(offset.x, offset.y)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        var angle = atan2(Double(offset.x), Double(offset.y))
        if angle < 0 { angle += 2 * .pi }
        return Int((angle + sliceAngle / 2) / sliceAngle) % slotCount
    }

    /// Moves `point` so a circle of `radius` stays inside `frame`; centred on an axis the frame cannot fit.
    static func clampedCentre(_ point: CGPoint, in frame: CGRect, radius: CGFloat) -> CGPoint {
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            low > high ? (low + high) / 2 : min(max(value, low), high)
        }
        return CGPoint(
            x: clamp(point.x, frame.minX + radius, frame.maxX - radius),
            y: clamp(point.y, frame.minY + radius, frame.maxY - radius)
        )
    }
}
