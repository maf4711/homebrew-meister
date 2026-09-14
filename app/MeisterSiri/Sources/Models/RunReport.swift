import Foundation

/// The CLI's backwards-compatible `meister.last/v1` report. Missing measurements stay unknown.
struct RunReport: Decodable, Equatable, Identifiable, Sendable {
    enum Status: String, Decodable, Sendable {
        case completed, partial, interrupted

        var title: String {
            switch self {
            case .completed: return "Abgeschlossen"
            case .partial: return "Unvollständig – Teilergebnis"
            case .interrupted: return "Abgebrochen – Teilergebnis"
            }
        }
    }

    struct Module: Decodable, Equatable, Sendable {
        let name: String
        let status: String
        let durationSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case name, status
            case durationSeconds = "duration_sec"
        }
    }

    let runID: String?
    let timestamp: Date
    let profile: String
    let twin: String
    let status: Status
    let isPreview: Bool
    let executionIsKnown: Bool
    let score: Int?
    let fixedCount: Int
    let warningCount: Int
    let errorCount: Int
    let verifiedCount: Int?
    let freedBytes: Int64?
    let durationSeconds: Int?
    let fixes: [String]
    let warnings: [String]
    let errors: [String]
    let proposedFixes: [String]
    let plannedModules: [String]
    let reportKind: String?
    let modules: [Module]

    var id: String { runID ?? "\(timestamp.timeIntervalSince1970)|\(twin)|\(profile)|\(isPreview)" }
    var openCount: Int { warningCount + errorCount }
    var foundCount: Int { fixedCount + openCount + proposedFixes.count }
    var isCompleted: Bool { executionIsKnown && status == .completed }
    var statusTitle: String { executionIsKnown ? status.title : "Ausführungsart unbekannt" }
    var profileTitle: String {
        switch profile {
        case "quick": return "Quick"
        case "auto": return "Auto (Daily)"
        case "deep": return "Deep (Weekly)"
        case "all": return "Alle Module"
        default: return profile
        }
    }

    var storageDescription: String {
        guard executionIsKnown, !isPreview, let freedBytes else { return "Nicht gemessen" }
        return ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)
    }

    func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(timestamp) > 24 * 60 * 60
    }

    func hasFutureTimestamp(at now: Date = Date()) -> Bool {
        timestamp.timeIntervalSince(now) > 5 * 60
    }

    enum CodingKeys: String, CodingKey {
        case schema, profile, twin, status, score, fixes, warnings, errors, modules
        case runID = "run_id", timestamp = "ts", isPreview = "dry_run"
        case fixedCount = "fix", warningCount = "warn", errorCount = "err"
        case verifiedCount = "verified_repair_count", freedBytes = "freed_bytes"
        case durationSeconds = "duration_sec", proposedFixes = "would_fix"
        case plannedModules = "planned_modules", reportKind = "report_kind"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(String.self, forKey: .schema) == "meister.last/v1" else {
            throw DecodingError.dataCorruptedError(forKey: .schema, in: values, debugDescription: "Unbekanntes Berichtformat")
        }
        let dateText = try values.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalDate = formatter.date(from: dateText)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractionalDate ?? formatter.date(from: dateText) else {
            throw DecodingError.dataCorruptedError(forKey: .timestamp, in: values, debugDescription: "Ungültiger Zeitpunkt")
        }
        timestamp = date
        runID = try values.decodeIfPresent(String.self, forKey: .runID)
        profile = try values.decode(String.self, forKey: .profile)
        twin = try values.decodeIfPresent(String.self, forKey: .twin) ?? "meister"
        let decodedStatus = try values.decodeIfPresent(Status.self, forKey: .status)
        let decodedPreview = try values.decodeIfPresent(Bool.self, forKey: .isPreview)
        executionIsKnown = decodedStatus != nil && decodedPreview != nil
        status = decodedStatus ?? .completed
        isPreview = decodedPreview ?? false
        score = try values.decodeIfPresent(Int.self, forKey: .score)
        fixedCount = try values.decodeIfPresent(Int.self, forKey: .fixedCount) ?? 0
        warningCount = try values.decodeIfPresent(Int.self, forKey: .warningCount) ?? 0
        errorCount = try values.decodeIfPresent(Int.self, forKey: .errorCount) ?? 0
        let decodedVerified = try values.decodeIfPresent(Int.self, forKey: .verifiedCount)
        verifiedCount = executionIsKnown ? decodedVerified : nil
        freedBytes = try values.decodeIfPresent(Int64.self, forKey: .freedBytes)
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds)
        fixes = try values.decodeIfPresent([String].self, forKey: .fixes) ?? []
        warnings = try values.decodeIfPresent([String].self, forKey: .warnings) ?? []
        errors = try values.decodeIfPresent([String].self, forKey: .errors) ?? []
        proposedFixes = try values.decodeIfPresent([String].self, forKey: .proposedFixes) ?? []
        plannedModules = try values.decodeIfPresent([String].self, forKey: .plannedModules) ?? []
        reportKind = try values.decodeIfPresent(String.self, forKey: .reportKind)
        modules = try values.decodeIfPresent([Module].self, forKey: .modules) ?? []
        // Counts are bounded to prevent corrupt input overflowing the derived totals.
        guard [fixedCount, warningCount, errorCount, verifiedCount ?? 0, durationSeconds ?? 0]
            .allSatisfy({ (0...1_000_000_000).contains($0) }),
            freedBytes ?? 0 >= 0, score.map({ (0...100).contains($0) }) ?? true,
            (decodedVerified ?? 0) <= fixedCount,
            !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Ungültige Berichtwerte"))
        }
        guard !isPreview || (fixedCount == 0 && (verifiedCount ?? 0) == 0 && freedBytes == nil) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Vorschau enthält echte Reparaturwerte"))
        }
    }
}

struct ReportSnapshot: Equatable, Sendable {
    var reports: [RunReport] = []
    var notices: [String] = []

    var latestActual: RunReport? { reports.first(where: { $0.executionIsKnown && !$0.isPreview }) }
    var latestPreview: RunReport? { reports.first(where: { $0.executionIsKnown && $0.isPreview }) }
    var latestLegacy: RunReport? { reports.first(where: { !$0.executionIsKnown }) }

    /// Compare finished runs of the same profile/twin. Prefer the latest prior day.
    func comparison(for report: RunReport, calendar: Calendar = .current, now: Date = Date()) -> RunReport? {
        guard !report.isPreview, report.isCompleted, !report.hasFutureTimestamp(at: now) else { return nil }
        let candidates = reports.filter {
            !$0.isPreview && $0.isCompleted && !$0.hasFutureTimestamp(at: now) && $0.id != report.id && $0.timestamp < report.timestamp
                && $0.profile == report.profile && $0.twin == report.twin
        }
        let dayStart = calendar.startOfDay(for: report.timestamp)
        return candidates.first(where: { $0.timestamp < dayStart }) ?? candidates.first
    }

    var emptyMessage: String {
        if !notices.isEmpty {
            return "Kein lesbarer Wartungsbericht verfügbar. Prüfe den Zugriff auf ~/.meister und starte bei Bedarf ein Wartungsprofil."
        }
        if latestPreview != nil {
            return "Bisher ist nur eine Vorschau vorhanden. Starte in Wartung ein Profil ohne Dry-Run, um ein tatsächliches Ergebnis zu erhalten."
        }
        return "Noch kein Wartungsbericht. Starte unter Wartung ein Profil; abgeschlossene Läufe erscheinen anschließend hier."
    }
}
