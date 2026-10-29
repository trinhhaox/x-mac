import Foundation

/// User preferences for plug/unplug notifications and per-drive automatic NTFS write mode.
public final class DiskAutomationSettings: ObservableObject {
    public static let shared = DiskAutomationSettings()

    static let notifyKey = "disk.notifyOnPlugEvents"
    static let autoWriteKey = "disk.autoWriteNTFSVolumeUUIDs"

    private let defaults: UserDefaults

    @Published public var notifyOnPlugEvents: Bool {
        didSet { defaults.set(notifyOnPlugEvents, forKey: Self.notifyKey) }
    }

    /// Keyed by volume UUID so the preference follows the drive across ports and re-plugs.
    @Published public private(set) var autoWriteVolumeUUIDs: Set<String> {
        didSet { defaults.set(Array(autoWriteVolumeUUIDs).sorted(), forKey: Self.autoWriteKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notifyOnPlugEvents = (defaults.object(forKey: Self.notifyKey) as? Bool) ?? true
        autoWriteVolumeUUIDs = Set(defaults.stringArray(forKey: Self.autoWriteKey) ?? [])
    }

    public func isAutoWriteEnabled(for volume: DiskVolume) -> Bool {
        guard let uuid = volume.volumeUUID else { return false }
        return autoWriteVolumeUUIDs.contains(uuid)
    }

    public func setAutoWrite(_ enabled: Bool, for volume: DiskVolume) {
        guard volume.isNTFS, let uuid = volume.volumeUUID else { return }
        if enabled {
            autoWriteVolumeUUIDs.insert(uuid)
        } else {
            autoWriteVolumeUUIDs.remove(uuid)
        }
    }
}
