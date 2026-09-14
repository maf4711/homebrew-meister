import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selection: SidebarItem = .dashboard
    @Published var dryRunDefault: Bool {
        didSet { preferences.set(dryRunDefault, forKey: "dryRunDefault") }
    }

    let runner: CLIRunner
    let tweaks = TweaksService()
    let status = SystemStatus()
    let reports: RunReportStore
    private let preferences: UserDefaults
    private var observations = Set<AnyCancellable>()

    init(runner: CLIRunner? = nil, preferences: UserDefaults = .standard, reports: RunReportStore? = nil,
         refreshOnInit: Bool = ProcessInfo.processInfo.environment["MEISTER_DISABLE_STARTUP_CHECKS"] != "1") {
        let runner = runner ?? CLIRunner()
        self.runner = runner
        self.reports = reports ?? RunReportStore()
        self.preferences = preferences
        self.dryRunDefault = preferences.bool(forKey: "dryRunDefault")
        // EnvironmentObject does not automatically observe its nested services.
        [runner.objectWillChange, tweaks.objectWillChange, status.objectWillChange, self.reports.objectWillChange].forEach { publisher in
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        }
        runner.onCompletion = { [weak self] _ in self?.refreshAll() }
        if refreshOnInit { refreshAll() }
    }

    func runMaintenance(profile: MaintenanceProfile, dryRun: Bool? = nil) {
        execute([profile.flag], dryRun: dryRunDefault || (dryRun ?? false), clearLog: true)
    }

    func runCommand(_ args: [String], clearLog: Bool = true) {
        execute(args, dryRun: dryRunDefault, clearLog: clearLog)
    }

    func setTweak(id: String, on: Bool) {
        let args = ["tweaks", id, on ? "on" : "off"]
        switch CommandPolicy.prepare(arguments: args, dryRun: dryRunDefault) {
        case .blocked(let message):
            tweaks.lastMessage = message
            runner.recordBlocked(message, clearLog: false)
        case .allowed(let command):
            if runner.run(command: command, clearLog: true) {
                tweaks.lastMessage = "Änderung gestartet. Ergebnis im Protokoll; Status wird nach Abschluss aktualisiert."
            }
        }
    }

    func mayCreateConfiguration() -> Bool {
        if case .blocked(let message) = CommandPolicy.configurationCreation(dryRun: dryRunDefault) {
            selection = .log
            runner.recordBlocked(message)
            return false
        }
        return true
    }

    func refreshAll() {
        guard ProcessInfo.processInfo.environment["MEISTER_DISABLE_STARTUP_CHECKS"] != "1" else { return }
        reports.refresh()
        status.refresh(using: runner)
        tweaks.refresh()
    }

    private func execute(_ arguments: [String], dryRun: Bool, clearLog: Bool) {
        selection = .log
        switch CommandPolicy.prepare(arguments: arguments, dryRun: dryRun,
                                     supportsAIPreview: runner.supportsAIPreview,
                                     supportsProfilePreview: runner.supportsProfilePreview) {
        case .allowed(let command): runner.run(command: command, clearLog: clearLog)
        case .blocked(let message): runner.recordBlocked(message, clearLog: clearLog)
        }
    }
}
