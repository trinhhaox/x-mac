import Foundation

/// Runs long synchronous converter work on its own queue so it never occupies the cooperative pool.
enum BlockingWork {
    /// Throws `CancellationError` when the awaiting task was cancelled; call it between pages/images.
    typealias CancellationCheck = () throws -> Void

    private static let queue = DispatchQueue(label: "vn.xmac.converter.blocking", qos: .userInitiated, attributes: .concurrent)

    static func run<T>(_ body: @escaping (CancellationCheck) throws -> T) async throws -> T {
        let flag = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    continuation.resume(with: Result { try body { if flag.isCancelled { throw CancellationError() } } })
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
