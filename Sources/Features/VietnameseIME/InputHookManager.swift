import Cocoa
import Carbon

public class InputHookManager: ObservableObject {
    public static let shared = InputHookManager()
    
    @Published public var isVietnameseMode: Bool = true {
        didSet {
            UserDefaults.standard.set(isVietnameseMode, forKey: "XmacIME_VietnameseMode")
        }
    }
    
    @Published public var typingMethod: TypingMethod = .telex {
        didSet {
            UserDefaults.standard.set(typingMethod.rawValue, forKey: "XmacIME_TypingMethod")
        }
    }
    
    @Published public var modernOrthography: Bool = true {
        didSet {
            UserDefaults.standard.set(modernOrthography, forKey: "XmacIME_ModernOrthography")
        }
    }
    
    @Published public var excludedApps: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.apple.dt.Xcode"
    ]
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentBuffer: String = ""
    private var isSimulating: Bool = false
    
    private init() {
        if UserDefaults.standard.object(forKey: "XmacIME_VietnameseMode") != nil {
            self.isVietnameseMode = UserDefaults.standard.bool(forKey: "XmacIME_VietnameseMode")
        }
        if let methodStr = UserDefaults.standard.string(forKey: "XmacIME_TypingMethod"),
           let method = TypingMethod(rawValue: methodStr) {
            self.typingMethod = method
        }
        if UserDefaults.standard.object(forKey: "XmacIME_ModernOrthography") != nil {
            self.modernOrthography = UserDefaults.standard.bool(forKey: "XmacIME_ModernOrthography")
        }
    }
    
    public func toggleLanguage() {
        self.isVietnameseMode.toggle()
        currentBuffer = ""
        SoundEffectManager.shared.play(.paste)
    }
    
    public func start() {
        guard eventTap == nil else { return }
        
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passRetained(event)
            }
            let manager = Unmanaged<InputHookManager>.fromOpaque(refcon).takeUnretainedValue()
            
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                manager.reenableTap()
                return Unmanaged.passRetained(event)
            }
            
            // Nếu đây là phím ảo do chính Xmac giả lập gửi ra, bỏ qua để không lặp vô tận
            if manager.isSimulating {
                return Unmanaged.passRetained(event)
            }
            
            // Xử lý phím tắt chuyển nhanh E/V (Control + Shift)
            if type == .flagsChanged {
                let flags = event.flags
                if flags.contains(.maskControl) && flags.contains(.maskShift) {
                    DispatchQueue.main.async {
                        manager.toggleLanguage()
                    }
                }
                return Unmanaged.passRetained(event)
            }
            
            guard type == .keyDown else {
                return Unmanaged.passRetained(event)
            }
            
            return manager.handleKeyDown(event: event)
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
            NSLog("Xmac IME: Không thể tạo CGEvent tap. Cần cấp quyền Accessibility.")
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
    
    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        // Nếu có Command, Option hoặc Control -> Phím tắt ứng dụng, reset buffer và bỏ qua
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) {
            currentBuffer = ""
            return Unmanaged.passRetained(event)
        }
        
        // Kiểm tra App đang active
        if let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if excludedApps.contains(frontApp) {
                currentBuffer = ""
                return Unmanaged.passRetained(event)
            }
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Phím Delete / Backspace (keyCode = 51)
        if keyCode == 51 {
            if !currentBuffer.isEmpty {
                currentBuffer.removeLast()
            }
            return Unmanaged.passRetained(event)
        }
        
        // Lấy ký tự Unicode
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        
        guard length > 0, let scalar = UnicodeScalar(chars[0]) else {
            currentBuffer = ""
            return Unmanaged.passRetained(event)
        }
        
        let char = Character(scalar)
        
        // Phím phân tách từ: Space, Return, Tab, dấu câu
        if char == " " || char == "\n" || char == "\t" || ",.!?;:()[]{}\"'".contains(char) {
            // Kiểm tra Macro
            if char == " " && MacroManager.shared.isMacroEnabled {
                if let expansion = MacroManager.shared.getExpansion(for: currentBuffer) {
                    let oldLen = currentBuffer.count
                    currentBuffer = ""
                    replaceWord(backspaceCount: oldLen, newText: expansion + " ")
                    return nil // Nuốt phím space vì đã gửi kèm trong expansion
                }
            }
            currentBuffer = ""
            return Unmanaged.passRetained(event)
        }
        
        // Nếu đang ở chế độ Tiếng Anh (E), chỉ lưu buffer cơ bản và cho qua
        guard isVietnameseMode else {
            currentBuffer.append(char)
            return Unmanaged.passRetained(event)
        }
        
        // Xử lý Tiếng Việt qua Engine
        let (transformed, didTransform) = VietnameseEngine.shared.processWord(
            currentWord: currentBuffer,
            newChar: char,
            method: typingMethod,
            modernOrthography: modernOrthography
        )
        
        if didTransform {
            let backspaces = currentBuffer.count
            currentBuffer = transformed
            replaceWord(backspaceCount: backspaces, newText: transformed)
            return nil // Nuốt sự kiện gốc
        } else {
            currentBuffer.append(char)
            return Unmanaged.passRetained(event)
        }
    }
    
    private func replaceWord(backspaceCount: Int, newText: String) {
        self.isSimulating = true
        
        let src = CGEventSource(stateID: .combinedSessionState)
        
        // 1. Gửi backspace để xoá từ cũ
        for _ in 0..<backspaceCount {
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true),
               let up = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
        
        // 2. Gửi chuỗi ký tự mới
        let utf16 = Array(newText.utf16)
        if let keyEvent = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
            keyEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyEvent.post(tap: .cghidEventTap)
        }
        if let keyUpEvent = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            keyUpEvent.post(tap: .cghidEventTap)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.isSimulating = false
        }
    }
}
