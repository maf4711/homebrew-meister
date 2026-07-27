import SwiftUI

struct MaintenanceView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Wartung",
                    subtitle: "OnyX-Style: ein Klick startet meisterSiri-Profile. Dry-Run oben rechts schützt vor echten Änderungen.",
                    systemImage: "wrench.and.screwdriver.fill"
                )

                SectionBox(title: "Profile") {
                    VStack(spacing: 10) {
                        ForEach(MaintenanceProfile.allCases) { profile in
                            ActionCard(
                                title: profile.title,
                                detail: profile.detail + (app.dryRunDefault ? " · Dry-Run" : ""),
                                systemImage: profile == .quick ? "hare.fill" : (profile == .deep ? "tortoise.fill" : "gauge.with.dots.needle.33percent"),
                                accent: profile == .deep ? .orange : .accentColor
                            ) {
                                app.runMaintenance(profile: profile)
                            }
                            .disabled(app.runner.isRunning)
                        }
                    }
                }

                SectionBox(title: "Schnell-Checks") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ActionCard(title: "Doctor", detail: "Read-only System-Checklist", systemImage: "stethoscope") {
                            app.runCommand(["doctor"])
                        }
                        ActionCard(title: "Today", detail: "Morning Briefing + AI-Fokus", systemImage: "sun.max.fill") {
                            app.runCommand(["today"])
                        }
                        ActionCard(title: "Score", detail: "Wartungs-Score 0–100", systemImage: "chart.bar.fill") {
                            app.runCommand(["score"])
                        }
                        ActionCard(title: "Health", detail: "Self-Healing Dashboard", systemImage: "heart.text.square.fill") {
                            app.runCommand(["-H"])
                        }
                        ActionCard(title: "AI + Autofix", detail: "Echte Fixes, dann Rest-Diagnose", systemImage: "brain.head.profile", accent: .green) {
                            app.runCommand(["ai"])
                        }
                        ActionCard(title: "Autofix only", detail: "Bottles, Orphans, Git-Push, FW, Inbox", systemImage: "wand.and.stars") {
                            app.runCommand(["autofix"])
                        }
                        ActionCard(title: "Selftest", detail: "CLI Smoke-Tests", systemImage: "checkmark.seal.fill") {
                            app.runCommand(["selftest"])
                        }
                    }
                    .disabled(app.runner.isRunning)
                }

                statusStrip
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Label(app.status.score, systemImage: "gauge")
            Label(app.status.disk, systemImage: "internaldrive")
            Spacer()
            Text("Zuletzt: \(app.status.lastRefresh.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .font(.subheadline)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
