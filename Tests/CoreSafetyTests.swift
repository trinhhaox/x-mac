import Testing
@testable import Xmac

@Suite struct CoreSafetyTests {
    @Test func posixShellQuotesSingleArgument() {
        #expect(POSIXShell.quote("O'Reilly") == "'O'\"'\"'Reilly'")
        #expect(POSIXShell.join(["echo", "hello world"]) == "'echo' 'hello world'")
    }

    @Test func bsdDeviceNameValidation() {
        #expect(BSDDeviceName.isValid("disk4"))
        #expect(BSDDeviceName.isValid("disk4s1"))

        #expect(!BSDDeviceName.isValid("/dev/disk4"))
        #expect(!BSDDeviceName.isValid("disk4s1s2"))
        #expect(!BSDDeviceName.isValid("disk 4"))
        #expect(!BSDDeviceName.isValid("disk4; reboot"))
    }
}
