import CoreGraphics
import Foundation
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

    @Test func staleUnmountFailureContinuesOnlyWhenDiskIsNowUnmounted() {
        #expect(NTFSMountHelper.canContinueAfterUnmountFailure(currentlyMounted: false))
        #expect(!NTFSMountHelper.canContinueAfterUnmountFailure(currentlyMounted: true))
        #expect(!NTFSMountHelper.canContinueAfterUnmountFailure(currentlyMounted: nil))
    }

    @Test func simulatedIMEEventsAreIdentifiedWithoutARealKeySuppressionWindow() throws {
        let simulated = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ))
        let physical = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ))

        InputHookManager.markAsSimulated(simulated)

        #expect(InputHookManager.isSimulatedEvent(simulated))
        #expect(!InputHookManager.isSimulatedEvent(physical))
    }

    @Test func unmountedDiskDoesNotReportReliableCapacity() {
        let unmounted = DiskVolume(
            name: "Test",
            bsdName: "disk4s3",
            mountPoint: nil,
            fileSystem: "NTFS",
            totalSize: 644_245_094_400,
            freeSize: 0,
            isExternal: true,
            isWritable: false,
            isMounted: false
        )
        #expect(!unmounted.hasReliableCapacity)
    }

    @Test func diskScanSkipsSystemPartitionsAndListsAPFSVolumes() {
        let disks: [[String: Any]] = [
            ["DeviceIdentifier": "disk4", "Partitions": [
                ["DeviceIdentifier": "disk4s1", "Content": "EFI"],
                ["DeviceIdentifier": "disk4s2", "Content": "Microsoft Basic Data"]
            ]],
            ["DeviceIdentifier": "disk6", "Partitions": [
                ["DeviceIdentifier": "disk6s1", "Content": "EFI"],
                ["DeviceIdentifier": "disk6s2", "Content": "Apple_APFS"]
            ]],
            ["DeviceIdentifier": "disk7", "APFSPhysicalStores": [["DeviceIdentifier": "disk6s2"]],
             "Partitions": [[String: Any]](), "APFSVolumes": [["DeviceIdentifier": "disk7s1"]]],
            ["DeviceIdentifier": "disk8", "Content": "Windows_NTFS"]
        ]
        #expect(DiskManager.userVolumeIdentifiers(from: disks) == ["disk4s2", "disk7s1", "disk8"])
    }

    @Test func apfsFreeSpaceComesFromTheContainer() {
        #expect(DiskManager.freeSpace(from: ["FreeSpace": Int64(0), "APFSContainerFree": Int64(384_660_668_416)]) == 384_660_668_416)
        #expect(DiskManager.freeSpace(from: ["FreeSpace": Int64(42)]) == 42)
        #expect(DiskManager.freeSpace(from: [:]) == 0)
    }

    @Test func emptyVolumeNameFallsBackToDeviceName() {
        #expect(DiskManager.displayName(from: ["VolumeName": "", "MediaName": " "], bsdName: "disk6s2") == "disk6s2")
        #expect(DiskManager.displayName(from: ["VolumeName": "Hao 1TB"], bsdName: "disk4s2") == "Hao 1TB")
    }

    @Test func emptyMountPointIsNotTreatedAsMounted() {
        let unmountedPlist: [String: Any] = [
            "MountPoint": "",
            "FilesystemType": "ntfs"
        ]
        #expect(DiskManager.mountPoint(from: unmountedPlist) == nil)
        #expect(!DiskManager.isMounted(from: unmountedPlist))

        let mountedPlist: [String: Any] = ["MountPoint": "/Volumes/Test"]
        #expect(DiskManager.mountPoint(from: mountedPlist) == "/Volumes/Test")
        #expect(DiskManager.isMounted(from: mountedPlist))

        let explicitUnmounted: [String: Any] = [
            "Mounted": false,
            "MountPoint": "/Volumes/Stale"
        ]
        #expect(!DiskManager.isMounted(from: explicitUnmounted))
    }

    @Test func physicalSpaceKeyExpandsMacroWithoutUnicodePayload() {
        let suiteName = "XmacTests.MacroSpace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = MacroManager(defaults: defaults)

        let expansion = InputHookManager.macroExpansion(
            for: "vn",
            boundaryKeyCode: 49,
            character: nil,
            macros: Dictionary(uniqueKeysWithValues: manager.macros.map { ($0.shortcut, $0.expansion) }),
            enabled: manager.isMacroEnabled
        )

        #expect(expansion == "Việt Nam")
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
