import Testing
import Foundation
@testable import Xmac

@Suite struct NotificationRouterTests {
    @Test func pathsMapToReveal() {
        let action = NotificationRouter.action(for: ["paths": ["/tmp/a.png", "/tmp/b.png"]])
        #expect(action == .reveal([URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]))
    }

    @Test func tabMapsToOpenTab() {
        let action = NotificationRouter.action(for: ["tab": NavigationTab.deduplicator.rawValue])
        #expect(action == .openTab(.deduplicator))
    }

    @Test func pathsTakePrecedenceOverTab() {
        let action = NotificationRouter.action(for: ["paths": ["/tmp/a"], "tab": NavigationTab.settings.rawValue])
        #expect(action == .reveal([URL(fileURLWithPath: "/tmp/a")]))
    }

    @Test func malformedInputYieldsNil() {
        #expect(NotificationRouter.action(for: [:]) == nil)
        #expect(NotificationRouter.action(for: ["paths": [String]()]) == nil)
        #expect(NotificationRouter.action(for: ["paths": [""]]) == nil)
        #expect(NotificationRouter.action(for: ["paths": "not-an-array"]) == nil)
        #expect(NotificationRouter.action(for: ["tab": "Không tồn tại"]) == nil)
    }
}
