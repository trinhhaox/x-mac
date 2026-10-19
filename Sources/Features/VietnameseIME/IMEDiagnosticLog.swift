import os

/// Opt-in keystroke trace for reproducing typing bugs. Unlike the latency
/// monitor it records typed text, so it is off by default, never persisted,
/// and logs only while the user has it switched on.
///
/// Read with: `Scripts/ime-latency.sh` (category IME-Debug).
enum IMEDiagnosticLog {
    private static let logger = Logger(subsystem: "vn.xmac.app", category: "IME-Debug")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
