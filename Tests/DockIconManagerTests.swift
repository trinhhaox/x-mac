import Foundation
import Testing
@testable import Xmac

@Suite struct DockIconManagerTests {
    @Test func dockIconIsHiddenByDefaultAndRemembersTheChoice() {
        let suiteName = "XmacTests.DockIcon.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!DockIconManager(defaults: defaults).showsDockIcon)
        defaults.set(true, forKey: "XmacShowDockIcon")
        #expect(DockIconManager(defaults: defaults).showsDockIcon)
    }
}
