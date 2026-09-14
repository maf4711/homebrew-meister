import Foundation
import Combine

struct StatusRow: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let ok: Bool?
}

@MainActor
final class SystemStatus: ObservableObject {
    typealias Probe = @Sendable (String, [String]) async -> ExecutionResult
    @Published var rows: [StatusRow] = []
    @Published var score = "—"
    @Published var cliVersion = "—"
    @Published var cliPath = "—"
    @Published var disk = "—"
    @Published var lastRefresh = Date()
    @Published private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
    private let probe: Probe
    private let historyPath: String

    init(historyPath: String = NSHomeDirectory() + "/.meister/history.log",
         probe: @escaping Probe = { executable, args in
             await ProcessExecution().run(executable: executable, arguments: args, timeout: 5)
         }) {
        self.historyPath = historyPath
        self.probe = probe
    }

    func refresh(using runner: CLIRunner) {
        guard refreshTask == nil else { return }
        isRefreshing = true
        let path = runner.cliPath
        let probe = self.probe, historyPath = self.historyPath
        refreshTask = Task { [weak self] in
            async let df = probe("/bin/df", ["-h", "/"])
            async let sip = probe("/usr/bin/csrutil", ["status"])
            async let fv = probe("/usr/bin/fdesetup", ["status"])
            // -N checks the ticket without extending its lifetime.
            async let sudo = probe("/usr/bin/sudo", ["-n", "-N", "-v"])
            let files = Task.detached { Self.readStatusFiles(cliPath: path, historyPath: historyPath) }
            let values = await (df, sip, fv, sudo, files.value)
            guard let self else { return }
            self.cliPath = path ?? "nicht gefunden"
            self.cliVersion = values.4.version
            self.score = values.4.score
            self.disk = Self.diskDescription(values.0)
            let sipOn = values.1.code == 0 ? values.1.output.lowercased().contains("enabled") : nil
            let fvOn = values.2.code == 0 ? values.2.output.lowercased().contains("filevault is on") : nil
            self.rows = [
                StatusRow(label: "CLI", value: self.cliVersion, ok: path != nil),
                StatusRow(label: "Pfad", value: self.cliPath, ok: path != nil),
                StatusRow(label: "Score", value: self.score, ok: nil),
                StatusRow(label: "Disk", value: self.disk, ok: nil),
                StatusRow(label: "SIP", value: Self.statusText(values.1), ok: sipOn),
                StatusRow(label: "FileVault", value: Self.statusText(values.2), ok: fvOn),
                StatusRow(label: "Sudo-Ticket", value: values.3.code == 0 ? "live" : "nicht verfügbar", ok: values.3.code == 0),
                StatusRow(label: "Sudo share", value: values.4.sudoShare ? "zz-meister (2h)" : "default tty", ok: values.4.sudoShare),
            ]
            self.lastRefresh = Date()
            self.isRefreshing = false
            self.refreshTask = nil
        }
    }

    private nonisolated static func statusText(_ result: ExecutionResult) -> String {
        if result.timedOut { return "Zeitlimit erreicht" }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "Nicht verfügbar (Exit \(result.code))" : output
    }

    private nonisolated static func diskDescription(_ result: ExecutionResult) -> String {
        guard result.code == 0 else { return "Nicht verfügbar" }
        let lines = result.output.split(separator: "\n")
        guard lines.count >= 2 else { return "Nicht verfügbar" }
        let parts = lines[1].split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 5 else { return "Nicht verfügbar" }
        return "\(parts[4]) belegt · \(parts[3]) frei"
    }

    private nonisolated static func readStatusFiles(cliPath: String?, historyPath: String) -> (version: String, score: String, sudoShare: Bool) {
        var score = "—"
        if let file = FileHandle(forReadingAtPath: historyPath) {
            defer { try? file.close() }
            if let size = try? file.seekToEnd() {
                try? file.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
                if let data = try? file.readToEnd(), let history = String(data: data, encoding: .utf8),
                   let last = history.split(separator: "\n").last, let range = last.range(of: "SCORE:") {
                    let digits = last[range.upperBound...].prefix(while: { $0.isNumber })
                    if !digits.isEmpty { score = String(digits) + "/100" }
                }
            }
        }
        // Read the script constant: launching older CLIs for --version can run EXIT cleanup.
        var version = cliPath == nil ? "nicht gefunden" : "Version nicht verfügbar"
        if let cliPath, let file = FileHandle(forReadingAtPath: cliPath) {
            defer { try? file.close() }
            if let data = try? file.read(upToCount: 65_536), let script = String(data: data, encoding: .utf8),
               let line = script.split(separator: "\n").first(where: { $0.hasPrefix("# Version:") }) {
                let number = line.dropFirst(10).trimmingCharacters(in: .whitespaces)
                version = "meisterSiri \(number)"
            }
        }
        return (version, score, FileManager.default.fileExists(atPath: "/etc/sudoers.d/zz-meister"))
    }
}
