import Foundation

@MainActor
final class PingStore: ObservableObject {
    @Published var target = ""
    @Published var packetCount = 4
    @Published var isInfinite = false
    @Published private(set) var logs = ""
    @Published private(set) var isRunning = false

    private var process: Process?
    private let pingPath = "/sbin/ping"
    private let maxLogCharacters = 80_000
    private var pendingLog = ""
    private var logFlushTask: Task<Void, Never>?
    private var stopRequested = false

    func start() {
        guard !isRunning, !target.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pingPath)
        process.arguments = isInfinite ? [target] : ["-c", "\(packetCount)", target]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        logFlushTask?.cancel()
        pendingLog = ""
        stopRequested = false
        logs = "> Pinging \(target)...\n"
        isRunning = true
        self.process = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendLog(text)
            }
        }

        process.terminationHandler = { [weak self, weak pipe] _ in
            pipe?.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                self.isRunning = false
                self.flushLog()
                if !self.stopRequested {
                    self.appendLog("\n> Done.", immediate: true)
                }
                self.stopRequested = false
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            isRunning = false
            appendLog("\nError: \(error.localizedDescription)", immediate: true)
        }
    }

    func stop() {
        guard let process else { return }
        stopRequested = true
        process.terminate()
        appendLog("\n> Stopped by user.\n", immediate: true)
    }

    func clearLogs() {
        logFlushTask?.cancel()
        logFlushTask = nil
        pendingLog = ""
        logs = ""
    }

    private func appendLog(_ text: String, immediate: Bool = false) {
        pendingLog += text

        if immediate {
            flushLog()
            return
        }

        guard logFlushTask == nil else { return }

        logFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self?.flushLog()
        }
    }

    private func flushLog() {
        logFlushTask?.cancel()
        logFlushTask = nil

        guard !pendingLog.isEmpty else { return }

        logs += pendingLog
        pendingLog = ""

        if logs.count > maxLogCharacters {
            logs = String(logs.suffix(maxLogCharacters))
        }
    }
}
