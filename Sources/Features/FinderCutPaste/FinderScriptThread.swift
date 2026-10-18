import Foundation

/// Runs Finder AppleScript on one dedicated thread, in submission order.
/// NSAppleScript must stay on a single thread, and running it inside the event
/// tap callback would stall every key press and click system-wide while Finder
/// is slow (network/iCloud volumes) or an Automation prompt is showing.
final class FinderScriptThread {
    static let shared = FinderScriptThread()

    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    private var thread: Thread?

    private init() {}

    func async(_ job: @escaping () -> Void) {
        condition.lock()
        jobs.append(job)
        if thread == nil {
            let worker = Thread { [unowned self] in self.drainForever() }
            worker.name = "vn.xmac.finder-applescript"
            worker.qualityOfService = .userInitiated
            thread = worker
            worker.start()
        }
        condition.signal()
        condition.unlock()
    }

    private func drainForever() {
        while true {
            condition.lock()
            while jobs.isEmpty {
                condition.wait()
            }
            let job = jobs.removeFirst()
            condition.unlock()
            autoreleasepool { job() }
        }
    }
}
