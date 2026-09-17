import Foundation
import Combine

/// Locates the CLI and consumes ordered output from a background process group.
@MainActor
final class CLIRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isCancelling = false
    @Published private(set) var lastExitCode: Int32?
    @Published var liveOutput = ""
    @Published private(set) var supportsAIPreview = false
    @Published private(set) var supportsProfilePreview = false
    @Published private(set) var executionReadiness: ExecutionReadiness = .checking
    enum ExecutionReadiness: Sendable { case checking, ready, requiresUpdate, unavailable }
    var isExecutionReady: Bool { executionReadiness == .ready }
    var executionMessage: String {
        switch executionReadiness {
        case .checking: return "CLI wird geprüft. Bitte kurz warten."
        case .ready: return "CLI bereit"
        case .requiresUpdate: return "Die installierte CLI muss für die sichere App-Ausführung aktualisiert werden. Bitte MeisterAI aktualisieren; es wurde nichts gestartet."
        case .unavailable: return "MeisterAI nicht gefunden. Installiere: brew install maf4711/meister/meister"
        }
    }
    var onCompletion: ((ExecutionResult) -> Void)?

    private var execution: ProcessExecution?
    private var executionTask: Task<Void, Never>?
    private let selectedExecutable: String?
    private var verifiedIdentity: SourceIdentity?
    private var capabilityTask: Task<Void, Never>?
    private let maxLogChars = 200_000

    init(executable: String? = nil) {
        selectedExecutable = (executable ?? Self.resolveCLI()).map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        refreshCapabilities()
    }

    func waitForCapabilities() async { await capabilityTask?.value }

    private func refreshCapabilities() {
        executionReadiness = .checking
        supportsAIPreview = false
        supportsProfilePreview = false
        verifiedIdentity = nil
        let path = selectedExecutable
        capabilityTask = Task { [weak self] in
            let capabilities = await Task.detached { Self.readCapabilities(path: path) }.value
            guard let self else { return }
            self.verifiedIdentity = capabilities.identity
            self.executionReadiness = capabilities.readiness
            self.supportsAIPreview = capabilities.previews.contains("ai") && capabilities.readiness == .ready
            self.supportsProfilePreview = capabilities.previews.contains("profiles") && capabilities.readiness == .ready
        }
    }

    private func validateExecutable() -> String? {
        guard executionReadiness == .ready, let path = selectedExecutable else { return nil }
        guard Self.identity(path: path) == verifiedIdentity else {
            refreshCapabilities()
            return nil
        }
        return path
    }

    private struct SourceIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
        let size: UInt64
        let modified: Date
    }
    private struct Capabilities: Sendable {
        let readiness: ExecutionReadiness
        let identity: SourceIdentity?
        let previews: Set<String>
    }
    private nonisolated static func identity(path: String) -> SourceIdentity? {
        guard FileManager.default.isExecutableFile(atPath: path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return SourceIdentity(device: device.uint64Value, inode: inode.uint64Value, size: size.uint64Value, modified: modified)
    }
    private nonisolated static func readCapabilities(path: String?) -> Capabilities {
        guard let path, let before = identity(path: path), let file = FileHandle(forReadingAtPath: path) else {
            return Capabilities(readiness: .unavailable, identity: nil, previews: [])
        }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 65_536), let script = String(data: data, encoding: .utf8),
              before == identity(path: path) else {
            return Capabilities(readiness: .requiresUpdate, identity: nil, previews: [])
        }
        let lines = script.split(separator: "\n")
        guard lines.contains("# GUI-Execution-Contract: 1") else {
            return Capabilities(readiness: .requiresUpdate, identity: before, previews: [])
        }
        let prefix = "# GUI-Preview-Capabilities:"
        let previewLine = lines.first { $0.hasPrefix(prefix) }
        let previews = Set((previewLine?.dropFirst(prefix.count) ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
        return Capabilities(readiness: .ready, identity: before, previews: previews)
    }

    nonisolated static func resolveCLI() -> String? {
        let candidates = [
            "/opt/homebrew/bin/MeisterAI", "/usr/local/bin/MeisterAI",
            NSHomeDirectory() + "/Developer/homebrew-meister/MeisterAI.sh",
            "/opt/homebrew/bin/meister", "/usr/local/bin/meister",
        ]
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").filter { $0.hasPrefix("/") }.map { String($0) + "/MeisterAI" }
        return (candidates + pathCandidates).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var cliPath: String? { selectedExecutable }

    @discardableResult
    func run(command: CommandPolicy.PreparedCommand, clearLog: Bool = false,
             timeout: TimeInterval = 30 * 60) -> Bool {
        guard !isRunning else {
            append("Bereits ein Lauf aktiv — bitte warten, bis er vollständig beendet ist.\n")
            return false
        }
        if clearLog { liveOutput = "" }
        guard let cli = validateExecutable() else {
            lastExitCode = 126
            append(executionMessage + "\n")
            return false
        }
        // Re-evaluate against this exact executable; a prepared command from another runner grants no capability.
        guard case .allowed = CommandPolicy.prepare(arguments: command.arguments, dryRun: command.isPreview,
                                                     supportsAIPreview: supportsAIPreview,
                                                     supportsProfilePreview: supportsProfilePreview) else {
            append("Dry-Run: Diese CLI unterstützt die angeforderte Vorschau nicht. Es wurde nichts gestartet.\n")
            return false
        }
        append("\(command.isPreview ? "[Dry-Run freigegeben]" : "[Aktion freigegeben]")\n")
        append("┌─ \(cli) \(command.arguments.joined(separator: " "))\n")
        isRunning = true
        isCancelling = false
        lastExitCode = nil
        let operation = ProcessExecution()
        execution = operation
        executionTask = Task { [weak self] in
            let stream = AsyncStream<RunEvent> { continuation in
                Task {
                    let result = await operation.run(executable: cli, arguments: command.arguments, timeout: timeout) {
                        continuation.yield(.output($0))
                    }
                    continuation.yield(.finished(result))
                    continuation.finish()
                }
            }
            for await event in stream {
                guard let self else { operation.cancel(); return }
                switch event {
                case .output(let text): self.append(Self.stripANSI(text))
                case .finished(let result):
                    self.lastExitCode = result.code
                    if result.timedOut { self.append("\n[Zeitlimit erreicht; CLI-Prozess beendet]\n") }
                    if result.wasCancelled { self.append("\n[Abbruch bestätigt; CLI-Prozess beendet]\n") }
                    if result.code == 127 { self.append(result.output + "\n") }
                    self.append("└─ exit \(result.code)\n")
                    self.execution = nil
                    self.executionTask = nil
                    self.isCancelling = false
                    self.isRunning = false
                    self.onCompletion?(result)
                }
            }
        }
        return true
    }

    func cancel() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        append("\n[Abbruch angefordert — warte auf Prozessende…]\n")
        execution?.cancel()
    }

    func recordBlocked(_ message: String, clearLog: Bool = true) {
        if clearLog && !isRunning { liveOutput = "" }
        append(message + "\n")
    }

    func probe(arguments: [String], timeout: TimeInterval = 5) async -> ExecutionResult {
        guard CommandPolicy.permitsProbe(arguments: arguments) else {
            return ExecutionResult(code: 126, output: "Statusprüfung gesperrt: Diese Aktion kann Änderungen ausführen.", wasCancelled: false, timedOut: false)
        }
        await waitForCapabilities()
        guard let cli = validateExecutable() else {
            return ExecutionResult(code: 126, output: executionMessage, wasCancelled: false, timedOut: false)
        }
        return await ProcessExecution().run(executable: cli, arguments: arguments, timeout: timeout)
    }

    private func append(_ text: String) {
        liveOutput += text
        if liveOutput.count > maxLogChars { liveOutput = String(liveOutput.suffix(maxLogChars)) }
    }

    nonisolated private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\\u001B\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    private enum RunEvent: Sendable {
        case output(String)
        case finished(ExecutionResult)
    }
}
