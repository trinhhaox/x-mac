/// Detects a clean Control+Shift tap (the E/V language switch).
/// Arms when exactly Control+Shift are down, is cancelled by any key press or
/// extra modifier, and fires once on release so chords such as ⌃⇧Tab or
/// ⌃⇧⌘4 never toggle the language.
struct CtrlShiftToggleDetector {
    private var armed = false
    private var cancelled = false

    /// Returns true when the language should be toggled.
    mutating func handleFlagsChanged(control: Bool, shift: Bool, other: Bool) -> Bool {
        if !control && !shift && !other {
            let shouldToggle = armed && !cancelled
            self = CtrlShiftToggleDetector()
            return shouldToggle
        }
        if other { cancelled = true }
        if control && shift {
            armed = true
            return false
        }
        // One of the two modifiers was released: fire once, then wait for a full release.
        if armed {
            let shouldToggle = !cancelled
            armed = false
            cancelled = true
            return shouldToggle
        }
        return false
    }

    mutating func handleKeyDown() {
        if armed { cancelled = true }
    }

    mutating func reset() {
        self = CtrlShiftToggleDetector()
    }
}
