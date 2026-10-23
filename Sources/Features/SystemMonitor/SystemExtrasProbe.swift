import Darwin
import Foundation
import IOKit

/// Battery state from the AppleSmartBattery registry entry (read-only, no privileges). Nil on desktops.
struct BatteryInfo: Equatable {
    var chargePercent: Int?
    var isCharging: Bool
    /// On power adapter; a full battery is connected but not charging.
    var isExternalPowerConnected: Bool
    var cycleCount: Int?
    /// Full-charge capacity relative to design capacity, 0–100+.
    var healthPercent: Int?

    init?(registry: [String: Any]) {
        guard registry["BatteryInstalled"] as? Bool ?? true,
              registry["DesignCapacity"] != nil || registry["CycleCount"] != nil
        else { return nil }
        isCharging = registry["IsCharging"] as? Bool ?? false
        isExternalPowerConnected = registry["ExternalConnected"] as? Bool ?? false
        cycleCount = registry["CycleCount"] as? Int
        if let current = registry["CurrentCapacity"] as? Int, let max = registry["MaxCapacity"] as? Int, max > 0 {
            // Apple silicon reports these as percentages already (max == 100); Intel reports mAh.
            chargePercent = Int((Double(current) / Double(max) * 100).rounded())
        }
        // mAh values sit at the top level on older systems and only inside BatteryData on newer
        // Apple silicon releases. MaxCapacity is a percentage there, so it is never used for health.
        // NominalChargeCapacity is what System Settings reports as "Maximum Capacity".
        let nested = registry["BatteryData"] as? [String: Any] ?? [:]
        func milliampHours(_ key: String) -> Int? { registry[key] as? Int ?? nested[key] as? Int }
        let fullCharge = milliampHours("NominalChargeCapacity") ?? milliampHours("AppleRawMaxCapacity")
        if let fullCharge, let design = milliampHours("DesignCapacity"), design > 0 {
            healthPercent = Int((Double(fullCharge) / Double(design) * 100).rounded())
        }
    }
}

/// Cumulative bytes read/written by all block storage drivers since boot.
struct DiskIOCounter: Equatable {
    var bytesRead: UInt64
    var bytesWritten: UInt64
}

struct DiskIORate: Equatable {
    var read: Double
    var write: Double

    /// Nil when a counter went backwards (disk ejected) or the interval is not usable.
    static func calculate(previous: DiskIOCounter, current: DiskIOCounter, elapsed: Double) -> DiskIORate? {
        guard elapsed > 0, current.bytesRead >= previous.bytesRead, current.bytesWritten >= previous.bytesWritten else { return nil }
        return DiskIORate(
            read: Double(current.bytesRead - previous.bytesRead) / elapsed,
            write: Double(current.bytesWritten - previous.bytesWritten) / elapsed
        )
    }
}

/// CPU time and memory of one process at one instant.
struct ProcessSample: Equatable {
    let pid: pid_t
    let name: String
    let cpuNanoseconds: UInt64
    let memoryBytes: UInt64
}

struct ProcessUsage: Equatable, Identifiable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    /// Percent of one core, like Activity Monitor (can exceed 100).
    let cpuPercent: Double
    let memoryBytes: UInt64

    /// Busiest processes between two snapshots; processes that started in between are skipped.
    static func top(previous: [ProcessSample], current: [ProcessSample], elapsed: Double, limit: Int = 5) -> [ProcessUsage] {
        guard elapsed > 0 else { return [] }
        let before = Dictionary(previous.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let usages: [ProcessUsage] = current.compactMap { now in
            guard let old = before[now.pid], old.name == now.name, now.cpuNanoseconds >= old.cpuNanoseconds else { return nil }
            let percent = Double(now.cpuNanoseconds - old.cpuNanoseconds) / (elapsed * 1_000_000_000) * 100
            return ProcessUsage(pid: now.pid, name: now.name, cpuPercent: percent, memoryBytes: now.memoryBytes)
        }
        return Array(usages.sorted { ($0.cpuPercent, $0.memoryBytes) > ($1.cpuPercent, $1.memoryBytes) }.prefix(limit))
    }
}

enum SystemExtrasProbe {
    static func battery() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let registry = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return BatteryInfo(registry: registry)
    }

    static func diskIO() -> DiskIOCounter? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var total = DiskIOCounter(bytesRead: 0, bytesWritten: 0)
        var found = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            total.bytesRead &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            total.bytesWritten &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            found = true
        }
        return found ? total : nil
    }

    /// The user's own processes; other users' and system processes are not readable without privileges.
    static func processes() -> [ProcessSample] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        var samples: [ProcessSample] = []
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            var info = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard status == 0 else { continue }
            var nameBuffer = [CChar](repeating: 0, count: 256)
            guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
            // rusage CPU times are Mach absolute time units (equal to ns only on Intel).
            let ticks = info.ri_user_time &+ info.ri_system_time
            let nanoseconds = UInt64(Double(ticks) * Double(timebase.numer) / Double(max(timebase.denom, 1)))
            samples.append(ProcessSample(pid: pid, name: String(cString: nameBuffer), cpuNanoseconds: nanoseconds, memoryBytes: info.ri_phys_footprint))
        }
        return samples
    }
}
