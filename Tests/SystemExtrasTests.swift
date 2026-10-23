import Foundation
import Testing
@testable import Xmac

@Suite struct SystemExtrasTests {
    @Test func batteryParsesAppleSiliconAndIntelRegistries() {
        let appleSilicon = BatteryInfo(registry: [
            "CurrentCapacity": 80, "MaxCapacity": 100, "AppleRawMaxCapacity": 4_500,
            "DesignCapacity": 5_000, "CycleCount": 212, "IsCharging": true
        ])
        #expect(appleSilicon?.chargePercent == 80)
        #expect(appleSilicon?.healthPercent == 90)
        #expect(appleSilicon?.cycleCount == 212)
        #expect(appleSilicon?.isCharging == true)

        let intel = BatteryInfo(registry: [
            "CurrentCapacity": 3_000, "MaxCapacity": 6_000, "NominalChargeCapacity": 6_000,
            "DesignCapacity": 6_600, "CycleCount": 900
        ])
        #expect(intel?.chargePercent == 50)
        #expect(intel?.healthPercent == 91)

        // Newer Apple silicon releases only expose mAh values inside BatteryData.
        let nested = BatteryInfo(registry: [
            "CurrentCapacity": 98, "MaxCapacity": 100, "CycleCount": 211, "ExternalConnected": true,
            "BatteryData": ["DesignCapacity": 4_563, "NominalChargeCapacity": 4_145, "MaxCapacity": 4_000]
        ])
        #expect(nested?.healthPercent == 91)
        #expect(nested?.isExternalPowerConnected == true)

        #expect(BatteryInfo(registry: [:]) == nil)
        #expect(BatteryInfo(registry: ["BatteryInstalled": false, "DesignCapacity": 5_000]) == nil)
    }

    @Test func diskRateRejectsCounterResets() {
        let before = DiskIOCounter(bytesRead: 1_000, bytesWritten: 500)
        let after = DiskIOCounter(bytesRead: 3_000, bytesWritten: 1_500)
        #expect(DiskIORate.calculate(previous: before, current: after, elapsed: 2) == DiskIORate(read: 1_000, write: 500))
        #expect(DiskIORate.calculate(previous: after, current: before, elapsed: 2) == nil)
        #expect(DiskIORate.calculate(previous: before, current: after, elapsed: 0) == nil)
    }

    @Test func topProcessesUseCPUDeltaAndSkipNewOrReusedPids() {
        let previous = [
            ProcessSample(pid: 1, name: "idle", cpuNanoseconds: 1_000, memoryBytes: 10),
            ProcessSample(pid: 2, name: "busy", cpuNanoseconds: 0, memoryBytes: 20),
            ProcessSample(pid: 3, name: "old", cpuNanoseconds: 0, memoryBytes: 30)
        ]
        let current = [
            ProcessSample(pid: 1, name: "idle", cpuNanoseconds: 1_000, memoryBytes: 10),
            ProcessSample(pid: 2, name: "busy", cpuNanoseconds: 3_000_000_000, memoryBytes: 20),
            ProcessSample(pid: 3, name: "reused", cpuNanoseconds: 9_000_000_000, memoryBytes: 30),
            ProcessSample(pid: 4, name: "new", cpuNanoseconds: 9_000_000_000, memoryBytes: 40)
        ]
        let top = ProcessUsage.top(previous: previous, current: current, elapsed: 2)
        #expect(top.map(\.name) == ["busy", "idle"])
        #expect(top.first?.cpuPercent == 150)
    }

    @Test func liveProbesReadThisMacWithoutPrivileges() {
        let processes = SystemExtrasProbe.processes()
        #expect(processes.contains { $0.pid == getpid() })
        #expect(SystemExtrasProbe.diskIO() != nil)
    }
}
