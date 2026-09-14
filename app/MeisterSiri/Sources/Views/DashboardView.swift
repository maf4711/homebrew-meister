import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var store: RunReportStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Ergebnisse", subtitle: "Was die letzte Wartung gefunden, repariert und überprüft hat.", systemImage: "chart.bar.doc.horizontal")
                if store.isLoading && !store.hasLoaded {
                    ProgressView("Berichte werden geladen …")
                } else {
                    ForEach(store.snapshot.notices, id: \.self) { notice in
                        noticeLabel(notice, icon: "exclamationmark.triangle", color: .orange)
                    }
                    if let report = store.snapshot.latestActual {
                        reportContent(report)
                    } else if let legacy = store.snapshot.latestLegacy {
                        reportContent(legacy)
                    } else {
                        SectionBox(title: "Letzter tatsächlicher Lauf") {
                            Text(store.snapshot.emptyMessage).foregroundStyle(.secondary)
                            Button("Wartung öffnen") { app.selection = .maintenance }
                        }
                    }
                    if let preview = store.snapshot.latestPreview {
                        previewContent(preview)
                    }
                }
                HStack {
                    Button("Berichte aktualisieren") { store.refresh() }
                        .disabled(store.isLoading)
                    Spacer()
                    Text("Lokal aus ~/.meister · ohne Systemprüfung")
                        .font(.caption).foregroundStyle(.secondary)
                }
                shortcutsHelp
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.refresh() }
    }

    @ViewBuilder
    private func reportContent(_ report: RunReport) -> some View {
        SectionBox(title: report.executionIsKnown ? "Letzter tatsächlicher Lauf" : "Früherer Bericht · Ausführungsart unbekannt") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.profileTitle).font(.title3.weight(.semibold))
                    Text(report.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(report.statusTitle, systemImage: !report.executionIsKnown ? "questionmark.circle" : (report.status == .interrupted ? "stop.circle" : (report.openCount > 0 ? "exclamationmark.circle" : "checkmark.circle")))
                    .foregroundStyle(report.status == .interrupted || report.openCount > 0 ? Color.orange : Color.secondary)
            }
            if !report.executionIsKnown {
                noticeLabel("Dieser ältere Bericht unterscheidet echte Wartung und Vorschau nicht. Die Zähler sind keine Bestätigung ausgeführter Reparaturen. Ein neuer Lauf liefert eindeutige Ergebnisse.", icon: "questionmark.circle", color: .orange)
            }
            if report.hasFutureTimestamp() {
                noticeLabel("Der Berichtzeitpunkt liegt in der Zukunft. Prüfe Datum und Uhrzeit deines Macs; dieser Bericht wird nicht für Vergleiche verwendet.", icon: "calendar.badge.exclamationmark", color: .orange)
            }
            if report.isStale() {
                noticeLabel("Dieser Bericht ist älter als 24 Stunden. Er beschreibt den damaligen Zustand deines Macs.", icon: "clock", color: .secondary)
            }
            if report.executionIsKnown && !report.isCompleted {
                noticeLabel("Der Lauf wurde nicht vollständig abgeschlossen. Die Werte zeigen nur bis dahin erfasste Ergebnisse. Prüfe die offenen Punkte und das Protokoll.", icon: "stop.circle", color: .orange)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 12) {
                metric("Gefunden", value: String(report.foundCount), icon: "magnifyingglass")
                metric("Reparaturmeldungen", value: String(report.fixedCount), icon: "wrench.adjustable")
                metric("Verifiziert", value: report.verifiedCount.map(String.init) ?? "–", icon: "checkmark.seal")
                metric("Offen", value: String(report.openCount), icon: "exclamationmark.bubble")
            }
            Text("Gefunden zählt Reparaturmeldungen, Warnungen, Fehler und Vorschläge. Verifiziert zählt erfolgreiche Nachprüfungen; ältere Berichte erfassen sie nicht.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label("Entfernte Dateidaten: \(report.storageDescription)", systemImage: "internaldrive")
                    .help("Gemessene Teilmenge entfernter Dateien. Snapshots und offene Dateien können den tatsächlich freien Speicher beeinflussen.")
                Spacer()
                if let score = report.score { Text("Score \(score)/100") }
            }
            .font(.subheadline)
            if let previous = store.snapshot.comparison(for: report) {
                comparison(report, previous: previous)
            } else {
                Text("Noch kein vergleichbarer abgeschlossener Lauf mit demselben Profil und Programm vorhanden.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        SectionBox(title: "Einzelheiten") {
            messages("Offene Fehler", messages: report.errors, reportedCount: report.errorCount, icon: "xmark.circle", color: .red)
            messages("Offene Warnungen", messages: report.warnings, reportedCount: report.warningCount, icon: "exclamationmark.triangle", color: .orange)
            messages("Reparaturmeldungen", messages: report.fixes, reportedCount: report.fixedCount, icon: "wrench.adjustable", color: .secondary)
            if !report.proposedFixes.isEmpty {
                messages("Vorgeschlagen", messages: report.proposedFixes, reportedCount: report.proposedFixes.count, icon: "lightbulb", color: .secondary)
            }
            if report.openCount == 0 {
                Text(report.status == .interrupted ? "Bis zum Abbruch wurden keine offenen Punkte protokolliert." : "In diesem Lauf wurden keine offenen Punkte protokolliert.")
                    .foregroundStyle(.secondary)
            }
            if !report.modules.isEmpty {
                DisclosureGroup("Module (\(report.modules.count))") {
                    ForEach(Array(report.modules.enumerated()), id: \.offset) { _, module in
                        HStack {
                            Text(module.name)
                            Spacer()
                            Text(module.status).foregroundStyle(.secondary)
                            if let duration = module.durationSeconds { Text("\(duration) s").monospacedDigit() }
                        }
                        .font(.caption).padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func previewContent(_ report: RunReport) -> some View {
        SectionBox(title: "Letzte Vorschau · getrennt vom Ergebnis") {
            Label("\(report.profileTitle) · \(report.timestamp.formatted(date: .abbreviated, time: .shortened))", systemImage: "eye")
            Text("\(report.plannedModules.count) geplante Module · \(report.proposedFixes.count) Vorschläge · \(report.openCount) offene Meldungen. Profil-Vorschauen zeigen den Ablaufplan ohne Ausführung oder Detailprüfung der Module. Reparaturen und Speichergewinne werden dabei nicht gezählt.")
                .font(.subheadline).foregroundStyle(.secondary)
            if report.status == .interrupted {
                noticeLabel("Auch diese Vorschau wurde abgebrochen und ist unvollständig.", icon: "stop.circle", color: .orange)
            }
            messages("Ablaufplan und Vorschläge", messages: report.proposedFixes, reportedCount: report.proposedFixes.count, icon: "eye", color: .secondary)
            messages("Geplante Module", messages: report.plannedModules, reportedCount: report.plannedModules.count, icon: "list.bullet", color: .secondary)
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func comparison(_ report: RunReport, previous: RunReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Verglichen mit \(previous.timestamp.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption.weight(.semibold))
            Text("Offene Meldungen: \(delta(report.openCount - previous.openCount)) · Reparaturmeldungen: \(delta(report.fixedCount - previous.fixedCount))")
                .font(.caption)
            if let current = report.freedBytes, let earlier = previous.freedBytes {
                Text("Unterschied bei entfernten Dateidaten: \(current >= earlier ? "+" : "−")\(ByteCountFormatter.string(fromByteCount: abs(current - earlier), countStyle: .file))")
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary).padding(.top, 4)
    }

    @ViewBuilder
    private func messages(_ title: String, messages: [String], reportedCount: Int, icon: String, color: Color) -> some View {
        if reportedCount > 0 || !messages.isEmpty {
            DisclosureGroup("\(title) (\(reportedCount))") {
                if messages.isEmpty {
                    Text("Dieser ältere Bericht enthält nur Zähler. Einzelheiten stehen gegebenenfalls im bisherigen Protokoll.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    noticeLabel(message, icon: icon, color: color).textSelection(.enabled)
                }
            }
        }
    }

    private func noticeLabel(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).font(.subheadline).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func delta(_ number: Int) -> String { number > 0 ? "+\(number)" : String(number) }

    private var shortcutsHelp: some View {
        SectionBox(title: "Siri & Kurzbefehle") {
            Text("„Wie geht es meinem Mac mit MeisterSiri?“\n„Zeige den letzten Wartungsbericht in MeisterSiri“")
                .font(.subheadline).textSelection(.enabled)
            Text("Beide Kurzbefehle lesen den letzten gespeicherten Bericht. Sie starten keine Wartung.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
