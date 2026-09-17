import SwiftUI

@main
struct MeisterAIApp: App {
    @StateObject private var appState: AppState

    init() {
        if ProcessInfo.processInfo.environment["MEISTER_DISABLE_STARTUP_CHECKS"] != "1" {
            PreferenceMigration.migrate()
        }
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Wartung") {
                Button("Quick-Lauf") { appState.runMaintenance(profile: .quick) }
                    .keyboardShortcut("q", modifiers: [.command, .shift])
                Button("Deep-Lauf") { appState.runMaintenance(profile: .deep) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Dry-Run (Quick)") { appState.runMaintenance(profile: .quick, dryRun: true) }
                Divider()
                Button("Doctor") { appState.runCommand(["doctor"]) }
                Button("Today Briefing") { appState.runCommand(["today"]) }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 420, height: 280)
        }
    }
}
