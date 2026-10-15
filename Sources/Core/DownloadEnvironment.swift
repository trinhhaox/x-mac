import Foundation
import Network

/// Owns exactly one idle-sleep assertion for the download queue.
final class DownloadEnvironment: ObservableObject {
    static let shared = DownloadEnvironment()
    @Published private(set) var online = false
    @Published private(set) var metered = false
    @Published var keepAwake: Bool {
        didSet {
            defaults.set(keepAwake, forKey: "Downloads.KeepAwake")
            updateActivity()
        }
    }
    @Published var avoidMetered: Bool {
        didSet {
            defaults.set(avoidMetered, forKey: "Downloads.AvoidMetered")
            onChange?()
        }
    }
    var onChange: (() -> Void)?
    private let monitor = NWPathMonitor()
    private let defaults: UserDefaults
    private var activity: NSObjectProtocol?
    private var running = false

    init(defaults: UserDefaults = .standard, startMonitoring: Bool = true) {
        self.defaults = defaults
        keepAwake = defaults.object(forKey: "Downloads.KeepAwake") as? Bool ?? true
        avoidMetered = defaults.bool(forKey: "Downloads.AvoidMetered")
        guard startMonitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateConnection(online: path.status == .satisfied, metered: path.isExpensive || path.isConstrained)
            }
        }
        monitor.start(queue: DispatchQueue(label: "vn.xmac.network"))
    }

    func updateConnection(online: Bool, metered: Bool) {
        self.online = online
        self.metered = metered
        onChange?()
        updateActivity()
    }

    func setRunning(_ value: Bool) {
        running = value
        updateActivity()
    }

    private func updateActivity() {
        let needed = Self.shouldKeepAwake(enabled: keepAwake, running: running, online: online)
        if needed, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled], reason: "Xmac đang tải tệp"
            )
        } else if !needed, let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
    }

    func stop() {
        monitor.cancel()
        setRunning(false)
    }

    static func shouldKeepAwake(enabled: Bool, running: Bool, online: Bool) -> Bool {
        enabled && running && online
    }
}
