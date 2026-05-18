import Foundation

struct HardwareInterface: Identifiable, Hashable {
    var id: String { device }

    var name: String
    var device: String
    var mac: String
    var isActive: Bool
    var logicInterfaces: [LogicInterface]
}

struct LogicInterface: Identifiable, Hashable {
    var id: String
    var name: String
    var device: String
    var ip: String
    var mask: String
    var gateway: String
    var method: IPMethod
}

enum IPMethod: String, CaseIterable, Identifiable, Hashable {
    case dhcp = "DHCP"
    case manual = "Manual"
    case unknown = "Unknown"
    case autoOther = "Auto/Other"

    var id: String { rawValue }

    static var editableCases: [IPMethod] {
        [.dhcp, .manual]
    }
}

struct InterfaceUpdatePayload: Hashable {
    var oldName: String
    var newName: String
    var method: IPMethod
    var ip: String
    var mask: String
    var gateway: String
}
