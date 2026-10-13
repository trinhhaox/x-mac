import Cocoa

public class EventTapManager {
    public static let shared = EventTapManager()

    private init() {}

    public func start() {
        GlobalEventTap.shared.start()
    }

    public func stop() {
        // Cut/Paste off must not tear down the shared IME tap.
    }

    /// Returns true when the event was consumed as a Finder cut/paste/undo shortcut.
    static func handleIfNeeded(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        guard FinderCutPasteManager.shared.isEnabled else { return false }

        let flags = event.flags
        let isCommand = flags.contains(.maskCommand)
        let isControl = flags.contains(.maskControl)
        let isOption = flags.contains(.maskAlternate)
        let isShift = flags.contains(.maskShift)

        guard isCommand && !isControl && !isOption else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 7 || keyCode == 9 || keyCode == 6 || keyCode == 8 else {
            return false
        }
        guard FinderBridge.isFinderActive() else { return false }
        if FinderBridge.isRenamingFile() { return false }

        let cutPaste = FinderCutPasteManager.shared
        if keyCode == 7 && !isShift {
            return cutPaste.handleCut()
        }
        if keyCode == 9 && !isShift {
            return cutPaste.handlePaste()
        }
        if keyCode == 6 && !isShift {
            return cutPaste.handleUndo()
        }
        if keyCode == 8 && !isShift {
            cutPaste.handleCopy()
        }
        return false
    }
}
