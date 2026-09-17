import AppIntents
import SwiftUI

/// Shared read-only response construction, injectable for tests without accessing real user data.
struct ReportIntentResponse: Equatable, Sendable {
    let title: String
    let summary: String
    let details: String

    static func load(directory: URL? = nil, detailed: Bool, now: Date = Date()) async -> ReportIntentResponse {
        let repository = directory.map { RunReportRepository(directory: $0) } ?? RunReportRepository()
        return make(snapshot: await repository.load(), detailed: detailed, now: now)
    }

    static func make(snapshot: ReportSnapshot, detailed: Bool, now: Date = Date()) -> ReportIntentResponse {
        guard let report = snapshot.latestActual else {
            if let legacy = snapshot.latestLegacy {
                let summary = "Gespeicherter älterer Bericht vom \(legacy.timestamp.formatted(date: .abbreviated, time: .shortened)), Profil \(legacy.profileTitle): \(legacy.openCount) offene Meldungen. Dieser Bericht unterscheidet echte Wartung und Vorschau nicht. Ausgeführte Reparaturen und der aktuelle Zustand deines Macs sind damit nicht belegt."
                return .init(title: "Älterer Bericht · Ausführungsart unbekannt", summary: summary, details: snapshot.notices.joined(separator: "\n"))
            }
            return .init(title: "Kein Wartungsergebnis", summary: snapshot.emptyMessage, details: snapshot.notices.joined(separator: "\n"))
        }
        let date = report.timestamp.formatted(date: .abbreviated, time: .shortened)
        let verification = report.verifiedCount.map { "\($0) Reparaturen nachgeprüft" } ?? "Nachprüfungen nicht erfasst"
        var summary = "Letzter tatsächlicher Lauf am \(date), Profil \(report.profileTitle): \(report.status.title). \(report.fixedCount) Reparaturmeldungen, \(verification), \(report.openCount) offene Meldungen."
        if !snapshot.notices.isEmpty { summary += " Beim Laden gab es Hinweise; der Verlauf kann unvollständig und das Ergebnis älter sein." }
        if report.isStale(at: now) { summary += " Der Bericht ist älter als 24 Stunden und keine aktuelle Systemprüfung." }
        if report.hasFutureTimestamp(at: now) { summary += " Der Berichtzeitpunkt liegt in der Zukunft. Bitte prüfe Datum und Uhrzeit; die Aktualität ist unklar." }
        if let preview = snapshot.latestPreview, preview.timestamp > report.timestamp {
            summary += " Eine neuere Vorschau ist nicht als Reparatur gezählt."
        }
        var detailLines = ["Gefunden: \(report.foundCount) Meldungen.", "Entfernte Dateidaten: \(report.storageDescription) (gemessene Teilmenge, keine Messung des freien Speicherplatzes)."]
        detailLines += snapshot.notices
        if detailed {
            detailLines += (report.errors + report.warnings).prefix(5).map { "Offen: \($0)" }
            detailLines += report.fixes.prefix(5).map { "Reparatur: \($0)" }
            if report.openCount > 0 && report.errors.isEmpty && report.warnings.isEmpty {
                detailLines.append("Dieser ältere Bericht enthält keine Einzelheiten zu den offenen Meldungen.")
            }
            if report.errors.count + report.warnings.count > 5 || report.fixes.count > 5 {
                detailLines.append("Weitere Einzelheiten stehen in MeisterAI unter Ergebnisse.")
            }
        }
        return .init(title: detailed ? "Letzter Wartungsbericht" : "Wie geht es meinem Mac?", summary: summary, details: detailLines.joined(separator: "\n"))
    }
}

struct MacHealthIntent: AppIntent {
    static let title: LocalizedStringResource = "Wie geht es meinem Mac?"
    static let description = IntentDescription("Liest den letzten gespeicherten Wartungsbericht und nennt offene Punkte. Startet keine Systemprüfung oder Reparatur.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let response = await ReportIntentResponse.load(detailed: false)
        return .result(value: response.summary, dialog: "\(response.summary)") {
            ReportIntentSnippet(response: response)
        }
    }
}

struct LastMaintenanceReportIntent: AppIntent {
    static let title: LocalizedStringResource = "Zeige den letzten Wartungsbericht"
    static let description = IntentDescription("Zeigt das letzte tatsächliche Wartungsergebnis mit Reparaturen und offenen Punkten. Vorschauen werden getrennt behandelt.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let response = await ReportIntentResponse.load(detailed: true)
        return .result(value: response.summary + "\n" + response.details, dialog: "\(response.summary)") {
            ReportIntentSnippet(response: response)
        }
    }
}

struct MeisterAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MacHealthIntent(), phrases: [
            "Wie geht es meinem Mac mit \(.applicationName)",
            "Frage \(.applicationName) wie es meinem Mac geht"
        ], shortTitle: "Mac-Zustand", systemImageName: "heart.text.square")
        AppShortcut(intent: LastMaintenanceReportIntent(), phrases: [
            "Zeige den letzten Wartungsbericht in \(.applicationName)",
            "Zeige das letzte Ergebnis von \(.applicationName)"
        ], shortTitle: "Letzter Bericht", systemImageName: "chart.bar.doc.horizontal")
    }
}

struct ReportIntentSnippet: View {
    let response: ReportIntentResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(response.title, systemImage: "chart.bar.doc.horizontal").font(.headline)
            Text(response.summary)
            if !response.details.isEmpty { Text(response.details).font(.caption).foregroundStyle(.secondary) }
        }
        .padding()
    }
}
