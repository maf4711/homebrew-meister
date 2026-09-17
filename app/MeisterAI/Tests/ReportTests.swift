import XCTest
@testable import MeisterAI

enum ReportFixture {
    static func data(id: String = "run-1", timestamp: String = "2026-09-14T09:00:00Z", overrides: [String: Any] = [:]) throws -> Data {
        var fields: [String: Any] = [
            "schema": "meister.last/v1", "run_id": id, "ts": timestamp,
            "profile": "auto", "twin": "MeisterAI", "status": "completed", "dry_run": false,
            "fix": 2, "warn": 1, "err": 0, "verified_repair_count": 1,
            "freed_bytes": NSNull(), "fixes": ["Cache entfernt", "Dienst repariert"],
            "warnings": ["Backup prüfen"], "errors": [], "would_fix": []
        ]
        fields.merge(overrides) { _, new in new }
        return try JSONSerialization.data(withJSONObject: fields)
    }

    static func report(id: String = "run-1", timestamp: String = "2026-09-14T09:00:00Z", overrides: [String: Any] = [:]) throws -> RunReport {
        try JSONDecoder().decode(RunReport.self, from: data(id: id, timestamp: timestamp, overrides: overrides))
    }

    static func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MeisterReportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

final class ReportTests: XCTestCase {
    func testLegacyReportKeepsUnmeasuredFieldsUnknown() throws {
        let data = Data(#"{"schema":"meister.last/v1","ts":"2026-09-14T09:00:00Z","profile":"auto","fix":2,"warn":3,"err":1}"#.utf8)
        let report = try JSONDecoder().decode(RunReport.self, from: data)
        XCTAssertNil(report.verifiedCount)
        XCTAssertNil(report.freedBytes)
        XCTAssertFalse(report.executionIsKnown)
        XCTAssertFalse(report.isCompleted)
        XCTAssertNil(ReportSnapshot(reports: [report]).latestActual)
        XCTAssertEqual(report.storageDescription, "Nicht gemessen")
        XCTAssertEqual(report.foundCount, 6)
        XCTAssertEqual(report.openCount, 4)
    }

    func testEnrichedReportAndFractionalTimestamp() throws {
        let report = try ReportFixture.report(timestamp: "2026-09-14T09:00:00.123Z", overrides: [
            "freed_bytes": 8192, "score": 91,
            "modules": [["name": "Cleanup", "status": "OK", "duration_sec": 2]]
        ])
        XCTAssertEqual(report.verifiedCount, 1)
        XCTAssertEqual(report.freedBytes, 8192)
        XCTAssertEqual(report.score, 91)
        XCTAssertEqual(report.modules.first?.durationSeconds, 2)
        XCTAssertFalse(report.isStale(at: report.timestamp.addingTimeInterval(60)))
        XCTAssertTrue(report.isStale(at: report.timestamp.addingTimeInterval(86_401)))
    }

    func testInvalidSchemaDateAndCountsAreRejected() throws {
        for invalid in [["schema": "meister.last/v999"], ["ts": "tomorrow"], ["fix": -1], ["warn": Int.max], ["freed_bytes": -1], ["score": 101], ["verified_repair_count": 3], ["profile": " "]] as [[String: Any]] {
            XCTAssertThrowsError(try ReportFixture.report(overrides: invalid))
        }
    }

    func testPreviewCannotClaimRepairsOrMeasuredSavings() throws {
        let preview = try ReportFixture.report(overrides: ["dry_run": true, "fix": 0, "verified_repair_count": 0, "would_fix": ["Cache würde entfernt"]])
        XCTAssertTrue(preview.isPreview)
        XCTAssertEqual(preview.foundCount, 2)
        XCTAssertEqual(preview.fixedCount, 0)
        XCTAssertThrowsError(try ReportFixture.report(overrides: ["dry_run": true]))
        XCTAssertThrowsError(try ReportFixture.report(overrides: ["dry_run": true, "fix": 0, "verified_repair_count": 0, "freed_bytes": 10]))
    }

    func testComparisonPrefersEarlierDayAndExcludesPreviewPartialAndOtherProfiles() throws {
        let latest = try ReportFixture.report()
        let sameDay = try ReportFixture.report(id: "same", timestamp: "2026-09-14T08:00:00Z")
        let yesterday = try ReportFixture.report(id: "prior-day", timestamp: "2026-09-13T08:00:00Z")
        let incomplete = try ReportFixture.report(id: "partial", timestamp: "2026-09-13T09:00:00Z", overrides: ["status": "partial"])
        let otherProfile = try ReportFixture.report(id: "deep", timestamp: "2026-09-13T10:00:00Z", overrides: ["profile": "deep"])
        let otherTwin = try ReportFixture.report(id: "other", timestamp: "2026-09-13T11:00:00Z", overrides: ["twin": "meister"])
        let preview = try ReportFixture.report(id: "preview", timestamp: "2026-09-13T12:00:00Z", overrides: ["dry_run": true, "fix": 0, "verified_repair_count": 0])
        let snapshot = ReportSnapshot(reports: [latest, sameDay, preview, otherTwin, otherProfile, incomplete, yesterday])
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(snapshot.comparison(for: latest, calendar: utc, now: latest.timestamp)?.id, yesterday.id)
        XCTAssertNil(snapshot.comparison(for: incomplete))
        XCTAssertNil(snapshot.comparison(for: preview))
    }

    func testRepositoryRecoversArchiveAndSeparatesPreview() async throws {
        let directory = try ReportFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("runs")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("last.json"))
        try ReportFixture.data(id: "actual").write(to: archive.appendingPathComponent("20260914-actual.json"))
        try ReportFixture.data(id: "preview", timestamp: "2026-09-14T10:00:00Z", overrides: ["dry_run": true, "fix": 0, "verified_repair_count": 0])
            .write(to: archive.appendingPathComponent("20260914-preview.json"))
        let result = await RunReportRepository(directory: directory).load()
        XCTAssertEqual(result.latestActual?.id, "actual")
        XCTAssertEqual(result.latestPreview?.id, "preview")
        XCTAssertEqual(result.notices.count, 1)
        XCTAssertTrue(result.notices[0].contains("last.json"))
    }

    func testRepositoryDeduplicatesLatestAndRetainsInterruptedStatus() async throws {
        let directory = try ReportFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("runs")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let data = try ReportFixture.data(overrides: ["status": "interrupted"])
        try data.write(to: directory.appendingPathComponent("last.json"))
        try data.write(to: archive.appendingPathComponent("run.json"))
        let result = await RunReportRepository(directory: directory).load()
        XCTAssertEqual(result.reports.count, 1)
        XCTAssertEqual(result.latestActual?.status, .interrupted)
        XCTAssertNil(result.comparison(for: try XCTUnwrap(result.latestActual)))
    }

    func testMissingAndMalformedReportsHaveDistinctStates() async throws {
        let directory = try ReportFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RunReportRepository(directory: directory)
        let empty = await repository.load()
        XCTAssertTrue(empty.notices.isEmpty)
        XCTAssertTrue(empty.emptyMessage.contains("Noch kein"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("last.json"))
        let broken = await repository.load()
        XCTAssertFalse(broken.notices.isEmpty)
        XCTAssertTrue(broken.emptyMessage.contains("Kein lesbarer"))
    }
}
