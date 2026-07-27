import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selection: SidebarItem = .maintenance
    @Published var dryRunDefault = false

    let runner = CLIRunner()
    let tweaks = TweaksService()
    let status = SystemStatus()

    init() {
        tweaks.refresh()
        status.refresh(using: runner)
    }

    func runMaintenance(profile: MaintenanceProfile, dryRun: Bool? = nil) {
        selection = .log
        var args = [profile.flag]
        if dryRun ?? dryRunDefault {
            args.append("-n")
        }
        runner.run(arguments: args, clearLog: true)
    }

    func runCommand(_ args: [String], clearLog: Bool = true) {
        selection = .log
        runner.run(arguments: args, clearLog: clearLog)
    }

    func refreshAll() {
        status.refresh(using: runner)
        tweaks.refresh()
    }
}
