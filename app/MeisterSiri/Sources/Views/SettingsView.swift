import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section("Ausführung") {
                Toggle("Dry-Run standardmäßig", isOn: $app.dryRunDefault)
                LabeledContent("CLI") {
                    Text(app.status.cliPath)
                        .font(.caption)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Section("Hinweis") {
                Text("Profile und Timeouts steuerst du über ~/.meister/config bzw. meisterSiri --quick/--deep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
