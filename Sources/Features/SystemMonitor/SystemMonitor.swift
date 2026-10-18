import AppKit
import Combine
import Darwin

struct CPUTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since old: CPUTicks) -> Double? {
        let busy = UInt64(user &- old.user) + UInt64(system &- old.system) + UInt64(nice &- old.nice)
        let total = busy + UInt64(idle &- old.idle)
        return total > 0 ? Double(busy) / Double(total) * 100 : nil
    }
}

struct NetworkCounter: Equatable {
    let received: UInt64
    let sent: UInt64
}

struct NetworkRate: Equatable {
    let received: Double
    let sent: Double

    static func calculate(previous: [String: NetworkCounter], current: [String: NetworkCounter], elapsed: Double) -> NetworkRate? {
        guard elapsed.isFinite, elapsed > 0, elapsed <= 10 else { return nil }
        var received = 0.0, sent = 0.0
        var compared = false
        for (name, value) in current {
            guard let old = previous[name], value.received >= old.received, value.sent >= old.sent else { continue }
            received += Double(value.received - old.received)
            sent += Double(value.sent - old.sent)
            compared = true
        }
        return compared ? NetworkRate(received: received / elapsed, sent: sent / elapsed) : nil
    }
}

struct SystemSample {
    var date = Date()
    var cpu: CPUTicks?
    var memoryUsed: UInt64?
    var memoryWired: UInt64?
    var memoryCompressed: UInt64?
    var swapUsed: UInt64?
    var diskTotal: Int64?
    var diskAvailable: Int64?
    var network: [String: NetworkCounter]?
    var uptime = ProcessInfo.processInfo.systemUptime
    var thermal = ProcessInfo.processInfo.thermalState
}

enum SystemProbe {
    static func read() -> SystemSample {
        var sample = SystemSample()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if cpuStatus == KERN_SUCCESS {
            sample.cpu = CPUTicks(user: cpu.cpu_ticks.0, system: cpu.cpu_ticks.1, idle: cpu.cpu_ticks.2, nice: cpu.cpu_ticks.3)
        }
        var vm = vm_statistics64()
        count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if vmStatus == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            sample.memoryWired = UInt64(vm.wire_count) * page
            sample.memoryCompressed = UInt64(vm.compressor_page_count) * page
            sample.memoryUsed = memoryUsed(
                internalPages: UInt64(vm.internal_page_count), purgeablePages: UInt64(vm.purgeable_count),
                wiredPages: UInt64(vm.wire_count), compressedPages: UInt64(vm.compressor_page_count),
                pageSize: page, physicalMemory: ProcessInfo.processInfo.physicalMemory)
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { sample.swapUsed = swap.xsu_used }
        // Home volume is the writable Data volume on modern macOS, not the sealed system snapshot.
        if let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            sample.diskTotal = values.volumeTotalCapacity.map(Int64.init)
            sample.diskAvailable = values.volumeAvailableCapacity.map(Int64.init)
        }
        sample.network = networkCounters()
        return sample
    }

    /// Activity Monitor's "Memory Used": app memory (internal − purgeable) + wired + compressed.
    /// Active pages are deliberately excluded because they include reclaimable file cache.
    static func memoryUsed(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
                           compressedPages: UInt64, pageSize: UInt64, physicalMemory: UInt64) -> UInt64 {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return min(physicalMemory, (appPages + wiredPages + compressedPages) * pageSize)
    }

    static func networkCounters() -> [String: NetworkCounter]? {
        // NET_RT_IFLIST2 supplies 64-bit byte counters (getifaddrs' if_data can wrap at 4 GiB).
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var data = Data(count: size)
        let status = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
        guard status == 0 else { return nil }
        data.count = size
        return decodeNetworkCounters(data) { index in
            var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            guard if_indextoname(UInt32(index), &name) != nil else { return nil }
            return String(cString: name)
        }
    }

    static func decodeNetworkCounters(_ data: Data, interfaceName: (UInt16) -> String?) -> [String: NetworkCounter]? {
        data.withUnsafeBytes { bytes in
            var result: [String: NetworkCounter] = [:]
            var offset = 0
            // Route address messages can be shorter than if_msghdr. Only the first
            // four bytes are shared; skip unknown records by their actual length.
            while offset < data.count {
                guard offset + 4 <= data.count else { return nil }
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= data.count else { return nil }
                if bytes[offset + 3] == RTM_IFINFO2 {
                    guard length >= MemoryLayout<if_msghdr2>.size else { return nil }
                    let info = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let interface = interfaceName(info.ifm_index) {
                        // Count physical Ethernet / Wi-Fi once; omit tunnels, loopback and peer-to-peer duplicates.
                        if interface.hasPrefix("en"), info.ifm_flags & IFF_UP != 0 {
                            result[interface] = NetworkCounter(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += length
            }
            return result
        }
    }
}

@MainActor final class SystemMonitor: ObservableObject {
    @Published private(set) var sample: SystemSample?
    @Published private(set) var cpuUsage: Double?
    @Published private(set) var networkRate: NetworkRate?
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var running = false
    private var task: Task<Void, Never>?
    private let probe: ProbeBox
    private var previous: SystemSample?

    /// The probe runs on a background task and is only ever called sequentially, one sample at a time.
    private struct ProbeBox: @unchecked Sendable { let read: () -> SystemSample }

    init(probe: @escaping () -> SystemSample = SystemProbe.read) { self.probe = ProbeBox(read: probe) }

    func start() {
        guard task == nil else { return }
        running = true
        previous = nil
        cpuUsage = nil
        networkRate = nil
        cpuHistory = []
        let probe = probe
        task = Task { [weak self] in
            while !Task.isCancelled {
                // Sampling is read-only and bounded; no subprocesses, sockets, sensors or privileged helper.
                // It runs off the main actor; only publishing happens on main.
                let next = await Task.detached(priority: .utility) { probe.read() }.value
                guard !Task.isCancelled, let self else { return }
                self.accept(next)
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        running = false
        previous = nil
    }

    func accept(_ next: SystemSample) {
        let elapsed = previous.map { next.uptime - $0.uptime } ?? 0
        if let old = previous, elapsed > 0, elapsed <= 10 {
            cpuUsage = next.cpu.flatMap { ticks in old.cpu.flatMap { ticks.usage(since: $0) } }
            networkRate = next.network.flatMap { counters in old.network.flatMap {
                NetworkRate.calculate(previous: $0, current: counters, elapsed: elapsed)
            } }
        } else { cpuUsage = nil; networkRate = nil }
        if let cpuUsage { cpuHistory.append(cpuUsage); cpuHistory = Array(cpuHistory.suffix(30)) }
        previous = next
        sample = next
    }

    static func thermalTitle(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return L10n.text("Bình thường")
        case .fair: return L10n.text("Ấm")
        case .serious: return L10n.text("Nóng — hệ thống đang hạn chế hiệu năng")
        case .critical: return L10n.text("Rất nóng — cần giảm tải")
        @unknown default: return L10n.text("Không xác định")
        }
    }
}
