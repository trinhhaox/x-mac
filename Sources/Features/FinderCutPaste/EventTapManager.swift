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

    private static let shortcutKeyCodes: Set<Int64> = [6, 7, 8, 9] // Z, X, C, V

    /// Cheap, thread-safe pre-check run on the event tap thread: only events
    /// that can be a Finder shortcut are handed to `handleIfNeeded` on main.
    static func isShortcutCandidate(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        let flags = event.flags
        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else { return false }
        return shortcutKeyCodes.contains(event.getIntegerValueField(.keyboardEventKeycode))
    }

    /// Returns true when the event was consumed as a Finder cut/paste/undo shortcut.
    /// Main thread only.
    static func handleIfNeeded(type: CGEventType, event: CGEvent) -> Bool {
        guard isShortcutCandidate(type: type, event: event) else { return false }
        guard FinderCutPasteManager.shared.isEnabled else { return false }

        let flags = event.flags
        let isShift = flags.contains(.maskShift)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
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
