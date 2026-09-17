import XCTest
import Combine
@testable import MeisterAI

final class ExecutionPolicyTests: XCTestCase {
    func testPreviewSyntaxForEverySupportedMutation() {
        let actions: [([String], [String])] = [
            (["--quick"], ["--quick", "-n"]), (["--auto"], ["--auto", "-n"]),
            (["--deep"], ["--deep", "-n"]), (["autofix"], ["autofix", "--dry-run"]),
            (["heal"], ["heal", "--dry-run"]), (["orphans"], ["orphans", "--dry-run"]),
            (["simfix"], ["simfix", "--dry-run"]),
            (["bloatware", "kill", "--p0"], ["bloatware", "kill", "--p0", "--dry-run"]),
        ]
        for (action, expected) in actions {
            guard case .allowed(let command) = CommandPolicy.prepare(arguments: action, dryRun: true, supportsProfilePreview: true) else {
                return XCTFail("Missing preview: \(action)")
            }
            XCTAssertEqual(command.arguments, expected)
            XCTAssertTrue(command.isPreview)
        }
    }

    func testUnsupportedMutationIsBlockedEvenWithManuallyAppendedPreviewFlag() {
        let actions = [["free"], ["free", "--restart-ui"], ["ai"], ["touchid"], ["sudo-setup"], ["-I"],
                       ["selftest"], ["tweaks", "showhidden", "on"], ["tcc-clean", "--do"], ["unknown"]]
        for action in actions {
            for args in [action, action + ["--dry-run"]] {
                guard case .blocked(let message) = CommandPolicy.prepare(arguments: args, dryRun: true) else {
                    return XCTFail("Unsafe action allowed: \(args)")
                }
                XCTAssertFalse(message.isEmpty)
            }
        }
        guard case .blocked = CommandPolicy.configurationCreation(dryRun: true) else {
            return XCTFail("Dry-run must not create config")
        }
    }

    func testProfilePreviewsNeedExplicitSourceCapability() {
        for profile in ["--quick", "--auto", "--deep"] {
            guard case .blocked = CommandPolicy.prepare(arguments: [profile], dryRun: true) else {
                return XCTFail("Unproven profile preview was allowed")
            }
        }
    }

    func testProbeAPIRejectsMutations() {
        XCTAssertFalse(CommandPolicy.permitsProbe(arguments: ["free"]))
        XCTAssertFalse(CommandPolicy.permitsProbe(arguments: ["ai"]))
        XCTAssertFalse(CommandPolicy.permitsProbe(arguments: ["tweaks", "showhidden", "on"]))
        XCTAssertFalse(CommandPolicy.permitsProbe(arguments: ["--quick", "-n"]))
        XCTAssertTrue(CommandPolicy.permitsProbe(arguments: ["doctor", "--json"]))
    }

    func testNewCLIAIPreviewCapabilityIsExplicit() {
        guard case .allowed(let command) = CommandPolicy.prepare(arguments: ["ai"], dryRun: true, supportsAIPreview: true) else {
            return XCTFail("New CLI must expose AI preview")
        }
        XCTAssertEqual(command.arguments, ["ai", "--dry-run"])
        XCTAssertTrue(command.isPreview)
    }

    func testInspectionsStayAvailableWithoutUnsupportedCLIFlags() {
        let actions = [["doctor"], ["today"], ["score"], ["-H"], ["privacy"], ["startup"], ["tcc-clean"],
                       ["appupdates"], ["disk"], ["bloatware", "scan"], ["ai", "--diagnose-only"]]
        for args in actions {
            guard case .allowed(let command) = CommandPolicy.prepare(arguments: args, dryRun: true) else {
                return XCTFail("Inspection blocked: \(args)")
            }
            XCTAssertEqual(command.arguments, args)
        }
    }

    @MainActor
    func testGlobalPreviewIsAppliedAndPersisted() async throws {
        let script = try ExecutionFixture("printf '%s\\n' \"$@\"")
        defer { script.remove() }
        let suite = "MeisterAITests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let runner = CLIRunner(executable: script.path)
        await runner.waitForCapabilities()
        let app = AppState(runner: runner, preferences: preferences, refreshOnInit: false)
        app.dryRunDefault = true
        let completed = expectation(description: "preview completed")
        runner.onCompletion = { _ in completed.fulfill() }
        app.runCommand(["autofix"])
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertTrue(runner.liveOutput.contains("autofix\n--dry-run\n"))
        let restored = AppState(runner: CLIRunner(executable: script.path), preferences: preferences, refreshOnInit: false)
        XCTAssertTrue(restored.dryRunDefault)
        app.setTweak(id: "showhidden", on: true)
        XCTAssertFalse(runner.isRunning)
        XCTAssertTrue(app.tweaks.lastMessage.contains("gesperrt"))
        XCTAssertFalse(app.mayCreateConfiguration())
    }

    @MainActor
    func testNestedServiceChangesReachEnvironmentObject() {
        let app = AppState(refreshOnInit: false)
        var events = 0
        let token = app.objectWillChange.sink { events += 1 }
        app.runner.liveOutput = "new output"
        app.tweaks.lastMessage = "new message"
        app.status.score = "50/100"
        XCTAssertEqual(events, 3)
        withExtendedLifetime(token) {}
    }
}
