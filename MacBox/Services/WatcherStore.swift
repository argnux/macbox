import Foundation
import Network

final class WatcherStore: ObservableObject {
    @Published var config = WatcherConfig()
    @Published private(set) var isRunning = false
    @Published private(set) var packets: [CapturedPacket] = []
    @Published var selectedPacketID: CapturedPacket.ID?
    @Published var autoScroll = true
    @Published var errorMessage: String?

    let availableParsers = PacketParserRegistry.metadata

    private let queue = DispatchQueue(label: "MacBox.Watcher")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var nextPacketID: Int64 = 0
    private var pendingPackets: [CapturedPacket] = []
    private var pendingFlushWorkItem: DispatchWorkItem?
    private let maxPackets = 1_000
    private let packetBatchInterval: TimeInterval = 0.08
    private let packetBatchLimit = 40

    var selectedPacket: CapturedPacket? {
        guard let selectedPacketID else { return nil }
        return packets.first { $0.id == selectedPacketID }
    }

    func start() {
        guard !isRunning else { return }
        guard (1...65_535).contains(config.port),
              let port = NWEndpoint.Port(rawValue: UInt16(config.port)) else {
            errorMessage = "Port must be between 1 and 65535."
            return
        }

        let protocolType = config.protocolType
        let listenPort = config.port
        let parserID = config.parserID
        let parser = PacketParserRegistry.parser(id: parserID)
        let parameters: NWParameters = protocolType == .udp ? .udp : .tcp

        do {
            let listener = try NWListener(using: parameters, on: port)
            self.listener = listener
            isRunning = true
            errorMessage = nil

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .failed(let error):
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.stop()
                    }
                case .cancelled:
                    DispatchQueue.main.async {
                        self.isRunning = false
                    }
                case .waiting(let error):
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                    }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }

                DispatchQueue.main.async {
                    self.connections[ObjectIdentifier(connection)] = connection
                }

                connection.start(queue: self.queue)
                if protocolType == .tcp {
                    self.receiveStream(on: connection, protocolType: protocolType, parserID: parserID, parser: parser, port: listenPort)
                } else {
                    self.receiveDatagram(on: connection, protocolType: protocolType, parserID: parserID, parser: parser, port: listenPort)
                }
            }

            listener.start(queue: queue)
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        queue.async { [weak self] in
            self?.flushPendingPackets()
        }
        isRunning = false
    }

    func clearPackets() {
        packets.removeAll()
        selectedPacketID = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingFlushWorkItem?.cancel()
            self.pendingFlushWorkItem = nil
            self.pendingPackets.removeAll()
            self.nextPacketID = 0
        }
    }

    private func receiveDatagram(
        on connection: NWConnection,
        protocolType: WatchProtocol,
        parserID: String,
        parser: PacketParser,
        port: Int
    ) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.appendPacket(data: data, from: connection.endpoint, protocolType: protocolType, parserID: parserID, parser: parser, port: port)
            }

            if error == nil {
                self.receiveDatagram(on: connection, protocolType: protocolType, parserID: parserID, parser: parser, port: port)
            } else {
                self.removeConnection(connection)
            }
        }
    }

    private func receiveStream(
        on connection: NWConnection,
        protocolType: WatchProtocol,
        parserID: String,
        parser: PacketParser,
        port: Int
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.appendPacket(data: data, from: connection.endpoint, protocolType: protocolType, parserID: parserID, parser: parser, port: port)
            }

            if error == nil, !isComplete {
                self.receiveStream(on: connection, protocolType: protocolType, parserID: parserID, parser: parser, port: port)
            } else {
                self.removeConnection(connection)
            }
        }
    }

    private func appendPacket(
        data: Data,
        from endpoint: NWEndpoint,
        protocolType: WatchProtocol,
        parserID: String,
        parser: PacketParser,
        port: Int
    ) {
        let parsedOutput = parser.parse(data)
        let remote = endpoint.displayName
        let timestamp = Date()
        let packet = CapturedPacket(
            id: nextPacketID,
            timestamp: timestamp,
            formattedTime: PacketDisplayFormatter.formattedTime(timestamp),
            protocolName: protocolType.rawValue,
            parserID: parserID,
            size: data.count,
            payload: data,
            preview: PacketDisplayFormatter.preview(data),
            hexDump: PacketDisplayFormatter.hexDump(data),
            parsedOutput: parsedOutput,
            fromIP: remote,
            port: port
        )

        nextPacketID += 1
        pendingPackets.append(packet)

        if pendingPackets.count >= packetBatchLimit {
            flushPendingPackets()
        } else {
            schedulePacketFlush()
        }
    }

    private func schedulePacketFlush() {
        guard pendingFlushWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingPackets()
        }
        pendingFlushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + packetBatchInterval, execute: workItem)
    }

    private func flushPendingPackets() {
        pendingFlushWorkItem?.cancel()
        pendingFlushWorkItem = nil

        guard !pendingPackets.isEmpty else { return }

        let packetsToAppend = pendingPackets
        pendingPackets.removeAll(keepingCapacity: true)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.packets.append(contentsOf: packetsToAppend)

            if self.packets.count > self.maxPackets {
                self.packets.removeFirst(self.packets.count - self.maxPackets)
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        DispatchQueue.main.async {
            self.connections.removeValue(forKey: ObjectIdentifier(connection))
        }
    }
}

private enum PacketDisplayFormatter {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func formattedTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func preview(_ data: Data) -> String {
        let bytes = data.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
        return data.count > 12 ? "\(bytes)..." : bytes
    }

    static func hexDump(_ data: Data) -> String {
        data.enumerated().reduce(into: "") { result, pair in
            if pair.offset > 0, pair.offset.isMultiple(of: 16) {
                result += "\n"
            }
            result += String(format: "%02X ", pair.element)
        }
    }
}

private extension NWEndpoint {
    var displayName: String {
        switch self {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        case .service(let name, let type, let domain, _):
            return "\(name).\(type).\(domain)"
        case .unix(let path):
            return path
        case .url(let url):
            return url.absoluteString
        case .opaque:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
}
