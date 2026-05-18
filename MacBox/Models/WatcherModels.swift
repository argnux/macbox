import Foundation

enum WatchProtocol: String, CaseIterable, Identifiable {
    case udp
    case tcp

    var id: String { rawValue }

    var title: String {
        rawValue.uppercased()
    }
}

struct ParserMeta: Identifiable, Hashable {
    var id: String
    var name: String
    var description: String
}

struct WatcherConfig: Hashable {
    var protocolType: WatchProtocol = .udp
    var port: Int = 8080
    var parserID: String = "raw"
}

struct CapturedPacket: Identifiable, Hashable {
    var id: Int64
    var timestamp: Date
    var formattedTime: String
    var protocolName: String
    var parserID: String
    var size: Int
    var payload: Data
    var preview: String
    var hexDump: String
    var parsedOutput: ParsedOutput
    var fromIP: String
    var port: Int
}

struct ParsedOutput: Hashable {
    var message: String?
    var rows: [ParsedRow] = []
    var jsonText: String = "{}"
}

struct ParsedRow: Identifiable, Hashable {
    var id = UUID()
    var key: String
    var value: String
}

protocol PacketParser {
    var id: String { get }
    var name: String { get }
    var description: String { get }

    func parse(_ data: Data) -> ParsedOutput
}
