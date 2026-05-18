import Darwin
import Foundation
import Security
import SystemConfiguration

actor NetworkService {
    func createInterface(hardwarePortName: String, newServiceName: String) async throws {
        try updatePreferences { preferences in
            guard let set = SCNetworkSetCopyCurrent(preferences) else {
                throw NetworkConfigurationError.systemConfiguration("No active network location was found.")
            }

            guard let interface = findInterface(named: hardwarePortName) else {
                throw NetworkConfigurationError.notFound("Hardware port \"\(hardwarePortName)\" was not found.")
            }

            guard let service = SCNetworkServiceCreate(preferences, interface) else {
                throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not create network service."))
            }

            guard SCNetworkServiceEstablishDefaultConfiguration(service) else {
                throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not create default service configuration."))
            }

            guard SCNetworkServiceSetName(service, newServiceName as CFString) else {
                throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not name network service."))
            }

            guard SCNetworkSetAddService(set, service) else {
                throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not add service to current network location."))
            }
        }
    }

    func deleteInterface(serviceName: String) async throws {
        try updatePreferences { preferences in
            guard let service = findService(named: serviceName, in: preferences) else {
                throw NetworkConfigurationError.notFound("Service \"\(serviceName)\" was not found.")
            }

            guard SCNetworkServiceRemove(service) else {
                throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not remove network service."))
            }
        }
    }

    func updateInterface(_ data: InterfaceUpdatePayload) async throws {
        try updatePreferences { preferences in
            guard let service = findService(named: data.oldName, in: preferences) else {
                throw NetworkConfigurationError.notFound("Service \"\(data.oldName)\" was not found.")
            }

            if !data.newName.isEmpty, data.newName != data.oldName {
                guard SCNetworkServiceSetName(service, data.newName as CFString) else {
                    throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not rename network service."))
                }
            }

            guard let protocolRef = ipv4Protocol(for: service) else {
                throw NetworkConfigurationError.systemConfiguration("IPv4 protocol is not available for this service.")
            }

            let configuration: [CFString: Any]
            switch data.method {
            case .dhcp:
                configuration = [
                    kSCPropNetIPv4ConfigMethod: kSCValNetIPv4ConfigMethodDHCP as String
                ]
            case .manual:
                var manualConfiguration: [CFString: Any] = [
                    kSCPropNetIPv4ConfigMethod: kSCValNetIPv4ConfigMethodManual as String,
                    kSCPropNetIPv4Addresses: [data.ip],
                    kSCPropNetIPv4SubnetMasks: [data.mask]
                ]

                if !data.gateway.isEmpty {
                    manualConfiguration[kSCPropNetIPv4Router] = data.gateway
                }

                configuration = manualConfiguration
            case .unknown, .autoOther:
                return
            }

            guard SCNetworkProtocolSetConfiguration(protocolRef, configuration as CFDictionary) else {
                throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not update IPv4 configuration."))
            }
        }
    }

    func checkInterfaces() async -> [HardwareInterface] {
        guard let preferences = SCPreferencesCreate(nil, "MacBox" as CFString, nil) else {
            return []
        }

        let activeDevices = activeInterfaceNames()
        var hardwareByDevice: [String: HardwareInterface] = [:]

        for service in currentLocationServices(preferences: preferences) {
            guard let interface = SCNetworkServiceGetInterface(service),
                  let deviceID = SCNetworkInterfaceGetBSDName(interface) as String?,
                  !deviceID.isEmpty else {
                continue
            }

            let serviceName = SCNetworkServiceGetName(service) as String? ?? deviceID
            let serviceID = SCNetworkServiceGetServiceID(service) as String? ?? serviceName
            let logicInterface = logicInterface(
                serviceName: serviceName,
                serviceID: serviceID,
                deviceID: deviceID,
                service: service
            )

            var hardware = hardwareByDevice[deviceID] ?? HardwareInterface(
                name: hardwareName(for: interface, fallback: deviceID),
                device: deviceID,
                mac: SCNetworkInterfaceGetHardwareAddressString(interface) as String? ?? "",
                isActive: activeDevices.contains(deviceID),
                logicInterfaces: []
            )

            hardware.logicInterfaces.append(logicInterface)
            hardwareByDevice[deviceID] = hardware
        }

        return hardwareByDevice.values.sorted { lhs, rhs in
            if lhs.name == "Wi-Fi", rhs.name != "Wi-Fi" { return true }
            if lhs.name != "Wi-Fi", rhs.name == "Wi-Fi" { return false }
            return lhs.device < rhs.device
        }
    }

    func parseNetworkError(_ error: Error) -> String {
        if let configurationError = error as? NetworkConfigurationError {
            return configurationError.localizedDescription
        }
        return error.localizedDescription
    }

    private func currentLocationServices(preferences: SCPreferences) -> [SCNetworkService] {
        guard let set = SCNetworkSetCopyCurrent(preferences),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else {
            return SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] ?? []
        }

        guard let order = SCNetworkSetGetServiceOrder(set) as? [String], !order.isEmpty else {
            return services
        }

        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return services.sorted { lhs, rhs in
            let lhsID = SCNetworkServiceGetServiceID(lhs) as String? ?? ""
            let rhsID = SCNetworkServiceGetServiceID(rhs) as String? ?? ""
            return (orderIndex[lhsID] ?? Int.max) < (orderIndex[rhsID] ?? Int.max)
        }
    }

    private func logicInterface(
        serviceName: String,
        serviceID: String,
        deviceID: String,
        service: SCNetworkService
    ) -> LogicInterface {
        let protocolConfiguration = ipv4Protocol(for: service)
            .flatMap { SCNetworkProtocolGetConfiguration($0) as? [String: Any] } ?? [:]
        let dynamicConfiguration = dynamicIPv4Configuration(serviceID: serviceID)

        let configMethod = protocolConfiguration[kSCPropNetIPv4ConfigMethod as String] as? String
        let method: IPMethod
        if configMethod == (kSCValNetIPv4ConfigMethodManual as String) {
            method = .manual
        } else if configMethod == (kSCValNetIPv4ConfigMethodDHCP as String) {
            method = .dhcp
        } else if configMethod == nil {
            method = .unknown
        } else {
            method = .autoOther
        }

        return LogicInterface(
            id: serviceName,
            name: serviceName,
            device: deviceID,
            ip: firstString(for: kSCPropNetIPv4Addresses, in: dynamicConfiguration, fallback: protocolConfiguration),
            mask: firstString(for: kSCPropNetIPv4SubnetMasks, in: dynamicConfiguration, fallback: protocolConfiguration),
            gateway: string(for: kSCPropNetIPv4Router, in: dynamicConfiguration, fallback: protocolConfiguration),
            method: method
        )
    }

    private func dynamicIPv4Configuration(serviceID: String) -> [String: Any] {
        let key = "State:/Network/Service/\(serviceID)/IPv4" as CFString
        return SCDynamicStoreCopyValue(nil, key) as? [String: Any] ?? [:]
    }

    private func firstString(for key: CFString, in primary: [String: Any], fallback: [String: Any]) -> String {
        let key = key as String
        if let value = (primary[key] as? [String])?.first, !value.isEmpty {
            return value
        }
        if let value = (fallback[key] as? [String])?.first, !value.isEmpty {
            return value
        }
        return ""
    }

    private func string(for key: CFString, in primary: [String: Any], fallback: [String: Any]) -> String {
        let key = key as String
        if let value = primary[key] as? String, !value.isEmpty {
            return value
        }
        if let value = fallback[key] as? String, !value.isEmpty {
            return value
        }
        return ""
    }

    private func ipv4Protocol(for service: SCNetworkService) -> SCNetworkProtocol? {
        SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeIPv4)
    }

    private func hardwareName(for interface: SCNetworkInterface, fallback: String) -> String {
        if let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?, !displayName.isEmpty {
            return displayName
        }
        return fallback
    }

    private func findInterface(named name: String) -> SCNetworkInterface? {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        return interfaces.first { interface in
            hardwareName(for: interface, fallback: "") == name
                || (SCNetworkInterfaceGetBSDName(interface) as String?) == name
        }
    }

    private func findService(named name: String, in preferences: SCPreferences) -> SCNetworkService? {
        let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] ?? []
        return services.first { service in
            SCNetworkServiceGetName(service) as String? == name
        }
    }

    private func activeInterfaceNames() -> Set<String> {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            return []
        }
        defer { freeifaddrs(firstAddress) }

        var devices = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let pointer = cursor {
            let address = pointer.pointee
            let flags = Int32(address.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 {
                devices.insert(String(cString: address.ifa_name))
            }
            cursor = address.ifa_next
        }

        return devices
    }

    private func updatePreferences(_ changes: (SCPreferences) throws -> Void) throws {
        let authorization = try makeAuthorization()
        defer { AuthorizationFree(authorization, []) }

        guard let preferences = SCPreferencesCreateWithAuthorization(
            nil,
            "MacBox" as CFString,
            nil,
            authorization
        ) else {
            throw NetworkConfigurationError.authorization("Could not open network preferences.")
        }

        guard SCPreferencesLock(preferences, true) else {
            throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not lock network preferences."))
        }

        var shouldUnlock = true
        defer {
            if shouldUnlock {
                SCPreferencesUnlock(preferences)
            }
        }

        try changes(preferences)

        guard SCPreferencesCommitChanges(preferences) else {
            throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not save network preferences."))
        }

        guard SCPreferencesApplyChanges(preferences) else {
            throw NetworkConfigurationError.systemConfiguration(lastSCError("Could not apply network preferences."))
        }

        SCPreferencesUnlock(preferences)
        shouldUnlock = false
    }

    private func makeAuthorization() throws -> AuthorizationRef {
        var authorization: AuthorizationRef?
        let status = AuthorizationCreate(
            nil,
            nil,
            [.interactionAllowed, .extendRights, .preAuthorize],
            &authorization
        )

        guard status == errAuthorizationSuccess, let authorization else {
            throw NetworkConfigurationError.authorization("Administrator approval is required.")
        }

        return authorization
    }

    private func lastSCError(_ fallback: String) -> String {
        let rawError = SCErrorString(SCError())
        let message = String(cString: rawError)
        return message.isEmpty ? fallback : message
    }
}

enum NetworkConfigurationError: Error, LocalizedError {
    case authorization(String)
    case notFound(String)
    case systemConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .authorization(let message),
             .notFound(let message),
             .systemConfiguration(let message):
            return message
        }
    }
}
