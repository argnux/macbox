import Foundation

enum PacketParserRegistry {
    static let parsers: [PacketParser] = [
        RawPacketParser(),
        ASCIIPacketParser(),
        MAVLinkPacketParser()
    ]

    static var metadata: [ParserMeta] {
        parsers.map {
            ParserMeta(id: $0.id, name: $0.name, description: $0.description)
        }
    }

    static func parser(id: String) -> PacketParser {
        parsers.first { $0.id == id } ?? parsers[0]
    }
}

struct RawPacketParser: PacketParser {
    let id = "raw"
    let name = "Raw Hex"
    let description = "Displays raw bytes without decoding"

    func parse(_ data: Data) -> ParsedOutput {
        ParsedOutput(message: "Raw bytes mode. See Hex Dump below.")
    }
}

struct ASCIIPacketParser: PacketParser {
    let id = "ascii"
    let name = "ASCII"
    let description = "Displays printable ASCII characters, replaces others with '.'"

    func parse(_ data: Data) -> ParsedOutput {
        guard !data.isEmpty else {
            return ParsedOutput(message: "<Empty Payload>")
        }

        var printableCount = 0
        let text = data.map { byte -> Character in
            if byte >= 32, byte <= 126 {
                printableCount += 1
                return Character(UnicodeScalar(byte))
            }
            return "."
        }

        let isText = Double(printableCount) / Double(data.count) > 0.9
        let rows = [
            ParsedRow(key: "total_bytes", value: "\(data.count)"),
            ParsedRow(key: "printable_bytes", value: "\(printableCount)"),
            ParsedRow(key: "heuristic_guess", value: isText ? "Likely Text" : "Binary Data")
        ]

        return ParsedOutput(
            message: String(text),
            rows: rows,
            jsonText: """
            {
              "message": "\(String(text).jsonEscaped)",
              "stats": {
                "total_bytes": \(data.count),
                "printable_bytes": \(printableCount),
                "heuristic_guess": "\(isText ? "Likely Text" : "Binary Data")"
              }
            }
            """
        )
    }
}

struct MAVLinkPacketParser: PacketParser {
    let id = "mavlink"
    let name = "MAVLink Parser"
    let description = "Decode MAVLink v1/v2 packets"

    func parse(_ data: Data) -> ParsedOutput {
        guard let frame = MAVLinkFrame(data: data) else {
            return ParsedOutput(
                message: nil,
                rows: [ParsedRow(key: "error", value: "Decode error")],
                jsonText: #"{"error":"decode error"}"#
            )
        }

        var rows = [
            ParsedRow(key: "system_id", value: "\(frame.systemID)"),
            ParsedRow(key: "component_id", value: "\(frame.componentID)"),
            ParsedRow(key: "message_id", value: "\(frame.messageID)"),
            ParsedRow(key: "name", value: frame.messageName)
        ]

        rows.append(contentsOf: frame.summaryRows)

        return ParsedOutput(
            rows: rows,
            jsonText: frame.jsonText
        )
    }
}

private struct MAVLinkFrame {
    var version: Int
    var systemID: UInt8
    var componentID: UInt8
    var messageID: UInt32
    var payload: Data

    init?(data: Data) {
        guard let magic = data.first else { return nil }

        switch magic {
        case 0xFE:
            guard data.count >= 8 else { return nil }
            let payloadLength = Int(data[1])
            let payloadStart = 6
            guard data.count >= payloadStart + payloadLength + 2 else { return nil }
            version = 1
            systemID = data[3]
            componentID = data[4]
            messageID = UInt32(data[5])
            payload = data.subdata(in: payloadStart..<(payloadStart + payloadLength))

        case 0xFD:
            guard data.count >= 12 else { return nil }
            let payloadLength = Int(data[1])
            let payloadStart = 10
            guard data.count >= payloadStart + payloadLength + 2 else { return nil }
            version = 2
            systemID = data[5]
            componentID = data[6]
            messageID = UInt32(data[7]) | (UInt32(data[8]) << 8) | (UInt32(data[9]) << 16)
            payload = data.subdata(in: payloadStart..<(payloadStart + payloadLength))

        default:
            return nil
        }
    }

