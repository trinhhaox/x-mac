import Foundation
import Testing
@testable import Xmac

@MainActor
@Suite struct ConverterManagerTests {
    private final class Alerts {
        var notifications: [(title: String, paths: [String])] = []
        var sounds: [SoundEffectManager.SoundType] = []
    }

    private func makeManager(
        _ converter: FakeConverter, defaults: UserDefaults, alerts: Alerts
    ) -> ConverterManager {
        ConverterManager(
            registry: ConverterRegistry(converters: [converter], locator: BinaryLocator(defaults: defaults)),
            defaults: defaults,
            notify: { alerts.notifications.append(($0, $1)) },
            playSound: { alerts.sounds.append($0) }
        )
    }

    private func waitUntilFinished(_ manager: ConverterManager) async -> Bool {
        for _ in 0..<500 {
            if !manager.jobs.isEmpty, manager.jobs.allSatisfy({ $0.state.isFinished }) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private func setUpFiles(_ names: [String]) throws -> (URL, [URL]) {
        let dir = try ConverterFixtures.makeTempDirectory()
        let urls = try names.map { name -> URL in
            let url = dir.appendingPathComponent(name)
            try Data("in".utf8).write(to: url)
            return url
        }
        return (dir, urls)
    }

    @Test func batchPostsOneNotificationAndPersistsRecent() async throws {
        let defaults = UserDefaults(suiteName: "manager-\(UUID().uuidString)")!
        let (dir, inputs) = try setUpFiles(["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let alerts = Alerts()
        let converter = FakeConverter()
        let manager = makeManager(converter, defaults: defaults, alerts: alerts)
        let target = converter.targets(for: inputs[0])[0]
        #expect(manager.enqueue(inputs: inputs, target: target).count == 2)
        #expect(await waitUntilFinished(manager))
        #expect(alerts.notifications.count == 1)
        #expect(alerts.notifications[0].paths.count == 2)
        #expect(alerts.sounds == [.done])
        #expect(manager.recent.count == 2)
        let reloaded = makeManager(converter, defaults: defaults, alerts: Alerts())
        #expect(reloaded.recent.map(\.id) == manager.recent.map(\.id))
    }

    @Test func notificationCanBeDisabledAndFailuresAreReported() async throws {
        let defaults = UserDefaults(suiteName: "manager-\(UUID().uuidString)")!
        let (dir, inputs) = try setUpFiles(["a.txt"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let alerts = Alerts()
        let converter = FakeConverter(behavior: .fail)
        let manager = makeManager(converter, defaults: defaults, alerts: alerts)
        manager.notifyOnFinish = false
        manager.enqueue(inputs: inputs, target: converter.targets(for: inputs[0])[0])
        #expect(await waitUntilFinished(manager))
        #expect(alerts.notifications.isEmpty)
        #expect(alerts.sounds == [.error])
        #expect(manager.jobs[0].state == .failed("boom"))
        #expect(manager.recent.isEmpty)
    }

    @Test func cancelAllMarksJobsCancelledWithoutNotification() async throws {
        let defaults = UserDefaults(suiteName: "manager-\(UUID().uuidString)")!
        let (dir, inputs) = try setUpFiles(["a.txt"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let alerts = Alerts()
        let converter = FakeConverter(behavior: .hang)
        let manager = makeManager(converter, defaults: defaults, alerts: alerts)
        manager.enqueue(inputs: inputs, target: converter.targets(for: inputs[0])[0])
        manager.cancelAll()
        #expect(await waitUntilFinished(manager))
        #expect(manager.jobs[0].state == .cancelled)
        #expect(alerts.notifications.isEmpty && alerts.sounds.isEmpty)
    }

    @Test func presetAndRecentLimitPersist() {
        let defaults = UserDefaults(suiteName: "manager-\(UUID().uuidString)")!
        let manager = makeManager(FakeConverter(), defaults: defaults, alerts: Alerts())
        manager.preset.maxImageDimension = 1024
        manager.preset.imageQuality = 0.5
        let reloaded = makeManager(FakeConverter(), defaults: defaults, alerts: Alerts())
        #expect(reloaded.preset.maxImageDimension == 1024 && reloaded.preset.imageQuality == 0.5)
        #expect(reloaded.notifyOnFinish)
    }
}
