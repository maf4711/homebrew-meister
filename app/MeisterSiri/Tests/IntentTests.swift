import XCTest
@testable import MeisterSiri

final class IntentTests: XCTestCase {
    func testLegacyReportCannotBecomeVerifiedActualRun() throws {
        let report = try ReportFixture.report(overrides: ["dry_run": NSNull(), "status": NSNull()])
        let response = ReportIntentResponse.make(snapshot: .init(reports: [report]), detailed: true)
        XCTAssertTrue(response.summary.contains("älterer Bericht"))
        XCTAssertTrue(response.summary.contains("unterscheidet echte Wartung und Vorschau nicht"))
        XCTAssertFalse(response.summary.contains("Letzter tatsächlicher Lauf"))
        XCTAssertNil(ReportSnapshot(reports: [report]).comparison(for: report))
    }

    func testFutureTimestampIsDisclosed() throws {
        let report = try ReportFixture.report()
        let response = ReportIntentResponse.make(snapshot: .init(reports: [report]), detailed: false, now: report.timestamp.addingTimeInterval(-600))
        XCTAssertTrue(response.summary.contains("in der Zukunft"))
        XCTAssertNil(ReportSnapshot(reports: [report]).comparison(for: report, now: report.timestamp.addingTimeInterval(-600)))
    }

    func testHealthResponseDescribesHistoricalDataInsteadOfClaimingCurrentHealth() throws {
        let report = try ReportFixture.report()
        let response = ReportIntentResponse.make(snapshot: .init(reports: [report]), detailed: false, now: report.timestamp.addingTimeInterval(90_000))
        XCTAssertTrue(response.summary.contains("Letzter tatsächlicher Lauf"))
        XCTAssertTrue(response.summary.contains("1 offene Meldungen"))
        XCTAssertTrue(response.summary.contains("älter als 24 Stunden"))
        XCTAssertTrue(response.details.contains("Nicht gemessen"))
    }

    func testPreviewOnlyAndMalformedDataDoNotBecomeHealthClaims() throws {
        let preview = try ReportFixture.report(overrides: ["dry_run": true, "fix": 0, "verified_repair_count": 0])
        let response = ReportIntentResponse.make(snapshot: .init(reports: [preview]), detailed: true)
        XCTAssertEqual(response.title, "Kein Wartungsergebnis")
        XCTAssertTrue(response.summary.contains("nur eine Vorschau"))
        let broken = ReportIntentResponse.make(snapshot: .init(notices: ["Ungültiger Bericht"]), detailed: true)
        XCTAssertTrue(broken.summary.contains("Kein lesbarer"))
    }

    func testDetailedResponseIncludesOpenIssuesAndIncompleteState() throws {
        let report = try ReportFixture.report(overrides: ["status": "interrupted"])
        let response = ReportIntentResponse.make(snapshot: .init(reports: [report]), detailed: true, now: report.timestamp)
        XCTAssertTrue(response.summary.contains("Abgebrochen"))
        XCTAssertTrue(response.details.contains("Offen: Backup prüfen"))
        XCTAssertTrue(response.details.contains("Reparatur: Cache entfernt"))
    }

    func testIntentReaderDoesNotWriteToReportDirectory() async throws {
        let directory = try ReportFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try ReportFixture.data()
        let file = directory.appendingPathComponent("last.json")
        try original.write(to: file)
        let response = await ReportIntentResponse.load(directory: directory, detailed: true)
        XCTAssertTrue(response.details.contains("Backup prüfen"))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["last.json"])
        XCTAssertFalse(MacHealthIntent.openAppWhenRun)
        XCTAssertFalse(LastMaintenanceReportIntent.openAppWhenRun)
    }

    func testUnusableNewerReportIsDisclosedWhenFallingBack() throws {
        let report = try ReportFixture.report()
        let response = ReportIntentResponse.make(snapshot: .init(reports: [report], notices: ["last.json nicht lesbar"]), detailed: true, now: report.timestamp)
        XCTAssertTrue(response.summary.contains("unvollständig"))
        XCTAssertTrue(response.summary.contains("älter sein"))
        XCTAssertTrue(response.details.contains("last.json nicht lesbar"))
    }
}
