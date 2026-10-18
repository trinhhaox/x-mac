import Foundation
import Testing
@testable import Xmac

@Suite(.serialized) struct CleanerUninstallerTests {
    @Test func systemAppDecisionAllowsAppleAppsInApplications() {
        #expect(!AppUninstallPolicy.isSystemApp(bundlePath: "/Applications/Xcode.app", bundleIdentifier: "com.apple.dt.Xcode"))
        #expect(!AppUninstallPolicy.isSystemApp(bundlePath: "/Applications/Pages.app", bundleIdentifier: "com.apple.iWork.Pages"))
        #expect(AppUninstallPolicy.isSystemApp(bundlePath: "/System/Applications/Notes.app", bundleIdentifier: "com.apple.Notes"))
        #expect(AppUninstallPolicy.isSystemApp(bundlePath: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari"))
        #expect(AppUninstallPolicy.isSystemApp(bundlePath: "/System/Library/CoreServices/Finder.app", bundleIdentifier: "com.apple.finder"))
    }

    @Test func pathComponentSanitizationRejectsTraversal() {
        #expect(AppUninstallPolicy.isSafePathComponent("com.example.app"))
        #expect(AppUninstallPolicy.isSafePathComponent("My App"))
        #expect(!AppUninstallPolicy.isSafePathComponent(""))
        #expect(!AppUninstallPolicy.isSafePathComponent("../../Documents"))
        #expect(!AppUninstallPolicy.isSafePathComponent("a/b"))
        #expect(!AppUninstallPolicy.isSafePathComponent("a\0b"))
    }

    @Test func runningAppCachesAreSkipped() {
        let running: Set<String> = ["com.example.app"]
        #expect(CleanerItemPolicy.shouldSkip(itemName: "com.example.app", runningBundleIdentifiers: running))
        #expect(CleanerItemPolicy.shouldSkip(itemName: "com.example.app.ShipIt", runningBundleIdentifiers: running))
        #expect(!CleanerItemPolicy.shouldSkip(itemName: "com.example.application", runningBundleIdentifiers: running))
        #expect(!CleanerItemPolicy.shouldSkip(itemName: "com.other.app", runningBundleIdentifiers: running))
        #expect(!CleanerItemPolicy.shouldSkip(itemName: "anything", runningBundleIdentifiers: []))
    }

    @Test func onlyTrashContentsArePermanentlyRemoved() {
        let home = "/Users/tester"
        #expect(CleanerItemPolicy.isInTrash(path: "\(home)/.Trash/old.zip", homeDirectory: home))
        #expect(!CleanerItemPolicy.isInTrash(path: "\(home)/.Trash", homeDirectory: home))
        #expect(!CleanerItemPolicy.isInTrash(path: "\(home)/Library/Caches/x", homeDirectory: home))
    }

    private func makeApp(files: [(String, Bool)], bundlePath: String) -> InstalledAppItem {
        InstalledAppItem(
            name: "Demo",
            bundleIdentifier: "com.example.demo",
            bundlePath: bundlePath,
            version: "1.0",
            isSystemApp: false,
            associatedFiles: files.map { path, selected in
                AppAssociatedFile(
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    fileType: "Test",
                    size: 1,
                    confidence: .verified,
                    isSelected: selected
                )
            },
            isSelected: false
        )
    }

    @Test func uninstallTrashesBundleFirstThenSupportFiles() throws {
        let home = NSHomeDirectory()
        let bundle = "/Applications/Demo.app"
        let support = "\(home)/Library/Caches/com.example.demo"
        let app = makeApp(files: [(support, true), (bundle, true)], bundlePath: bundle)
        var order: [String] = []
        let result = AppUninstallerEngine.performUninstall(app) { order.append($0.path) }
        #expect(result == .ok)
        #expect(order == [bundle, support])
    }

    @Test func bundleFailureAbortsBeforeTouchingSupportFiles() {
        let home = NSHomeDirectory()
        let bundle = "/Applications/Demo.app"
        let support = "\(home)/Library/Caches/com.example.demo"
        let app = makeApp(files: [(bundle, true), (support, true)], bundlePath: bundle)
        var attempted: [String] = []
        let result = AppUninstallerEngine.performUninstall(app) { url in
            attempted.append(url.path)
            throw CocoaError(.fileWriteNoPermission)
        }
        #expect(!result.success)
        #expect(attempted == [bundle])
        #expect(result.failedPaths == [bundle])
    }

    @Test func supportFileFailureIsReportedPrecisely() {
        let home = NSHomeDirectory()
        let bundle = "/Applications/Demo.app"
        let cache = "\(home)/Library/Caches/com.example.demo"
        let prefs = "\(home)/Library/Preferences/com.example.demo.plist"
        let app = makeApp(files: [(bundle, true), (cache, true), (prefs, true)], bundlePath: bundle)
        let result = AppUninstallerEngine.performUninstall(app) { url in
            if url.path == cache { throw CocoaError(.fileWriteNoPermission) }
        }
        #expect(!result.success)
        #expect(result.failedPaths == [cache])
        #expect(result.errorMessage?.contains("com.example.demo") == true)
    }
}
