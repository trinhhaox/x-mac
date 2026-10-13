import Foundation

public struct MacroItem: Identifiable, Codable, Hashable {
    public var id: String { shortcut }
    public let shortcut: String
    public let expansion: String
}

public class MacroManager: ObservableObject {
    public static let shared = MacroManager()
    
    @Published public var macros: [MacroItem] = []
    @Published public var isMacroEnabled: Bool = true
    
    private let storageKey = "XmacSavedMacros"
    
    private init() {
        loadMacros()
    }
    
    public func loadMacros() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([MacroItem].self, from: data) {
            self.macros = saved
        } else {
            // Mẫu gõ tắt thông dụng mặc định
            self.macros = [
                MacroItem(shortcut: "vn", expansion: "Việt Nam"),
                MacroItem(shortcut: "dc", expansion: "được"),
                MacroItem(shortcut: "ko", expansion: "không"),
                MacroItem(shortcut: "k", expansion: "không"),
                MacroItem(shortcut: "ng", expansion: "người"),
                MacroItem(shortcut: "thks", expansion: "cảm ơn")
            ]
            saveMacros()
        }
    }
    
    public func addMacro(shortcut: String, expansion: String) {
        let trimmedShortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedShortcut.isEmpty, !trimmedExpansion.isEmpty else { return }
        
        macros.removeAll { $0.shortcut == trimmedShortcut }
        macros.append(MacroItem(shortcut: trimmedShortcut, expansion: trimmedExpansion))
        saveMacros()
    }
    
    public func removeMacro(shortcut: String) {
        macros.removeAll { $0.shortcut == shortcut }
        saveMacros()
    }
    
    public func getExpansion(for shortcut: String) -> String? {
        guard isMacroEnabled else { return nil }
        return macros.first { $0.shortcut == shortcut }?.expansion
    }
    
    private func saveMacros() {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