    var messageName: String {
        switch messageID {
        case 0: "HEARTBEAT"
        case 1: "SYS_STATUS"
        case 30: "ATTITUDE"
        case 33: "GLOBAL_POSITION_INT"
        default: "MESSAGE_\(messageID)"
        }
    }

    var summaryRows: [ParsedRow] {
        switch messageID {
        case 0: heartbeatRows
        case 1: systemStatusRows
        case 30: attitudeRows
        case 33: globalPositionRows
        default: []
        }
    }

    var jsonText: String {
        let rowJSON = summaryRows
            .map { #"    "\#($0.key.jsonEscaped)": "\#($0.value.jsonEscaped)""# }
            .joined(separator: ",\n")
        let summary = rowJSON.isEmpty ? "{}" : "{\n\(rowJSON)\n  }"

        return """
        {
          "system_id": \(systemID),
          "component_id": \(componentID),
          "message_id": \(messageID),
          "name": "\(messageName)",
          "summary": \(summary),
          "payload_hex": "\(payload.hexString)"
        }
        """
    }

    private var heartbeatRows: [ParsedRow] {
        guard payload.count >= 9 else { return [] }
        let baseMode = payload[6]
        let armed = (baseMode & 128) != 0
        return [
            ParsedRow(key: "State", value: armed ? "ARMED" : "DISARMED"),
            ParsedRow(key: "Mav Type", value: "\(payload[4])"),
            ParsedRow(key: "Mode", value: "Base: \(baseMode) / Custom: \(payload.uint32LE(at: 0) ?? 0)")
        ]
    }

    private var attitudeRows: [ParsedRow] {
        guard payload.count >= 28 else { return [] }
        return [
            ParsedRow(key: "Roll", value: payload.float32LE(at: 4)?.degreesString ?? ""),
            ParsedRow(key: "Pitch", value: payload.float32LE(at: 8)?.degreesString ?? ""),
            ParsedRow(key: "Yaw", value: payload.float32LE(at: 12)?.degreesString ?? "")
        ]
    }

    private var globalPositionRows: [ParsedRow] {
        guard payload.count >= 30 else { return [] }
        let lat = Double(payload.int32LE(at: 4) ?? 0) / 10_000_000.0
        let lon = Double(payload.int32LE(at: 8) ?? 0) / 10_000_000.0
        let relativeAlt = Double(payload.int32LE(at: 16) ?? 0) / 1_000.0
        let heading = Double(payload.uint16LE(at: 28) ?? 0) / 100.0
        return [
            ParsedRow(key: "Lat", value: String(format: "%.7f", lat)),
            ParsedRow(key: "Lon", value: String(format: "%.7f", lon)),
            ParsedRow(key: "Alt", value: String(format: "%.2f m", relativeAlt)),
            ParsedRow(key: "Heading", value: String(format: "%.2f", heading))
        ]
    }

    private var systemStatusRows: [ParsedRow] {
        guard payload.count >= 18 else { return [] }
        let voltage = Double(payload.uint16LE(at: 14) ?? 0) / 1_000.0
        let current = Double(payload.int16LE(at: 16) ?? 0) / 100.0
        let load = Int(payload.uint16LE(at: 12) ?? 0) / 10
        return [
            ParsedRow(key: "Battery", value: String(format: "%.2f V", voltage)),
            ParsedRow(key: "Current", value: String(format: "%.2f A", current)),
            ParsedRow(key: "CPU Load", value: "\(load) %")
        ]
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    func uint16LE(at offset: Int) -> UInt16? {
        guard count >= offset + 2 else { return nil }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func int16LE(at offset: Int) -> Int16? {
        guard let value = uint16LE(at: offset) else { return nil }
        return Int16(bitPattern: value)
    }

    func uint32LE(at offset: Int) -> UInt32? {
        guard count >= offset + 4 else { return nil }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func int32LE(at offset: Int) -> Int32? {
        guard let value = uint32LE(at: offset) else { return nil }
        return Int32(bitPattern: value)
    }

    func float32LE(at offset: Int) -> Float? {
        guard let raw = uint32LE(at: offset) else { return nil }
        return Float(bitPattern: raw)
    }
}

private extension Float {
    var degreesString: String {
        String(format: "%.1f deg", Double(self) * 180.0 / Double.pi)
    }
}

private extension String {
    var jsonEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
