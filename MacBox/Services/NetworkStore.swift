import Foundation
import SystemConfiguration

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var interfaces: [HardwareInterface] = []
    @Published private(set) var isRefreshing = false

    private let service = NetworkService()
    private var changeMonitor: NetworkChangeMonitor?
    private var fallbackTask: Task<Void, Never>?
    private var scheduledRefreshTask: Task<Void, Never>?
    private var isRefreshInProgress = false
    private var needsDeferredRefresh = false

    deinit {
        changeMonitor?.stop()
        fallbackTask?.cancel()
        scheduledRefreshTask?.cancel()
    }

    func startLiveUpdates() {
        guard changeMonitor == nil else { return }

        changeMonitor = NetworkChangeMonitor { [weak self] in
            Task { @MainActor in
                self?.scheduleBackgroundRefresh()
            }
        }
        changeMonitor?.start()

        fallbackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.refresh(showActivity: false)
            }
        }

        Task { [weak self] in
            await self?.refresh()
        }
    }

    func refresh(showActivity: Bool = true) async {
        if isRefreshInProgress {
            needsDeferredRefresh = true
            return
        }

        isRefreshInProgress = true
        if showActivity {
            isRefreshing = true
        }

        let nextInterfaces = await service.checkInterfaces()
        if interfaces != nextInterfaces {
            interfaces = nextInterfaces
        }

        if showActivity {
            isRefreshing = false
        }
        isRefreshInProgress = false

        if needsDeferredRefresh {
            needsDeferredRefresh = false
            await refresh(showActivity: false)
        }
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

    private func scheduleBackgroundRefresh() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await self?.refresh(showActivity: false)
        }
    }
}

private final class NetworkChangeMonitor {
    private let queue = DispatchQueue(label: "MacBox.NetworkChangeMonitor")
    private let onChange: @Sendable () -> Void
    private var store: SCDynamicStore?

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard store == nil else { return }

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let dynamicStore = SCDynamicStoreCreate(
            nil,
            "MacBox.NetworkChangeMonitor" as CFString,
            { _, _, info in
                guard let info else { return }
                let monitor = Unmanaged<NetworkChangeMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.onChange()
            },
            &context
        ) else {
            return
        }

        let keys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6",
            "Setup:/Network/Global/IPv4",
            "Setup:/Network/Global/IPv6"
        ] as CFArray
        let patterns = [
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Interface/.*/IPv6",
            "State:/Network/Interface/.*/Link",
            "State:/Network/Service/.*/IPv4",
            "State:/Network/Service/.*/IPv6",
            "Setup:/Network/Service/.*"
        ] as CFArray

        guard SCDynamicStoreSetNotificationKeys(dynamicStore, keys, patterns),
              SCDynamicStoreSetDispatchQueue(dynamicStore, queue) else {
            return
        }

        store = dynamicStore
    }

    func stop() {
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        store = nil
    }
}
