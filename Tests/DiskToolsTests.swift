import DiskArbitration
import Foundation
import Testing

@testable import Xmac

@Suite struct DiskToolsTests {
    @Test func formatNameRulesFollowEachFileSystem() {
        #expect(DiskFormat.fat32.nameProblem("usb backup") == nil)
        #expect(DiskFormat.fat32.normalizedName(" usb backup ") == "USB BACKUP")
        #expect(DiskFormat.fat32.nameProblem("TWELVE CHARS") != nil)
        #expect(DiskFormat.fat32.nameProblem("Ổ CỨNG") != nil)
        #expect(DiskFormat.exFAT.nameProblem("Hao 1TB") == nil)
        #expect(DiskFormat.exFAT.nameProblem("Sixteen chars!!!") != nil)
        #expect(DiskFormat.apfs.nameProblem("Ổ cứng công việc") == nil)
        #expect(DiskFormat.apfs.nameProblem("a/b") != nil)
        #expect(DiskFormat.macExtended.nameProblem("   ") != nil)
    }

    @Test func diskutilFileSystemMapsToFormat() {
        #expect(DiskFormat(fileSystem: "exfat") == .exFAT)
        #expect(DiskFormat(fileSystem: "msdos") == .fat32)
        #expect(DiskFormat(fileSystem: "apfs") == .apfs)
        #expect(DiskFormat(fileSystem: "hfs") == .macExtended)
        #expect(DiskFormat(fileSystem: "ntfs") == nil)
        #expect(DiskFormat.fat32.partitionScheme == "MBR")
        #expect(DiskFormat.exFAT.partitionScheme == "GPT")
    }

    @Test func eraseIsOnlyAllowedOnExternalNonSystemDevices() {
        let internalBoot: [String: Any] = ["DeviceIdentifier": "disk3s1s1", "ParentWholeDisk": "disk3",
                                           "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]]]
        let external: [String: Any] = ["Internal": false, "BusProtocol": "USB", "DeviceIdentifier": "disk4s2",
                                       "ParentWholeDisk": "disk4", "MountPoint": "/Volumes/X"]
        #expect(DiskEraseGuard.isAllowed(targetInfo: external, bootInfo: internalBoot))
        #expect(!DiskEraseGuard.isAllowed(targetInfo: external, bootInfo: nil))

        var internalDisk = external
        internalDisk["Internal"] = true
        #expect(!DiskEraseGuard.isAllowed(targetInfo: internalDisk, bootInfo: internalBoot))

        var image = external
        image["BusProtocol"] = "Disk Image"
        #expect(!DiskEraseGuard.isAllowed(targetInfo: image, bootInfo: internalBoot))

        var missingInternalFlag = external
        missingInternalFlag["Internal"] = nil
        #expect(!DiskEraseGuard.isAllowed(targetInfo: missingInternalFlag, bootInfo: internalBoot))
    }

    @Test func eraseRefusesAnotherPartitionOfAnExternalBootDrive() {
        // macOS running from external disk4: its root is APFS container disk5 on store disk4s2.
        let externalBoot: [String: Any] = ["DeviceIdentifier": "disk5s1s1", "ParentWholeDisk": "disk5",
                                           "APFSPhysicalStores": [["APFSPhysicalStore": "disk4s2"]]]
        let siblingPartition: [String: Any] = ["Internal": false, "BusProtocol": "USB", "DeviceIdentifier": "disk4s3",
                                               "ParentWholeDisk": "disk4"]
        #expect(!DiskEraseGuard.isAllowed(targetInfo: siblingPartition, bootInfo: externalBoot))
    }

    @Test func apfsVolumesResolveToTheirPhysicalDrive() {
        let apfsVolume: [String: Any] = ["DeviceIdentifier": "disk5s1", "ParentWholeDisk": "disk5",
                                         "APFSPhysicalStores": [["APFSPhysicalStore": "disk4s2"]]]
        #expect(DiskEraseGuard.physicalDisks(of: apfsVolume) == ["disk4"])
        #expect(DiskEraseGuard.physicalDisks(of: ["DeviceIdentifier": "disk8"]) == ["disk8"])
        #expect(DiskEraseGuard.physicalDisks(of: ["ParentWholeDisk": "../evil"]).isEmpty)
        #expect(DiskEraseGuard.wholeDisk(of: "disk12s3") == "disk12")
    }

    @Test func swappedDriveIsNotTreatedAsTheConfirmedVolume() {
        let confirmed = DiskVolume(name: "BACKUP", bsdName: "disk4s1", mountPoint: "/Volumes/BACKUP", fileSystem: "exfat",
                                   totalSize: 500, freeSize: 0, isExternal: true, isWritable: true, isMounted: true,
                                   volumeUUID: "UUID-A")
        #expect(DiskEraseGuard.isSameVolume(info: ["VolumeUUID": "UUID-A"], as: confirmed))
        #expect(!DiskEraseGuard.isSameVolume(info: ["VolumeUUID": "UUID-B", "VolumeName": "BACKUP"], as: confirmed))

        let noUUID = DiskVolume(name: "CAM", bsdName: "disk4s1", mountPoint: nil, fileSystem: "msdos",
                                totalSize: 500, freeSize: 0, isExternal: true, isWritable: false, isMounted: false)
        #expect(DiskEraseGuard.isSameVolume(info: ["VolumeName": "CAM", "TotalSize": Int64(500)], as: noUUID))
        #expect(!DiskEraseGuard.isSameVolume(info: ["VolumeName": "CAM", "TotalSize": Int64(900)], as: noUUID))
    }

    @Test func healthPrefersWholeDiskFacts() {
        let volume: [String: Any] = ["MediaName": "", "BusProtocol": "USB"]
        let whole: [String: Any] = ["MediaName": "Samsung T7", "BusProtocol": "USB", "SolidState": true, "SMARTStatus": "Verified"]
        let info = DiskHealthInfo.from(volumeInfo: volume, wholeDiskInfo: whole)
        #expect(info.model == "Samsung T7")
        #expect(info.isSolidState == true)
        #expect(info.smart == .verified)

        #expect(DiskHealthInfo.from(volumeInfo: ["SMARTStatus": "Failing"], wholeDiskInfo: nil).smart == .failing)
        #expect(DiskHealthInfo.from(volumeInfo: ["SMARTStatus": "Not Supported"], wholeDiskInfo: nil).smart == .unsupported)
        #expect(DiskHealthInfo.from(volumeInfo: [:], wholeDiskInfo: nil).isSolidState == nil)
    }

    @Test func speedTestWritesReadsAndCleansUp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xmac-speed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await DiskSpeedTest.run(at: directory.path, sizeMB: 8)
        #expect(result.writeMBps > 0)
        #expect(result.readMBps > 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(DiskSpeedTest.megabytesPerSecond(bytes: 1_048_576, seconds: 0) == 0)
        #expect(DiskSpeedTest.megabytesPerSecond(bytes: 10 * 1_048_576, seconds: 2) == 5)
    }

