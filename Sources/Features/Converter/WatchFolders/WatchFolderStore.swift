import Foundation

/// Watch rules, the master switch and the processed-file memory, all persisted in UserDefaults.
@MainActor
final class WatchFolderStore: ObservableObject {
    static let shared = WatchFolderStore()
    static let rulesKey = "Converter.WatchFolders.v1"
    static let enabledKey = "Converter.WatchFoldersEnabled"
    static let processedKey = "Converter.WatchProcessed.v1"

    @Published var rules: [WatchFolderRule] {
        didSet { Self.save(rules, key: Self.rulesKey, to: defaults) }
    }
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }
    private(set) var processed: WatchProcessedSet
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = Self.load([WatchFolderRule].self, key: Self.rulesKey, from: defaults) ?? []
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        processed = Self.load(WatchProcessedSet.self, key: Self.processedKey, from: defaults) ?? WatchProcessedSet()
    }

    func updateProcessed(_ change: (inout WatchProcessedSet) -> Void) {
        change(&processed)
        Self.save(processed, key: Self.processedKey, to: defaults)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            NSLog("WatchFolders: dropping unreadable \(key): \(error)")
            return nil
        }
    }

    private static func save<T: Encodable>(_ value: T, key: String, to defaults: UserDefaults) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            NSLog("WatchFolders: could not save \(key): \(error)")
        }
    }
}
