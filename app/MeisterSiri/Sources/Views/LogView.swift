import SwiftUI

struct LogView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageHeader(
                    title: "Protokoll",
                    subtitle: app.runner.isRunning
                        ? "Lauf aktiv — Ausgabe live"
                        : "Letzte meisterSiri-Ausgabe",
                    systemImage: "doc.text.fill"
                )
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            HStack {
                if let code = app.runner.lastExitCode {
                    Text("Exit \(code)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(code == 0 ? Color.green.opacity(0.2) : Color.orange.opacity(0.25)))
                }
                Spacer()
                Button("Leeren") { app.runner.liveOutput = "" }
                    .disabled(app.runner.isRunning)
                Button("Kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(app.runner.liveOutput, forType: .string)
                }
                if app.runner.isRunning {
                    Button("Stop", role: .destructive) { app.runner.cancel() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(app.runner.liveOutput.isEmpty ? "Noch keine Ausgabe.\nStarte einen Lauf unter Wartung oder Reinigung." : app.runner.liveOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .onChange(of: app.runner.liveOutput) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
