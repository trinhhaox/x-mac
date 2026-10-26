import Foundation

enum DonutSlot: Equatable {
    case target(ConversionTarget)
    /// Opens the full target panel when there are more targets than slices.
    case more

    var title: String {
        switch self {
        case .target(let target): return target.title
        case .more: return "Khác…"
        }
    }

    /// At most `maxSlots` slices; with more targets the last slice is "Khác…".
    static func make(targets: [ConversionTarget], recentIDs: [String]) -> [DonutSlot] {
        let ordered = DonutRecentTargets.ordered(targets, recentIDs: recentIDs)
        guard ordered.count > DonutGeometry.maxSlots else { return ordered.map(DonutSlot.target) }
        return ordered.prefix(DonutGeometry.maxSlots - 1).map(DonutSlot.target) + [.more]
    }
}

/// Most-recently-used target ids, newest first. Ids are unique across converters, so one small
/// list also remembers the choice per file group.
struct DonutRecentTargets {
    static let key = "Converter.DonutRecentTargets"
    static let limit = 16

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ids: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    func record(_ id: String) {
        defaults.set(Array(([id] + ids.filter { $0 != id }).prefix(Self.limit)), forKey: Self.key)
    }

    /// Recent targets first (newest first), then the rest in their original order.
    static func ordered(_ targets: [ConversionTarget], recentIDs: [String]) -> [ConversionTarget] {
        let rank = Dictionary(recentIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = targets.filter { rank[$0.id] != nil }.sorted { rank[$0.id, default: 0] < rank[$1.id, default: 0] }
        return recent + targets.filter { rank[$0.id] == nil }
    }
}