    @Test func diskutilSummaryIsTheLastMeaningfulLine() {
        #expect(DiskUtil.summary(of: "Started\nChecking\nThe volume Hao 1TB appears to be OK\n\n") == "The volume Hao 1TB appears to be OK")
        #expect(DiskUtil.summary(of: "") == "")
    }

    @Test func autoWritePreferenceIsKeyedByVolumeUUID() throws {
        let suite = "xmac.tests.disk.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let ntfs = DiskVolume(name: "Win", bsdName: "disk5s2", mountPoint: "/Volumes/Win", fileSystem: "ntfs",
                              totalSize: 1, freeSize: 0, isExternal: true, isWritable: false, isMounted: true,
                              volumeUUID: "UUID-1")
        let exfat = DiskVolume(name: "Ex", bsdName: "disk6s2", mountPoint: nil, fileSystem: "exfat",
                               totalSize: 1, freeSize: 0, isExternal: true, isWritable: false, isMounted: false,
                               volumeUUID: "UUID-2")
        let settings = DiskAutomationSettings(defaults: defaults)
        #expect(settings.notifyOnPlugEvents)
        settings.setAutoWrite(true, for: ntfs)
        settings.setAutoWrite(true, for: exfat)
        #expect(settings.isAutoWriteEnabled(for: ntfs))
        #expect(!settings.isAutoWriteEnabled(for: exfat))

        let reloaded = DiskAutomationSettings(defaults: defaults)
        #expect(reloaded.autoWriteVolumeUUIDs == ["UUID-1"])
    }

    @Test func unsafeRemovalNeedsAMountedExternalVolume() {
        var description: [String: Any] = [
            kDADiskDescriptionMediaBSDNameKey as String: "disk4s2",
            kDADiskDescriptionVolumeNameKey as String: "Hao 1TB",
            kDADiskDescriptionDeviceInternalKey as String: false,
            kDADiskDescriptionDeviceProtocolKey as String: "USB",
            kDADiskDescriptionVolumeKindKey as String: "exfat",
            kDADiskDescriptionVolumePathKey as String: URL(fileURLWithPath: "/Volumes/Hao 1TB"),
        ]
        #expect(DiskEventSnapshot(description: description).isUnsafeRemoval)

        description[kDADiskDescriptionVolumePathKey as String] = nil
        let ejected = DiskEventSnapshot(description: description)
        #expect(ejected.isUserVolume)
        #expect(!ejected.isUnsafeRemoval)

        description[kDADiskDescriptionDeviceProtocolKey as String] = "Disk Image"
        #expect(!DiskEventSnapshot(description: description).isUserVolume)
    }
}
