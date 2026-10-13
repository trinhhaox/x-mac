import Cocoa

public class EventTapManager {
    public static let shared = EventTapManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private init() {}
    
    public func start() {
        guard eventTap == nil else { return }
        
        let mask = (1 << CGEventType.keyDown.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                    manager.reenableTap()
                }
                return Unmanaged.passRetained(event)
            }
            
            guard type == .keyDown else {
                return Unmanaged.passRetained(event)
            }
            
            let flags = event.flags
            let isCommand = flags.contains(.maskCommand)
            let isControl = flags.contains(.maskControl)
            let isOption = flags.contains(.maskAlternate)
            let isShift = flags.contains(.maskShift)
            
            // Chỉ can thiệp khi có Command và không có Control / Option
            guard isCommand && !isControl && !isOption else {
                return Unmanaged.passRetained(event)
            }
            
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // 7: X, 9: V, 6: Z, 8: C
            if keyCode == 7 || keyCode == 9 || keyCode == 6 || keyCode == 8 {
                // Kiểm tra Finder có đang active không
                if FinderBridge.isFinderActive() {
                    // Nếu đang đổi tên file, để Finder xử lý text mặc định
                    if FinderBridge.isRenamingFile() {
                        return Unmanaged.passRetained(event)
                    }
                    
                    let cutPaste = FinderCutPasteManager.shared
                    
                    if keyCode == 7 && !isShift { // ⌘X: Cut
                        if cutPaste.handleCut() {
                            return nil // Nuốt sự kiện vì Finder không có ⌘X cho file
                        }
                    } else if keyCode == 9 && !isShift { // ⌘V: Paste
                        if cutPaste.handlePaste() {
                            return nil // Nuốt sự kiện nếu paste file cut thành công
                        }
                    } else if keyCode == 6 && !isShift { // ⌘Z: Undo
                        if cutPaste.handleUndo() {
                            return nil
                        }
                    } else if keyCode == 8 && !isShift { // ⌘C: Copy bình thường
                        cutPaste.handleCopy()
                    }
                }
            }
            
            return Unmanaged.passRetained(event)
        }
        
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: selfPtr
        )
        
        guard let tap = eventTap else {
            NSLog("Xmac: Không thể tạo CGEvent tap. Vui lòng cấp quyền Accessibility.")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }
    
    private func reenableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}
