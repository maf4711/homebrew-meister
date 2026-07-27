import SwiftUI

struct ParametersView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Parameter",
                    subtitle: "Versteckte macOS-Einstellungen im OnyX-Stil. Änderungen laufen über meisterSiri tweaks.",
                    systemImage: "slider.horizontal.3"
                )

                SectionBox(title: "Finder & UI") {
                    VStack(spacing: 0) {
                        ForEach(app.tweaks.items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.body.weight(.medium))
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { item.isOn },
                                    set: { newVal in
                                        app.tweaks.set(id: item.id, on: newVal, viaCLI: app.runner)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                            if item.id != app.tweaks.items.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }

                if !app.tweaks.lastMessage.isEmpty {
                    Text(app.tweaks.lastMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Status neu laden") {
                    app.tweaks.refresh()
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { app.tweaks.refresh() }
    }
}
