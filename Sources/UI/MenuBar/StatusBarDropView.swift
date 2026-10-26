import AppKit

/// Transparent overlay on the status item button that accepts file drops and links, images and downloads dragged from a browser.
/// It does not handle mouse events itself, so clicks reach the button through the responder chain.
final class StatusBarDropView: NSView {
    var onDrop: ((BrowserDragPayload, NSPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(BrowserDragPayload.registeredTypes)
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.payload(from: sender) != nil else { return [] }
        setHighlighted(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setHighlighted(false) }

    override func draggingEnded(_ sender: NSDraggingInfo) { setHighlighted(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHighlighted(false)
        guard let payload = Self.payload(from: sender), let window else { return false }
        BrowserDropCoordinator.shared.begin(payload)
        let frame = window.convertToScreen(convert(bounds, to: nil))
        onDrop?(payload, NSPoint(x: frame.midX, y: frame.minY))
        return true
    }

    /// A bare page link would download HTML, so a link is only taken when it names a known file type or comes with an image.
    private static func payload(from info: NSDraggingInfo) -> BrowserDragPayload? {
        let snapshot = BrowserDragSnapshot(pasteboard: info.draggingPasteboard)
        guard let payload = BrowserDragPayload.parse(snapshot) else { return nil }
        if case .remote = payload, payload.expectedExtension == nil, !snapshot.hasImage { return nil }
        return payload
    }

    private func setHighlighted(_ highlighted: Bool) {
        (superview as? NSButton)?.isHighlighted = highlighted
    }
}
