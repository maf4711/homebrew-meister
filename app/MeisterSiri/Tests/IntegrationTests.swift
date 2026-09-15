import XCTest
import SwiftUI
import AppKit
@testable import MeisterSiri

final class IntegrationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testExecutionPlanKeepsPlannedModulesSeparateFromFindings() throws {
        let data = Data(#"{"schema":"meister.last/v1","ts":"2026-09-14T12:00:00Z","profile":"quick","twin":"meisterSiri","status":"completed","dry_run":true,"report_kind":"execution_plan","planned_modules":["Homebrew","Cleanup"],"fix":0,"warn":0,"err":0,"verified_repair_count":0,"score":null,"freed_bytes":null}"#.utf8)
        let report = try JSONDecoder().decode(RunReport.self, from: data)
        XCTAssertEqual(report.plannedModules, ["Homebrew", "Cleanup"])
        XCTAssertEqual(report.reportKind, "execution_plan")
        XCTAssertEqual(report.foundCount, 0)
        XCTAssertNil(ReportSnapshot(reports: [report]).latestActual)
    }

    @MainActor
    func testCLIReportReachesDashboardAndSiri() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Exercise the real shell serializer against the Swift consumer using only
        // temporary data. No maintenance CLI or system-repair command is invoked.
        let script = #"""
        MEISTER_DIR="$1"
        source "$2"
        scutil() { printf 'fixture-host'; }
        AI_BACKEND_KIND=apple
        RUN_ID=integration-report
        RUN_STATUS=completed
        DRY_RUN=false
        VERIFIED_REPAIR_COUNT=1
        FREED_BYTES=4096
        FREED_BYTES_SCOPE=measured_file_removals
        REPORT_FIXED=('Defekte Verknüpfung repariert' 'Dateicache bereinigt')
        REPORT_WARNINGS=('Time Machine: letztes Backup prüfen')
        REPORT_ERRORS=()
        REPORT_WOULD_FIX=()
        MODULE_LEDGER=('FIX|Cleanup|1')
        write_last_json 91 12 2 1 0 0 1 quick integration
        """#
        let result = await ProcessExecution().run(executable: "/bin/bash", arguments: [
            "-c", script, "report-fixture", directory.path,
            repositoryRoot.appendingPathComponent("lib/core/last_json.sh").path
        ], timeout: 10)
        XCTAssertEqual(result.code, 0, result.output)
        let snapshot = await RunReportRepository(directory: directory).load()
        let report = try XCTUnwrap(snapshot.latestActual)
        XCTAssertEqual(report.fixedCount, 2)
        XCTAssertEqual(report.verifiedCount, 1)
        XCTAssertEqual(report.openCount, 1)
        XCTAssertEqual(report.freedBytes, 4096)
        XCTAssertEqual(snapshot.reports.count, 1, "last.json and archive must be deduplicated")
        let response = await ReportIntentResponse.load(directory: directory, detailed: true)
        XCTAssertTrue(response.summary.contains("2 Reparaturmeldungen"))
        XCTAssertTrue(response.details.contains("Time Machine"))

        let store = RunReportStore(directory: directory, initialSnapshot: snapshot)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "meister-integration-\(UUID().uuidString)"))
        let app = AppState(runner: CLIRunner(executable: "/bin/false"), preferences: preferences, refreshOnInit: false)
        let dashboard = DashboardView(store: store).environmentObject(app)
            .frame(width: 1000, height: 1000)
        // ImageRenderer does not draw AppKit-backed scroll views. Host the actual
        // hierarchy so this evidence includes the same dashboard the app displays.
        let host = NSHostingView(rootView: dashboard)
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 1000, height: 1000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.orderBack(nil)
        try await Task.sleep(nanoseconds: 150_000_000)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let evidence = repositoryRoot.appendingPathComponent("app/MeisterSiri/build/verification")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try png.write(to: evidence.appendingPathComponent("dashboard.png"))
        XCTAssertGreaterThan(png.count, 20_000, "Dashboard evidence must contain rendered content, not an empty surface")
    }
}
