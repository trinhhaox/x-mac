import Foundation

/// Thin async wrapper over `/usr/sbin/diskutil` for one-shot disk operations.
enum DiskUtil {
    static let executable = URL(fileURLWithPath: "/usr/sbin/diskutil")

    struct Outcome: Equatable {
        let succeeded: Bool
        let output: String
        let timedOut: Bool
    }

    /// Never throws: launch failures and timeouts come back as an unsuccessful outcome with a message.
    static func run(_ arguments: [String], timeout: TimeInterval) async -> Outcome {
        do {
            let result = try await ProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout)
            let stdout = String(decoding: result.stdout, as: UTF8.self)
            let output = [stdout, result.stderrTail]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return Outcome(succeeded: result.status == 0, output: output, timedOut: false)
        } catch ProcessRunnerError.timedOut {
            return Outcome(succeeded: false, output: L10n.text("diskutil không phản hồi kịp thời."), timedOut: true)
        } catch {
            return Outcome(succeeded: false, output: "\(error)", timedOut: false)
        }
    }

    static func infoPlist(_ target: String) async -> [String: Any]? {
        guard let result = try? await ProcessRunner.run(
            executable: executable, arguments: ["info", "-plist", target], timeout: 20
        ), result.status == 0 else { return nil }
        return try? PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil) as? [String: Any]
    }

    /// The last non-empty line, which is where diskutil states the verdict ("... appears to be OK").
    static func summary(of output: String) -> String {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
    }
}
