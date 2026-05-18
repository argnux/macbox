import Foundation

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var interfaces: [HardwareInterface] = []
    @Published private(set) var isRefreshing = false

    private let service = NetworkService()
    private var liveTask: Task<Void, Never>?

    deinit {
        liveTask?.cancel()
    }

    func startLiveUpdates() {
        guard liveTask == nil else { return }

        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        let nextInterfaces = await service.checkInterfaces()
        interfaces = nextInterfaces
        isRefreshing = false
    }

    func createInterface(hardwarePortName: String, newServiceName: String) async -> String? {
        do {
            try await service.createInterface(hardwarePortName: hardwarePortName, newServiceName: newServiceName)
            await refresh()
            return nil
        } catch {
            return await service.parseNetworkError(error)
        }
    }

    func deleteInterface(serviceName: String) async -> String? {
        do {
            try await service.deleteInterface(serviceName: serviceName)
            await refresh()
            return nil
        } catch {
            return await service.parseNetworkError(error)
        }
    }

    func updateInterface(_ payload: InterfaceUpdatePayload) async -> String? {
        do {
            try await service.updateInterface(payload)
            await refresh()
            return nil
        } catch {
            return await service.parseNetworkError(error)
        }
    }
}
