import CoreGraphics

/// Pure state machine for the donut gesture: the user drags files first and presses ⌃ afterwards.
/// ⌃ held before the mouse went down never arms (⌃-click is a right click in Finder), and ⌃ pressed
/// together with ⌘⌥⇧ never arms. Releasing ⌃ (or adding another modifier) disarms; mouse-up resets.
struct DragGestureDetector {
    enum State: Equatable {
        case idle, pressed, dragging, armed
    }

    static let dragThreshold: CGFloat = 4

    private(set) var state: State = .idle
    private var origin = CGPoint.zero
    private var controlDown = false
    private var controlHeldAtPress = false

    mutating func mouseDown(at point: CGPoint, controlDown: Bool) {
        origin = point
        self.controlDown = controlDown
        controlHeldAtPress = controlDown
        state = .pressed
    }

    mutating func mouseDragged(to point: CGPoint) {
        guard state == .pressed else { return }
        if hypot(point.x - origin.x, point.y - origin.y) >= Self.dragThreshold {
            state = .dragging
        }
    }

    /// `others` is true when any of ⌘⌥⇧ is down.
    mutating func flagsChanged(control: Bool, others: Bool) {
        let wasDown = controlDown
        controlDown = control
        switch state {
        case .dragging:
            if control, !wasDown, !others, !controlHeldAtPress { state = .armed }
        case .armed:
            if !control || others { state = .dragging }
        case .idle, .pressed:
            break
        }
    }

    mutating func mouseUp() {
        self = DragGestureDetector()
    }
}
