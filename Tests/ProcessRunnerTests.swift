import Testing
import Foundation
@testable import Xmac

@Suite struct ProcessRunnerTests {
    private let sh = URL(fileURLWithPath: "/bin/sh")

    @Test func capturesStdoutAndExitCode() async throws {
        let result = try await ProcessRunner.run(executable: sh, arguments: ["-c", "echo hello; exit 3"])
        #expect(result.status == 3)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "hello\n")
        #expect(throws: ProcessRunnerError.nonZeroExit(3, "")) { try result.throwIfFailed() }
    }

    @Test func streamsStderrLinesAndKeepsTail() async throws {
        let lines = LockedBox<[String]>([])
        let result = try await ProcessRunner.run(
            executable: sh,
            arguments: ["-c", "echo one >&2; printf 'two\\rthree' >&2"],
            onStderrLine: { line in lines.mutate { $0.append(line) } }
        )
        #expect(lines.value == ["one", "two", "three"])
        #expect(result.stderrTail.contains("one"))
    }

    @Test func stderrTailIsCappedAtFourKB() async throws {
        let result = try await ProcessRunner.run(
            executable: sh,
            arguments: ["-c", "i=0; while [ $i -lt 2000 ]; do echo 0123456789abcdef >&2; i=$((i+1)); done; echo END >&2"]
        )
        #expect(result.stderrTail.utf8.count <= 4096)
        #expect(result.stderrTail.hasSuffix("END\n"))
    }

    @Test func launchFailureIsReported() async {
        do {
            _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/nonexistent/tool"), arguments: [])
            Issue.record("expected launchFailed")
        } catch let error as ProcessRunnerError {
            if case .launchFailed = error {} else { Issue.record("wrong error \(error)") }
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func timeoutTerminatesProcess() async {
        let start = Date()
        do {
            _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.3)
            Issue.record("expected timeout")
        } catch {
            #expect(error as? ProcessRunnerError == .timedOut)
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func cancellationTerminatesProcess() async {
        let start = Date()
        let task = Task {
            try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error as? ProcessRunnerError == .cancelled)
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }
    @Test func returnsWhenAGrandchildKeepsThePipesOpen() async throws {
        let started = Date()
        let result = try await ProcessRunner.run(executable: sh, arguments: ["-c", "sleep 30 & echo $!; echo hi"])
        defer {
            if let pid = pid_t(String(decoding: result.stdout, as: UTF8.self).split(separator: "\n").first ?? "") {
                kill(pid, SIGKILL)
            }
        }
        #expect(Date().timeIntervalSince(started) < ProcessRunner.readerDrainTimeout + 4)
        #expect(String(decoding: result.stdout, as: UTF8.self).hasSuffix("hi\n"))
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); body(&stored); lock.unlock() }

}
