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
    private let maxPackets = 1_000

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
        isRunning = false
    }

    func clearPackets() {
        packets.removeAll()
        selectedPacketID = nil
        nextPacketID = 0
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

        DispatchQueue.main.async {
            let packet = CapturedPacket(
                id: self.nextPacketID,
                timestamp: Date(),
                protocolName: protocolType.rawValue,
                parserID: parserID,
                size: data.count,
                payload: data,
                parsedOutput: parsedOutput,
                fromIP: remote,
                port: port
            )

            self.nextPacketID += 1
            self.packets.append(packet)

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
