import SwiftUI

struct AutomationView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Automation",
                    subtitle: "Geplante Wartung wie OnyX-Scheduling — LaunchAgent & wiederkehrende Jobs.",
                    systemImage: "clock.arrow.2.circlepath"
                )

                SectionBox(title: "LaunchAgent") {
                    VStack(spacing: 10) {
                        ActionCard(
                            title: "LaunchAgent installieren",
                            detail: "Periodische meisterSiri-Läufe (Schedule in config)",
                            systemImage: "calendar.badge.plus"
                        ) {
                            app.runCommand(["-I"])
                        }
                        ActionCard(
                            title: "Config öffnen",
                            detail: "~/.meister/config im Editor",
                            systemImage: "doc.text"
                        ) {
                            openConfig()
                        }
                        ActionCard(
                            title: "Log-Ordner",
                            detail: "~/.meister im Finder",
                            systemImage: "folder"
                        ) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.meister"))
                        }
                    }
                }

                SectionBox(title: "Empfohlener Rhythmus") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Täglich: meisterSiri --quick", systemImage: "1.circle.fill")
                        Label("Wöchentlich: meisterSiri --deep", systemImage: "7.circle.fill")
                        Label("Sudo einmal: meisterSiri sudo-setup", systemImage: "touchid")
                    }
                    .font(.subheadline)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
            .padding(24)
            .disabled(app.runner.isRunning)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func openConfig() {
        let path = NSHomeDirectory() + "/.meister/config"
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(
                atPath: NSHomeDirectory() + "/.meister",
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: path, contents: "# MeisterSiri config\n".data(using: .utf8))
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
