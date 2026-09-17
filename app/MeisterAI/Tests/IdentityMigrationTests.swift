import XCTest
@testable import MeisterAI

final class IdentityMigrationTests: XCTestCase {
    func testAppIdentity() {
        let bundle = Bundle(for: AppState.self)
        XCTAssertEqual(bundle.bundleIdentifier, "com.maf4711.meisterai")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "MeisterAI")
    }

    func testMigrationCopiesOnlyKnownPreferencesOnce() throws {
        let name = "MeisterAI.migration.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        PreferenceMigration.migrate(to: preferences, legacy: ["dryRunDefault": true, "unrelated": "ignore"])
        XCTAssertTrue(preferences.bool(forKey: "dryRunDefault"))
        XCTAssertNil(preferences.object(forKey: "unrelated"))
        preferences.set(false, forKey: "dryRunDefault")
        PreferenceMigration.migrate(to: preferences, legacy: ["dryRunDefault": true])
        XCTAssertFalse(preferences.bool(forKey: "dryRunDefault"))
    }

    func testMigrationPreservesExplicitNewPreference() throws {
        let name = "MeisterAI.migration.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(false, forKey: "dryRunDefault")
        PreferenceMigration.migrate(to: preferences, legacy: ["dryRunDefault": true])
        XCTAssertFalse(preferences.bool(forKey: "dryRunDefault"))
    }

    func testHistoricalAppleReportsRemainComparableAndMeisterStaysSeparate() throws {
        let latest = try ReportFixture.report()
        for legacyName in ["meisterSiri", "MeisterSiri"] {
            let older = try ReportFixture.report(id: "old", timestamp: "2026-09-13T09:00:00Z",
                                               overrides: ["twin": legacyName])
            XCTAssertEqual(older.twin, "MeisterAI")
            XCTAssertEqual(ReportSnapshot(reports: [latest, older]).comparison(for: latest, now: latest.timestamp)?.id, older.id)
        }
        let ollama = try ReportFixture.report(overrides: ["twin": "meister"])
        XCTAssertEqual(ollama.twin, "meister")
    }
}
