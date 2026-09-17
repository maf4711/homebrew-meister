import Foundation
import Combine

struct RunReportRepository: Sendable {
    let directory: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".meister", isDirectory: true)) {
        self.directory = directory
    }

    func load() async -> ReportSnapshot {
        let directory = directory
        return await Task.detached(priority: .utility) { Self.read(directory: directory) }.value
    }

    private static func read(directory: URL) -> ReportSnapshot {
        let manager = FileManager.default
        var snapshot = ReportSnapshot()
        if manager.fileExists(atPath: directory.path), !manager.isReadableFile(atPath: directory.path) {
            snapshot.notices.append("Das Berichtsverzeichnis ist nicht lesbar. Prüfe die Zugriffsrechte für ~/.meister.")
            return snapshot
        }
        var files: [URL] = []
        let latest = directory.appendingPathComponent("last.json")
        if manager.fileExists(atPath: latest.path) { files.append(latest) }
        let archive = directory.appendingPathComponent("runs", isDirectory: true)
        if manager.fileExists(atPath: archive.path) {
            do {
                let archived = try manager.contentsOfDirectory(at: archive, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
                    .filter { $0.pathExtension == "json" }
                    .sorted { $0.lastPathComponent > $1.lastPathComponent }
                files.append(contentsOf: archived.prefix(400))
                if archived.count > 400 { snapshot.notices.append("Für den Vergleich werden die neuesten 400 Archivdateien geladen.") }
            } catch {
                snapshot.notices.append("Das Berichtsarchiv konnte nicht gelesen werden. Prüfe die Zugriffsrechte für ~/.meister/runs.")
            }
        }
        var seen = Set<String>()
        var invalidArchiveCount = 0
        for file in files {
            do {
                let resource = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard resource.isRegularFile == true, (resource.fileSize ?? 0) <= 2_000_000 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let report = try JSONDecoder().decode(RunReport.self, from: Data(contentsOf: file))
                if seen.insert(report.id).inserted { snapshot.reports.append(report) }
            } catch {
                if file == latest {
                    snapshot.notices.append("Der neueste Bericht (last.json) ist nicht lesbar oder hat ein unbekanntes Format. Verfügbare archivierte Ergebnisse werden angezeigt.")
                } else {
                    invalidArchiveCount += 1
                }
            }
        }
        if invalidArchiveCount > 0 {
            snapshot.notices.append("\(invalidArchiveCount) Archivberichte konnten nicht gelesen werden; der Verlauf kann Lücken enthalten.")
        }
        snapshot.reports.sort { $0.timestamp == $1.timestamp ? $0.id > $1.id : $0.timestamp > $1.timestamp }
        return snapshot
    }
}

@MainActor
final class RunReportStore: ObservableObject {
    @Published private(set) var snapshot = ReportSnapshot()
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    private let repository: RunReportRepository
    private var generation = 0

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".meister", isDirectory: true), initialSnapshot: ReportSnapshot? = nil) {
        repository = RunReportRepository(directory: directory)
        if let initialSnapshot {
            snapshot = initialSnapshot
            hasLoaded = true
        }
    }

    func refresh() {
        generation += 1
        let currentGeneration = generation
        isLoading = true
        Task {
            let updated = await repository.load()
            guard currentGeneration == generation else { return }
            snapshot = updated
            hasLoaded = true
            isLoading = false
        }
    }
}
