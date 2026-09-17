import SwiftUI

struct SecurityView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Sicherheit",
                    subtitle: "Status, Privacy und einmaliges Sudo-Setup — analog zu OnyX-Verifikation.",
                    systemImage: "lock.shield.fill"
                )

                SectionBox(title: "Live-Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(app.status.rows) { row in
                            HStack {
                                statusDot(row.ok)
                                Text(row.label)
                                    .frame(width: 110, alignment: .leading)
                                Text(row.value)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                }

                SectionBox(title: "Aktionen") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ActionCard(title: "Doctor", detail: "SIP, FV, Firewall, AI, Disk…", systemImage: "stethoscope") {
                            app.runCommand(["doctor"])
                        }
                        ActionCard(title: "Privacy Audit", detail: "FDA / LaunchDaemons Überblick", systemImage: "hand.raised.fill") {
                            app.runCommand(["privacy"])
                        }
                        ActionCard(title: "Startup Audit", detail: "Login Items & Agents", systemImage: "power") {
                            app.runCommand(["startup"])
                        }
                        ActionCard(title: "Sudo-Setup", detail: "2h Shared-Ticket (!tty_tickets)", systemImage: "touchid") {
                            app.runCommand(["sudo-setup"])
                        }
                        ActionCard(title: "Touch ID sudo", detail: "pam_tid aktivieren", systemImage: "fingerprint") {
                            app.runCommand(["touchid"])
                        }
                        ActionCard(title: "TCC Clean", detail: "Verwaiste Privacy-Grants (Dry-Run)", systemImage: "trash.slash") {
                            app.runCommand(["tcc-clean"])
                        }
                    }
                    .disabled(app.runner.isRunning)
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { app.status.refresh(using: app.runner) }
    }

    @ViewBuilder
    private func statusDot(_ ok: Bool?) -> some View {
        Circle()
            .fill(ok == true ? Color.green : (ok == false ? Color.orange : Color.gray.opacity(0.4)))
            .frame(width: 8, height: 8)
    }
}
