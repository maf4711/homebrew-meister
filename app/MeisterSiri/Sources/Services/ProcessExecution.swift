import Foundation
import Darwin

struct ExecutionResult: Sendable {
    let code: Int32
    let output: String
    let wasCancelled: Bool
    let timedOut: Bool
}

/// One process group per invocation. Blocking wait/read work never runs on the main actor.
final class ProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var finished = false
    private var cancelled = false
    private var expired = false
    private let maxOutputBytes = 2_000_000

    func run(executable: String, arguments: [String], timeout: TimeInterval = 30,
             onOutput: @escaping @Sendable (String) -> Void = { _ in }) async -> ExecutionResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: self.execute(executable: executable, arguments: arguments,
                                                               timeout: timeout, onOutput: onOutput))
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() { stop(timedOut: false) }

    private func stop(timedOut: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if timedOut { expired = true } else { cancelled = true }
        let target = pid
        if target > 0 { kill(-target, SIGTERM) }
        lock.unlock()
        guard target > 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
            lock.lock()
            defer { lock.unlock() }
            if !finished, pid == target { kill(-target, SIGKILL) }
        }
    }

    private func execute(executable: String, arguments: [String], timeout: TimeInterval,
                         onOutput: @escaping @Sendable (String) -> Void) -> ExecutionResult {
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { return failure("Ausgabe-Pipe konnte nicht geöffnet werden.") }
        let readFD = descriptors[0], writeFD = descriptors[1]
        _ = fcntl(readFD, F_SETFD, FD_CLOEXEC)
        _ = fcntl(writeFD, F_SETFD, FD_CLOEXEC)
        _ = fcntl(readFD, F_SETFL, O_NONBLOCK)
        defer { close(readFD) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, writeFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, readFD)
        posix_spawn_file_actions_addclose(&actions, writeFD)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        var environment = ProcessInfo.processInfo.environment
        let trustedPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let inheritedPaths = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var uniquePaths = Set<String>()
        environment["PATH"] = (trustedPaths + inheritedPaths).filter { uniquePaths.insert($0).inserted }.joined(separator: ":")
        environment.merge(["TERM": "dumb", "NO_COLOR": "1", "CLICOLOR": "0",
                           "HOMEBREW_NO_AUTO_UPDATE": "1", "MEISTER_GUI_PROCESS_GROUP": "1"]) { _, new in new }
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var child: pid_t = 0
        lock.lock()
        if cancelled {
            finished = true
            lock.unlock()
            close(writeFD)
            return ExecutionResult(code: 130, output: "", wasCancelled: true, timedOut: false)
        }
        let error = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&child, executable, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        if error == 0 { pid = child }
        lock.unlock()
        close(writeFD)
        guard error == 0 else { return failure("Start fehlgeschlagen: \(String(cString: strerror(error)))") }

        let deadline = DispatchWorkItem { [weak self] in self?.stop(timedOut: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0.01, timeout), execute: deadline)
        defer { deadline.cancel() }
        let collector = OutputCollector(limit: maxOutputBytes)
        let draining = DispatchGroup()
        draining.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { draining.leave() }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            var pending = Data()
            while !collector.shouldStop {
                var descriptor = pollfd(fd: readFD, events: Int16(POLLIN | POLLHUP), revents: 0)
                let readiness = poll(&descriptor, 1, 50)
                if readiness == 0 { continue }
                if readiness < 0, errno == EINTR { continue }
                guard readiness > 0 else { break }
                let count = read(readFD, &buffer, buffer.count)
                if count < 0, errno == EINTR || errno == EAGAIN { continue }
                guard count > 0 else { break }
                let data = Data(buffer.prefix(count))
                collector.append(data)
                pending.append(data)
                // Preserve UTF-8 characters split between reads.
                if let text = String(data: pending, encoding: .utf8) {
                    onOutput(text)
                    pending.removeAll(keepingCapacity: true)
                } else if pending.count > 65_536 {
                    onOutput(String(decoding: pending, as: UTF8.self))
                    pending.removeAll(keepingCapacity: true)
                }
            }
            if !pending.isEmpty { onOutput(String(decoding: pending, as: UTF8.self)) }
        }
        // Observe exit without reaping, so this PID cannot be reused while cleanup signals run.
        var info = siginfo_t()
        while waitid(P_PID, id_t(child), &info, WEXITED | WNOWAIT) < 0 {
            if errno != EINTR { break }
        }
        kill(-child, SIGTERM)
        _ = draining.wait(timeout: .now() + 0.5)
        lock.lock()
        kill(-child, SIGKILL)
        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 { if errno != EINTR { break } }
        pid = 0
        lock.unlock()
        // A daemon that escaped the group may retain a descriptor. Never wait forever for EOF.
        if draining.wait(timeout: .now() + 0.5) == .timedOut {
            collector.stopReading()
            draining.wait()
        }
        lock.lock()
        finished = true
        pid = 0
        let didCancel = cancelled, didExpire = expired
        lock.unlock()
        let code: Int32 = didExpire ? 124 : (didCancel ? 130 : ((status & 0x7f) == 0 ? status >> 8 : 128 + (status & 0x7f)))
        return ExecutionResult(code: code, output: collector.text, wasCancelled: didCancel, timedOut: didExpire)
    }

    private func failure(_ message: String) -> ExecutionResult {
        lock.lock(); finished = true; lock.unlock()
        return ExecutionResult(code: 127, output: message, wasCancelled: false, timedOut: false)
    }
}

private final class OutputCollector: @unchecked Sendable {
    private var data = Data()
    private let stopLock = NSLock()
    private var stopped = false
    var shouldStop: Bool { stopLock.lock(); defer { stopLock.unlock() }; return stopped }
    func stopReading() { stopLock.lock(); stopped = true; stopLock.unlock() }
    let limit: Int
    init(limit: Int) { self.limit = limit }
    func append(_ chunk: Data) {
        data.append(chunk)
        if data.count > limit { data.removeFirst(data.count - limit) }
    }
    var text: String { String(decoding: data, as: UTF8.self) }
}
