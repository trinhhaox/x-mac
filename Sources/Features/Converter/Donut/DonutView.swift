import AppKit

/// The ring itself: custom-drawn slices, highlight under the drag, drop handling.
final class DonutView: NSView {
    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    private let faces: [[DonutSlot]]
    private let side: CGFloat
    private var flipState: DonutFlipState
    private let summary: String
    private let onPick: (DonutSlot, BrowserDragPayload) -> Void
    private let onLeave: () -> Void
    private var hovered: Int?
    private var lastDragLocation: NSPoint?

    init(
        faces: [[DonutSlot]], side: CGFloat, summary: String,
        onPick: @escaping (DonutSlot, BrowserDragPayload) -> Void, onLeave: @escaping () -> Void
    ) {
        self.faces = faces
        self.side = side
        flipState = DonutFlipState(faceCount: faces.count)
        self.summary = summary
        self.onPick = onPick
        self.onLeave = onLeave
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        registerForDraggedTypes(BrowserDragPayload.registeredTypes + [Self.legacyFilenamesType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The face currently drawn; every hit-test and drop reads these two.
    private var slots: [DonutSlot] { faces[flipState.index] }
    private var geometry: DonutGeometry { DonutGeometry(slotCount: slots.count) }
    private var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            drawBackdrop()
            for index in slots.indices { drawSlice(index) }
            drawCentre()
        }
    }

    /// Fills the whole disc so the hole is hit-testable and the ring is readable on any background.
    private func drawBackdrop() {
        let rect = NSRect(x: centre.x - geometry.outerRadius, y: centre.y - geometry.outerRadius,
                          width: geometry.outerRadius * 2, height: geometry.outerRadius * 2)
        NSColor.windowBackgroundColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func slicePath(_ index: Int) -> NSBezierPath {
        // AppKit arcs are counter-clockwise degrees from +x; slices are clockwise radians from the top.
        let half = geometry.sliceAngle / 2
        let mid = geometry.midAngle(of: index)
        let start = 90 - (mid + half) * 180 / .pi
        let end = 90 - (mid - half) * 180 / .pi
        let path = NSBezierPath()
        path.appendArc(withCenter: centre, radius: geometry.outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.appendArc(withCenter: centre, radius: geometry.innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.close()
        return path
    }

    private func drawSlice(_ index: Int) {
        let path = slicePath(index)
        let isHovered = hovered == index
        (isHovered ? NSColor.controlAccentColor : NSColor.windowBackgroundColor.withAlphaComponent(0.9)).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        draw(L10n.text(slots[index].title), around: geometry.labelOffset(of: index), width: 64, height: 30,
             color: isHovered ? .alternateSelectedControlTextColor : .labelColor, weight: .medium, truncation: .byTruncatingTail)
    }

    private func drawCentre() {
        let side = geometry.innerRadius * 2 - 10
        let hasBack = flipState.faceCount > 1
        draw(summary, around: CGPoint(x: 0, y: hasBack ? 7 : 0), width: side, height: 28,
             color: .secondaryLabelColor, weight: .regular, truncation: .byTruncatingMiddle)
        if hasBack {
            draw(flipState.label, around: CGPoint(x: 0, y: -14), width: side, height: 14,
                 color: .tertiaryLabelColor, weight: .regular, truncation: .byClipping)
        }
    }

    private func draw(
        _ text: String, around offset: CGPoint, width: CGFloat, height: CGFloat,
        color: NSColor, weight: NSFont.Weight, truncation: NSLineBreakMode
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = truncation
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: weight), .foregroundColor: color, .paragraphStyle: style,
        ])
        let bounding = attributed.boundingRect(
            with: NSSize(width: width, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
        let rect = NSRect(x: centre.x + offset.x - width / 2, y: centre.y + offset.y - bounding.height / 2,
                          width: width, height: bounding.height)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // MARK: Faces

    /// Shows the other face; false when there is none.
    @discardableResult
    func flip() -> Bool {
        guard flipState.flip() else { return false }
        hovered = lastDragLocation.flatMap { slotIndex(at: $0) }
        needsDisplay = true
        animateFlip()
        return true
    }

    private func animateFlip() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        wantsLayer = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.25
        fade.toValue = 1
        fade.duration = 0.12
        layer?.add(fade, forKey: "flip")
    }

    // MARK: Drag destination

    private func slotIndex(at windowPoint: NSPoint) -> Int? {
        let point = convert(windowPoint, from: nil)
        return geometry.slotIndex(at: CGPoint(x: point.x - centre.x, y: point.y - centre.y))
    }

    private func track(_ info: NSDraggingInfo) -> NSDragOperation {
        lastDragLocation = info.draggingLocation
        let index = slotIndex(at: info.draggingLocation)
        if index != hovered {
            hovered = index
            needsDisplay = true
        }
        return index == nil ? [] : .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hovered = nil
        lastDragLocation = nil
        needsDisplay = true
        onLeave()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { slotIndex(at: sender.draggingLocation) != nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let index = slotIndex(at: sender.draggingLocation),
              let payload = BrowserDragPayload.parse(BrowserDragSnapshot(pasteboard: sender.draggingPasteboard)) else { return false }
        BrowserDropCoordinator.shared.begin(payload)
        onPick(slots[index], payload)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) { onLeave() }
}
