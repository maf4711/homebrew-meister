import Foundation
import Combine

struct StatusRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let ok: Bool?
}

@MainActor
final class SystemStatus: ObservableObject {
    @Published var rows: [StatusRow] = []
    @Published var score: String = "—"
    @Published var cliVersion: String = "—"
    @Published var cliPath: String = "—"
    @Published var disk: String = "—"
    @Published var lastRefresh = Date()

    func refresh(using runner: CLIRunner) {
        cliPath = runner.cliPath ?? "nicht gefunden"
        if let cli = runner.cliPath {
            let v = runner.runSync(arguments: ["--version"], timeout: 5)
            cliVersion = v.output.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = cli
        }

        // Score from history
        let hist = (NSHomeDirectory() as NSString).appendingPathComponent(".meister/history.log")
        if let data = try? String(contentsOfFile: hist, encoding: .utf8),
           let last = data.split(separator: "\n").last {
            if let range = last.range(of: "SCORE:") {
                let rest = last[range.upperBound...]
                score = String(rest.prefix(while: { $0.isNumber })) + "/100"
            }
        }

        // Disk
        let df = Process()
        df.executableURL = URL(fileURLWithPath: "/bin/df")
        df.arguments = ["-h", "/"]
        let pipe = Pipe()
        df.standardOutput = pipe
        try? df.run()
        df.waitUntilExit()
        if let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            let lines = out.split(separator: "\n")
            if lines.count >= 2 {
                let parts = lines[1].split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 5 {
                    disk = "\(parts[4]) used · \(parts[3]) free"
                }
            }
        }

        var r: [StatusRow] = []
        r.append(StatusRow(label: "CLI", value: cliVersion, ok: cliVersion.contains("meisterSiri") || cliVersion.contains("meister")))
        r.append(StatusRow(label: "Pfad", value: cliPath, ok: cliPath != "nicht gefunden"))
        r.append(StatusRow(label: "Score", value: score, ok: nil))
        r.append(StatusRow(label: "Disk", value: disk, ok: nil))

        // SIP
        let sip = shell("/usr/bin/csrutil", ["status"])
        let sipOn = sip.lowercased().contains("enabled")
        r.append(StatusRow(label: "SIP", value: sipOn ? "enabled" : sip.trimmingCharacters(in: .whitespacesAndNewlines), ok: sipOn))

        // FileVault
        let fv = shell("/usr/bin/fdesetup", ["status"])
        let fvOn = fv.lowercased().contains("on")
        r.append(StatusRow(label: "FileVault", value: fvOn ? "On" : "Off", ok: fvOn))

        // Sudo ticket
        let sudoOk = shell("/usr/bin/sudo", ["-n", "true"]).isEmpty && shellExit("/usr/bin/sudo", ["-n", "true"]) == 0
        r.append(StatusRow(label: "Sudo-Ticket", value: sudoOk ? "live" : "abgelaufen", ok: sudoOk))

        // zz-meister
        let share = FileManager.default.fileExists(atPath: "/etc/sudoers.d/zz-meister")
        r.append(StatusRow(label: "Sudo share", value: share ? "zz-meister (2h)" : "default tty", ok: share))

        rows = r
        lastRefresh = Date()
    }

    private func shell(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func shellExit(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
