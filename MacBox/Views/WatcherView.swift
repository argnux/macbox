import SwiftUI

struct WatcherView: View {
    @ObservedObject var store: WatcherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Packet Watcher")
                .font(.title2.weight(.semibold))

            controls

            HSplitView {
                PacketListView(store: store)
                    .frame(minWidth: 440)

                PacketInspectorView(packet: store.selectedPacket)
                    .frame(minWidth: 360)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16))
            )
        }
        .padding(20)
        .alert("Watcher Error", isPresented: errorBinding) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Protocol", selection: $store.config.protocolType) {
                ForEach(WatchProtocol.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .frame(width: 130)
            .disabled(store.isRunning)

            TextField("Port", value: $store.config.port, formatter: NumberFormatter.port)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .disabled(store.isRunning)

            Picker("Parser", selection: $store.config.parserID) {
                ForEach(store.availableParsers) { parser in
                    Text(parser.name).tag(parser.id)
                }
            }
            .frame(width: 220)
            .disabled(store.isRunning)

            Button {
                if store.isRunning {
                    store.stop()
                } else {
                    store.start()
                }
            } label: {
                Label(store.isRunning ? "Stop" : "Start Listening", systemImage: store.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(store.isRunning ? .red : .green)

            Button {
                store.clearPackets()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(store.packets.isEmpty)

            Spacer()

            Toggle("Auto-scroll", isOn: $store.autoScroll)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14))
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    store.errorMessage = nil
                }
            }
        )
    }
}

private struct PacketListView: View {
    @ObservedObject var store: WatcherStore

    var body: some View {
        VStack(spacing: 0) {
            PacketHeaderRow()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.packets) { packet in
                            PacketRow(
                                packet: packet,
                                isSelected: store.selectedPacketID == packet.id
                            )
                            .id(packet.id)
                            .onTapGesture {
                                store.selectedPacketID = packet.id
                            }

                            Divider()
                        }
                    }
                }
                .onReceive(store.$packets) { packets in
                    guard store.autoScroll, let lastID = packets.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

private struct PacketHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            HeaderText("Time", width: 96)
            HeaderText("Size", width: 70, alignment: .trailing)
            HeaderText("From", width: 160)
            HeaderText("Preview", width: nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PacketRow: View {
    var packet: CapturedPacket
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(packet.formattedTime)
                .frame(width: 96, alignment: .leading)
            Text("\(packet.size) B")
                .frame(width: 70, alignment: .trailing)
            Text(packet.fromIP)
                .frame(width: 160, alignment: .leading)
            Text(packet.preview)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
    }
}

private struct PacketInspectorView: View {
    var packet: CapturedPacket?

    var body: some View {
        Group {
            if let packet {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Text(packet.protocolName.uppercased())
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.16), in: Capsule())
                            Text("Port: \(packet.port)")
                            Text("Size: \(packet.size) bytes")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        InspectorSection(title: "Parsed Output (\(packet.parserID))") {
                            if let message = packet.parsedOutput.message {
                                CodeBlock(message)
                            }

                            if !packet.parsedOutput.rows.isEmpty {
                                ParsedRows(rows: packet.parsedOutput.rows)
                            }

                            if packet.parsedOutput.message == nil, packet.parsedOutput.rows.isEmpty {
                                CodeBlock(packet.parsedOutput.jsonText)
                            }
                        }

                        InspectorSection(title: "Raw Hex Dump") {
                            CodeBlock(packet.hexDump)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                    Text("Select a packet")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ParsedRows: View {
    var rows: [ParsedRow]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.key)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

private struct CodeBlock: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct HeaderText: View {
    var title: String
    var width: CGFloat?
    var alignment: Alignment

    init(_ title: String, width: CGFloat?, alignment: Alignment = .leading) {
        self.title = title
        self.width = width
        self.alignment = alignment
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

private extension NumberFormatter {
    static var port: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: 1)
        formatter.maximum = NSNumber(value: 65_535)
        return formatter
    }
}

private extension CapturedPacket {
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var preview: String {
        let bytes = payload.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
        return size > 12 ? "\(bytes)..." : bytes
    }

    var hexDump: String {
        payload.enumerated().reduce(into: "") { result, pair in
            if pair.offset > 0, pair.offset.isMultiple(of: 16) {
                result += "\n"
            }
            result += String(format: "%02X ", pair.element)
        }
    }
}
