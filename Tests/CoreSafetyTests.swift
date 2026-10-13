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

    @Test func mountOutputRequiresExactWritableMountPoint() {
        let output = """
        /dev/disk4s1 on /Volumes/Xmac_disk4s1 (ntfs, local, nodev, nosuid)
        /dev/disk5s1 on /Volumes/ReadOnly (ntfs, local, read-only)
        """

        #expect(MountOutputVerifier.isReadWriteMount(output: output, mountPoint: "/Volumes/Xmac_disk4s1"))
        #expect(!MountOutputVerifier.isReadWriteMount(output: output, mountPoint: "/Volumes/ReadOnly"))
        #expect(!MountOutputVerifier.isReadWriteMount(output: output, mountPoint: "/Volumes/Missing"))
    }

    @Test func cleanerPathPolicyAllowsOnlyDescendantsOfKnownRoots() {
        let home = "/Users/example"
        #expect(CleanerPathPolicy.isAllowed(
            itemPath: "/Users/example/Library/Caches/com.example.app",
            homeDirectory: home
        ))
        #expect(CleanerPathPolicy.isAllowed(
            itemPath: "/Users/example/.Trash/file.txt",
            homeDirectory: home
        ))
        #expect(CleanerPathPolicy.isAllowed(
            itemPath: "/Users/example/Library/Caches",
            homeDirectory: home
        ) == false)
        #expect(CleanerPathPolicy.isAllowed(
            itemPath: "/Users/example/Documents/important.txt",
            homeDirectory: home
        ) == false)
        #expect(CleanerPathPolicy.isAllowed(itemPath: "/", homeDirectory: home) == false)
    }

    @Test func uninstallPathPolicyAllowsOnlyAppBundleAndUserLibrary() {
        let home = "/Users/example"
        let bundle = "/Applications/Example.app"
        #expect(UninstallPathPolicy.isAllowed(path: bundle, bundlePath: bundle, homeDirectory: home))
        #expect(UninstallPathPolicy.isAllowed(
            path: "/Users/example/Library/Caches/com.example.app",
            bundlePath: bundle,
            homeDirectory: home
        ))
        #expect(UninstallPathPolicy.isAllowed(
            path: "/Users/example/Documents/important.txt",
            bundlePath: bundle,
            homeDirectory: home
        ) == false)
        #expect(UninstallPathPolicy.isAllowed(
            path: "/Users/example/Library/Mobile Documents/important.txt",
            bundlePath: bundle,
            homeDirectory: home
        ) == false)
        #expect(UninstallPathPolicy.isAllowed(
            path: "/Applications",
            bundlePath: "/Applications",
            homeDirectory: home
        ) == false)
    }
}
