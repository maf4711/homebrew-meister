import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $app.selection) { item in
                NavigationLink(value: item) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.rawValue)
                                .font(.body.weight(.medium))
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.systemImage)
                            .foregroundStyle(.tint)
                    }
                }
                .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("MeisterSiri")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(app.runner.isRunning ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        Text(app.runner.isRunning ? "Läuft…" : "Bereit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if app.runner.isRunning {
                            Button("Stop") { app.runner.cancel() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                    Text(app.status.cliVersion)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(12)
                .background(.bar)
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("Dry-Run", isOn: $app.dryRunDefault)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Keine Änderungen schreiben (-n)")
                Button {
                    app.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Status aktualisieren")
            }
        }
        .onAppear { app.refreshAll() }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.selection {
        case .maintenance: MaintenanceView()
        case .cleaning: CleaningView()
        case .parameters: ParametersView()
        case .security: SecurityView()
        case .automation: AutomationView()
        case .log: LogView()
        case .info: InfoView()
        }
    }
}
