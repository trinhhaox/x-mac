import Foundation
import Testing
@testable import Xmac

struct AppTrashMoverTests {
    @Test func permissionErrorsTriggerFinderFallback() {
        #expect(AppTrashMover.isPermissionDenied(CocoaError(.fileWriteNoPermission)))
        #expect(AppTrashMover.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))))
        let wrapped = NSError(domain: "x", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
        #expect(AppTrashMover.isPermissionDenied(wrapped))
    }

    @Test func otherErrorsDoNotTriggerFinderFallback() {
        #expect(!AppTrashMover.isPermissionDenied(CocoaError(.fileNoSuchFile)))
        #expect(!AppTrashMover.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
    }

    @Test func finderScriptEscapesQuotesAndBackslashes() {
        let script = AppTrashMover.finderDeleteScript(path: "/Applications/A \"B\" \\C.app")
        #expect(script == "tell application \"Finder\" to delete (POSIX file \"/Applications/A \\\"B\\\" \\\\C.app\" as alias)")
    }
}
