import SwiftUI

struct InfoView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "MeisterSiri",
                    subtitle: "macOS-GUI im OnyX-Stil über meisterSiri CLI · Apple Intelligence on-device",
                    systemImage: "sparkles"
                )

                GroupBox("Versionen") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("App", value: "1.0.0")
                        LabeledContent("CLI", value: app.status.cliVersion)
                        LabeledContent("CLI-Pfad", value: app.status.cliPath)
                        LabeledContent("Score", value: app.status.score)
                        LabeledContent("Disk", value: app.status.disk)
                    }
                    .font(.subheadline)
                    .padding(6)
                }

                GroupBox("Über") {
                    Text("""
                    MeisterSiri.app steuert die bewährte Shell-CLI meisterSiri — \
                    Wartung, Reinigung, Parameter (OnyX-Tweaks), Security und Automation \
                    in einer nativen SwiftUI-Oberfläche.

                    Alle schweren Jobs laufen im CLI (mit Dry-Run, Profilen und Sudo-once). \
                    Die GUI streamt die Ausgabe und bündelt die häufigsten Aktionen.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(6)
                }

                HStack {
                    Link("GitHub homebrew-meister",
                         destination: URL(string: "https://github.com/maf4711/homebrew-meister")!)
                    Spacer()
                    Button("Status aktualisieren") { app.refreshAll() }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
