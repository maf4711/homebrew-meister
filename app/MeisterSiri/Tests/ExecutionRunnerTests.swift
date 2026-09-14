import XCTest
import Darwin
@testable import MeisterSiri

struct ExecutionFixture {
    let directory: URL
    var path: String { directory.appendingPathComponent("fixture.sh").path }
    init(_ script: String, contract: Bool = true, previews: String = "profiles ai") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("meister-execution-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let markers = contract ? "# GUI-Execution-Contract: 1\n# GUI-Preview-Capabilities: \(previews)\n" : ""
        try ("#!/bin/sh\n" + markers + script + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

final class ExecutionRunnerTests: XCTestCase {
    func testOutputStreamsBeforeExitAndBothPipesDrainBeyondCapacity() async throws {
        let script = try ExecutionFixture("""
        echo FIRST
        /bin/sleep 0.3
        i=0
        while [ "$i" -lt 12000 ]; do
          echo OUTPUT-LINE
          echo ERROR-LINE >&2
          i=$((i + 1))
        done
        echo LAST
        """)
        defer { script.remove() }
        let first = expectation(description: "first streamed before completion")
        let run = Task {
            await ProcessExecution().run(executable: script.path, arguments: [], timeout: 5) { text in
                if text.contains("FIRST") { first.fulfill() }
            }
        }
        await fulfillment(of: [first], timeout: 1)
        let result = await run.value
        XCTAssertEqual(result.code, 0)
        XCTAssertEqual(result.output.components(separatedBy: "OUTPUT-LINE").count - 1, 12000)
        XCTAssertEqual(result.output.components(separatedBy: "ERROR-LINE").count - 1, 12000)
        XCTAssertTrue(result.output.hasSuffix("LAST\n"))
    }

    func testTimeoutEscalatesForTermIgnoringProcessGroup() async throws {
        let script = try ExecutionFixture("trap '' TERM\necho START\n/bin/sleep 30\necho SHOULD-NOT-RUN")
        defer { script.remove() }
        let start = Date()
        let result = await ProcessExecution().run(executable: script.path, arguments: [], timeout: 0.15)
        XCTAssertEqual(result.code, 124)
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.output.contains("SHOULD-NOT-RUN"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    @MainActor
    func testCancellationKeepsBusyUntilGroupExitsAndRejectsNextRun() async throws {
        let script = try ExecutionFixture("""
        trap '' TERM
        /bin/sleep 30 &
        echo CHILD:$!
        wait
        """)
        defer { script.remove() }
        let runner = CLIRunner(executable: script.path)
        await runner.waitForCapabilities()
        guard case .allowed(let command) = CommandPolicy.prepare(arguments: ["doctor"], dryRun: false) else {
            return XCTFail("doctor unavailable")
        }
        let completed = expectation(description: "cancellation complete")
        runner.onCompletion = { _ in completed.fulfill() }
        XCTAssertTrue(runner.run(command: command))
        let startedDeadline = Date().addingTimeInterval(3)
        while !runner.liveOutput.contains("CHILD:"), Date() < startedDeadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let childLine = try XCTUnwrap(runner.liveOutput.split(separator: "\n").first { $0.hasPrefix("CHILD:") })
        let child = try XCTUnwrap(Int32(childLine.dropFirst(6)))
        runner.cancel()
        XCTAssertTrue(runner.isRunning)
        XCTAssertTrue(runner.isCancelling)
        XCTAssertFalse(runner.run(command: command))
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertFalse(runner.isRunning)
        XCTAssertFalse(runner.isCancelling)
        XCTAssertEqual(runner.lastExitCode, 130)
        // A reparented zombie is already terminated; it must never be a live descendant.
        let process = await ProcessExecution().run(executable: "/bin/ps", arguments: ["-o", "stat=", "-p", String(child)])
        XCTAssertTrue(process.code != 0 || process.output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
        XCTAssertTrue(runner.liveOutput.hasSuffix("└─ exit 130\n"))
    }

    func testConcurrentProbesDoNotInheritEachOthersPipes() async {
        let long = Task { await ProcessExecution().run(executable: "/bin/sleep", arguments: ["0.8"]) }
        let start = Date()
        let short = await ProcessExecution().run(executable: "/bin/echo", arguments: ["SHORT"])
        XCTAssertEqual(short.output, "SHORT\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.4)
        _ = await long.value
    }

    func testEscapedDescendantCannotHoldOutputDrainForever() async throws {
        let ready = expectation(description: "escaped child holds the output pipe")
        let run = Task {
            await ProcessExecution().run(executable: "/usr/bin/python3", arguments: ["-c", """
        import os, time
        child = os.fork()
        if child == 0:
            os.setsid()
            print("ESCAPED:" + str(os.getpid()), flush=True)
            time.sleep(30)
            os._exit(0)
        time.sleep(0.1)
        """], timeout: 15) { text in
                if text.contains("ESCAPED:") { ready.fulfill() }
            }
        }
        // Measure the bounded drain after the child exists. A cold Python/Xcode
        // launcher on CI is setup time, not time spent waiting for pipe EOF.
        await fulfillment(of: [ready], timeout: 10)
        let start = Date()
        let result = await run.value
        let line = try XCTUnwrap(result.output.split(separator: "\n").first { $0.hasPrefix("ESCAPED:") })
        let child = try XCTUnwrap(Int32(line.dropFirst(8)))
        defer { kill(child, SIGKILL) }
        XCTAssertEqual(result.code, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testChildEnvironmentIncludesTrustedAbsoluteToolsAndGUIGroupFlag() async {
        let result = await ProcessExecution().run(executable: "/bin/sh", arguments: ["-c", "printf '%s\\n%s\\n' \"$PATH\" \"$MEISTER_GUI_PROCESS_GROUP\""])
        XCTAssertEqual(result.code, 0)
        let lines = result.output.split(separator: "\n")
        XCTAssertTrue(lines.first?.hasPrefix("/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin") == true)
        XCTAssertTrue(lines.first?.split(separator: ":").allSatisfy { $0.hasPrefix("/") } == true)
        XCTAssertEqual(lines.last, "1")
    }

    @MainActor
    func testLegacyCLIAndChangedSourceFailClosedWithoutExecuting() async throws {
        let legacy = try ExecutionFixture("echo UNSAFE", contract: false)
        defer { legacy.remove() }
        let oldRunner = CLIRunner(executable: legacy.path)
        await oldRunner.waitForCapabilities()
        XCTAssertEqual(oldRunner.executionReadiness, .requiresUpdate)
        guard case .allowed(let command) = CommandPolicy.prepare(arguments: ["doctor"], dryRun: true) else {
            return XCTFail("inspection unavailable")
        }
        XCTAssertFalse(oldRunner.run(command: command))
        XCTAssertTrue(oldRunner.liveOutput.contains("aktualisiert"))
        let oldProbe = await oldRunner.probe(arguments: ["--version"])
        XCTAssertEqual(oldProbe.code, 126)
        XCTAssertFalse(oldProbe.output.contains("UNSAFE"))

        let changed = try ExecutionFixture("echo SAFE")
        defer { changed.remove() }
        let runner = CLIRunner(executable: changed.path)
        await runner.waitForCapabilities()
        XCTAssertTrue(runner.isExecutionReady)
        try "#!/bin/sh\necho UNSAFE_REPLACEMENT\n".write(toFile: changed.path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: changed.path)
        XCTAssertFalse(runner.run(command: command))
        await runner.waitForCapabilities()
        XCTAssertEqual(runner.executionReadiness, .requiresUpdate)
        XCTAssertFalse(runner.run(command: command))
        XCTAssertFalse(runner.liveOutput.contains("UNSAFE_REPLACEMENT"))
    }

    @MainActor
    func testPreparedPreviewFromDifferentRunnerDoesNotGrantCapability() async throws {
        let script = try ExecutionFixture("echo MUST_NOT_RUN", previews: "")
        defer { script.remove() }
        let runner = CLIRunner(executable: script.path)
        await runner.waitForCapabilities()
        XCTAssertTrue(runner.isExecutionReady)
        guard case .allowed(let preview) = CommandPolicy.prepare(arguments: ["--quick"], dryRun: true, supportsProfilePreview: true) else {
            return XCTFail("profile preview unavailable")
        }
        XCTAssertFalse(runner.run(command: preview))
        XCTAssertFalse(runner.liveOutput.contains("MUST_NOT_RUN"))
    }

    @MainActor
    func testGUITimeoutWrapperKeepsChildInCancelledProcessGroup() async throws {
        let timeoutPath = try XCTUnwrap([
            "/opt/homebrew/bin/timeout", "/opt/homebrew/bin/gtimeout",
            "/usr/local/bin/timeout", "/usr/local/bin/gtimeout"
        ].first { FileManager.default.isExecutableFile(atPath: $0) },
            "Install GNU coreutils to verify timeout-child cancellation")
        let script = try ExecutionFixture("""
        if [ "$MEISTER_GUI_PROCESS_GROUP" = 1 ]; then
            timeout() { command \(timeoutPath) --foreground "$@"; }
        else
            exit 99
        fi
        timeout 30 /bin/sh -c 'trap "" TERM; /bin/sleep 30 & echo TIMED_CHILD:$!; wait'
        """)
        defer { script.remove() }
        let runner = CLIRunner(executable: script.path)
        await runner.waitForCapabilities()
        guard case .allowed(let command) = CommandPolicy.prepare(arguments: ["doctor"], dryRun: false) else {
            return XCTFail("inspection unavailable")
        }
        let completed = expectation(description: "GNU timeout subtree cancelled")
        runner.onCompletion = { _ in completed.fulfill() }
        XCTAssertTrue(runner.run(command: command))
        let deadline = Date().addingTimeInterval(3)
        while !runner.liveOutput.contains("TIMED_CHILD:"), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let line = try XCTUnwrap(runner.liveOutput.split(separator: "\n").first { $0.hasPrefix("TIMED_CHILD:") })
        let child = try XCTUnwrap(Int32(line.dropFirst(12)))
        defer { kill(child, SIGKILL) }
        runner.cancel()
        XCTAssertTrue(runner.isRunning)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(runner.lastExitCode, 130)
        let process = await ProcessExecution().run(executable: "/bin/ps", arguments: ["-o", "stat=", "-p", String(child)])
        XCTAssertTrue(process.code != 0 || process.output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
    }

    @MainActor
    func testAsyncProbeLeavesMainActorResponsive() async throws {
        let script = try ExecutionFixture("/bin/sleep 0.3\necho VERSION")
        defer { script.remove() }
        let runner = CLIRunner(executable: script.path)
        await runner.waitForCapabilities()
        let probe = Task { await runner.probe(arguments: ["--version"]) }
        let start = Date()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
        let result = await probe.value
        XCTAssertEqual(result.output, "VERSION\n")
        XCTAssertFalse(runner.isRunning)
    }

    @MainActor
    func testStatusProbesCoalesceAndReportFailuresAsUnknown() async throws {
        let status = SystemStatus(historyPath: "/nonexistent/meister-test-history") { _, _ in
            try? await Task.sleep(nanoseconds: 200_000_000)
            return ExecutionResult(code: 124, output: "", wasCancelled: false, timedOut: true)
        }
        let runner = CLIRunner(executable: "/nonexistent/meister-test-cli")
        status.refresh(using: runner)
        status.refresh(using: runner)
        XCTAssertTrue(status.isRefreshing)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(status.isRefreshing)
        let refreshDeadline = Date().addingTimeInterval(3)
        while status.isRefreshing, Date() < refreshDeadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(status.isRefreshing)
        XCTAssertNil(status.rows.first { $0.label == "FileVault" }?.ok)
        XCTAssertEqual(status.rows.first { $0.label == "FileVault" }?.value, "Zeitlimit erreicht")
    }
}
