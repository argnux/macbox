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

    func start() {
        guard !isRunning, !target.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pingPath)
        process.arguments = isInfinite ? [target] : ["-c", "\(packetCount)", target]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        logs = "> Pinging \(target)...\n"
        isRunning = true
        self.process = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.logs += text
            }
        }

        process.terminationHandler = { [weak self, weak pipe] _ in
            pipe?.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                self.isRunning = false
                if !self.logs.hasSuffix("> Stopped by user.\n") {
                    self.logs += "\n> Done."
                }
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            isRunning = false
            logs += "\nError: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let process else { return }
        process.terminate()
        logs += "\n> Stopped by user.\n"
    }
}
