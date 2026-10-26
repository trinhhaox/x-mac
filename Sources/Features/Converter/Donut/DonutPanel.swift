import AppKit

/// Borderless, non-activating drop target so Finder keeps focus while the drag continues.
final class DonutPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(centre: CGPoint, side: CGFloat, view: DonutView) {
        let frame = NSRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = view
    }
}
