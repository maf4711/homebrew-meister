import SwiftUI

struct CleaningView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Reinigung",
                    subtitle: "Gezielte Aufräum-Aktionen wie in OnyX — jeweils über meisterSiri, mit Dry-Run-Schalter.",
                    systemImage: "trash.fill"
                )

                SectionBox(title: "System & Speicher") {
                    VStack(spacing: 10) {
                        ActionCard(
                            title: "Healer",
                            detail: "Broken Symlinks, Orphans, DNS, Casks — proaktiv",
                            systemImage: "cross.case.fill",
                            accent: .green
                        ) {
                            var args = ["heal"]
                            if app.dryRunDefault { args.append("--dry-run") }
                            app.runCommand(args)
                        }
                        ActionCard(
                            title: "RAM freigeben",
                            detail: "sudo purge (braucht Sudo/Touch ID einmal)",
                            systemImage: "memorychip.fill"
                        ) {
                            app.runCommand(["free"])
                        }
                        ActionCard(
                            title: "RAM + UI-Reset",
                            detail: "purge + Finder/Dock neu starten",
                            systemImage: "arrow.triangle.2.circlepath"
                        ) {
                            app.runCommand(["free", "--restart-ui"])
                        }
                    }
                }

                SectionBox(title: "Apps & Leftovers") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ActionCard(title: "Orphans scannen", detail: "Leftovers deinstallierter Apps", systemImage: "shippingbox") {
                            var args = ["orphans"]
                            if app.dryRunDefault { args.append("--dry-run") }
                            app.runCommand(args)
                        }
                        ActionCard(title: "App-Updates", detail: "brew + App Store + Sparkle", systemImage: "arrow.down.app") {
                            app.runCommand(["appupdates"])
                        }
                        ActionCard(title: "Simulator Fix", detail: "hängende iOS Simulatoren", systemImage: "iphone") {
                            app.runCommand(["simfix"])
                        }
                        ActionCard(title: "Disk analysieren", detail: "Top-Ordner unter ~", systemImage: "externaldrive") {
                            app.runCommand(["disk"])
                        }
                    }
                }

                Text("Für Full-Clean: Wartung → Deep. Deep enthält Dev-Caches, .DS_Store, Docs-Order u. a.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .disabled(app.runner.isRunning)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
