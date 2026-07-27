import Foundation
import Combine

/// Locates and runs `meisterSiri` / `meister` CLI, streaming stdout/stderr.
@MainActor
final class CLIRunner: ObservableObject {
    @Published var isRunning = false
    @Published var lastExitCode: Int32?
    @Published var liveOutput: String = ""

    private var process: Process?
    private let maxLogChars = 200_000

    /// Preferred CLI binary search order.
    static func resolveCLI() -> String? {
        let candidates = [
            "/opt/homebrew/bin/meisterSiri",
            "/usr/local/bin/meisterSiri",
            NSHomeDirectory() + "/Developer/homebrew-meister/meisterSiri.sh",
            "/opt/homebrew/bin/meister",
            "/usr/local/bin/meister",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // PATH lookup
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["meisterSiri"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty, FileManager.default.isExecutableFile(atPath: s) {
            return s
        }
        return nil
    }

    var cliPath: String? { Self.resolveCLI() }

    func run(arguments: [String], clearLog: Bool = false) {
        guard let cli = cliPath else {
            append("Fehler: meisterSiri nicht gefunden.\nInstalliere: brew install maf4711/meister/meister\n")
            return
        }
        guard !isRunning else {
            append("Bereits ein Lauf aktiv — bitte warten oder abbrechen.\n")
            return
        }

        if clearLog { liveOutput = "" }
        append("┌─ \(cli) \(arguments.joined(separator: " "))\n")
        isRunning = true
        lastExitCode = nil

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = arguments
        proc.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "dumb",
            "NO_COLOR": "1",
            "CLICOLOR": "0",
        ]) { _, new in new }

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        let handleOut: (FileHandle) -> Void = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.append(Self.stripANSI(text)) }
        }

        out.fileHandleForReading.readabilityHandler = handleOut
        err.fileHandleForReading.readabilityHandler = handleOut

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                self?.isRunning = false
                self?.lastExitCode = p.terminationStatus
                self?.append("└─ exit \(p.terminationStatus)\n")
                self?.process = nil
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            isRunning = false
            append("Start fehlgeschlagen: \(error.localizedDescription)\n")
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        isRunning = false
        append("\n[abgebrochen]\n")
    }

    func runSync(arguments: [String], timeout: TimeInterval = 30) -> (code: Int32, output: String) {
        guard let cli = cliPath else {
            return (127, "meisterSiri nicht gefunden")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "dumb", "NO_COLOR": "1",
        ]) { _, n in n }
        do {
            try proc.run()
        } catch {
            return (1, error.localizedDescription)
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            proc.waitUntilExit()
            group.leave()
        }
        _ = group.wait(timeout: .now() + timeout)
        if proc.isRunning {
            proc.terminate()
            return (124, "timeout")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = Self.stripANSI(String(data: data, encoding: .utf8) ?? "")
        return (proc.terminationStatus, text)
    }

    private func append(_ s: String) {
        liveOutput += s
        if liveOutput.count > maxLogChars {
            liveOutput = String(liveOutput.suffix(maxLogChars / 2))
        }
    }

    private static func stripANSI(_ s: String) -> String {
        // crude CSI strip
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{001B}", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "[" {
                i = s.index(after: i)
                while i < s.endIndex, s[i].isLetter == false { i = s.index(after: i) }
                if i < s.endIndex { i = s.index(after: i) }
            } else {
                out.append(s[i])
                i = s.index(after: i)
            }
        }
        return out
    }
}
